"""Isolated synthetic media checks, not LG device or migrated-database acceptance."""
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:18097"
ROOT = pathlib.Path(os.environ["SMOKE_DIR"])
IMAGE = os.environ["CANDIDATE_IMAGE"]
TOKEN = None
RESULTS = []


def request(path, method="GET", body=None):
    headers = {"Authorization": 'MediaBrowser Client="LG candidate smoke", Device="scratch", DeviceId="lg-candidate-smoke", Version="1"'}
    if TOKEN:
        headers["Authorization"] += f', Token="{TOKEN}"'
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        BASE + urllib.parse.quote(path, safe="/?&=,%:+"),
        data=json.dumps(body).encode() if body is not None else None,
        headers=headers, method=method,
    )
    with urllib.request.urlopen(req, timeout=90) as response:
        data = response.read()
        return json.loads(data) if data and "json" in response.headers.get("Content-Type", "") else data


def check(name, condition):
    RESULTS.append({"name": name, "passed": bool(condition)})
    (ROOT / "endpoint-results.json").write_text(json.dumps(RESULTS, indent=2))
    if not condition:
        raise AssertionError(name)


def media_path(url):
    resolved = urllib.parse.urljoin(BASE + "/", url)
    parsed = urllib.parse.urlsplit(resolved)
    if (parsed.scheme, parsed.netloc) != ("http", "127.0.0.1:18097"):
        raise ValueError("Unexpected media URL origin")
    return parsed.path + ("?" + parsed.query if parsed.query else "")


def run():
    global TOKEN
    info = request("/System/Info/Public")
    check("stock server version 12.3.0", info["Version"] == "12.3.0")
    request("/Startup/Configuration", "POST", {"UICulture": "en-US", "MetadataCountryCode": "US", "PreferredMetadataLanguage": "en"})
    request("/Startup/User")
    request("/Startup/User", "POST", {"Name": "scratch", "Password": "scratch-loopback-only"})
    request("/Startup/Complete", "POST", {})
    auth = request("/Users/AuthenticateByName", "POST", {"Username": "scratch", "Pw": "scratch-loopback-only"})
    TOKEN = auth["AccessToken"]
    user = auth["User"]["Id"]
    policy = auth["User"]["Policy"]
    policy.update(EnableVideoPlaybackTranscoding=False, EnableAudioPlaybackTranscoding=True, EnablePlaybackRemuxing=True)
    request(f"/Users/{user}/Policy", "POST", policy)
    request("/Library/VirtualFolders?name=Scratch&collectionType=movies&refreshLibrary=true", "POST", {
        "LibraryOptions": {"PathInfos": [{"Path": "/media"}], "EnableRealtimeMonitor": False,
                           "EnableInternetProviders": False, "EnableAutomaticSeriesGrouping": False}
    })
    items = []
    for _ in range(60):
        items = request(f"/Items?Recursive=true&IncludeItemTypes=Movie&Fields=MediaSources&UserId={user}")["Items"]
        if len(items) == 3 and all(i.get("MediaSources") for i in items):
            break
        time.sleep(2)
    check("three synthetic fixtures scanned", len(items) == 3 and all(i.get("MediaSources") for i in items))
    items = {pathlib.Path(i["MediaSources"][0]["Path"]).stem: i for i in items}
    profile = {
        "MaxStreamingBitrate": 200000000,
        "DirectPlayProfiles": [{"Type": "Video", "Container": "mkv,mp4", "VideoCodec": "h264,hevc", "AudioCodec": "aac"}],
        "TranscodingProfiles": [{"Type": "Video", "Container": "mp4", "VideoCodec": "h264,hevc", "AudioCodec": "aac",
                                 "Protocol": "hls", "Context": "Streaming", "MaxAudioChannels": "6", "MinSegments": 1}],
    }

    def negotiate(name):
        item = items[name]
        body = {"MediaSourceId": item["MediaSources"][0]["Id"], "UserId": user, "DeviceProfile": profile,
                "AudioStreamIndex": 1, "MaxAudioChannels": 6, "MaxStreamingBitrate": 200000000,
                "EnableDirectPlay": True, "EnableDirectStream": True, "EnableTranscoding": True,
                "AllowVideoStreamCopy": True, "AllowAudioStreamCopy": True, "IsPlayback": True}
        return request(f'/Items/{item["Id"]}/PlaybackInfo', "POST", body)["MediaSources"][0]

    check("AAC compatible direct-play control", negotiate("aac")["SupportsDirectPlay"])
    for name, codec in [("h264", "h264"), ("hevc", "hevc")]:
        source = negotiate(name)
        check(name + " offers incompatible-audio remux", not source["SupportsDirectPlay"] and bool(source.get("TranscodingUrl")))
        master_url = media_path(source["TranscodingUrl"])
        master = request(master_url).decode()
        child = next(line for line in master.splitlines() if line and not line.startswith("#"))
        child_url = media_path(urllib.parse.urljoin(BASE + master_url, child))
        playlist = request(child_url).decode()
        init = re.search(r'#EXT-X-MAP:URI="([^"]+)"', playlist)
        check(name + " fMP4 playlist", bool(init) and "#EXTINF" in playlist)
        fragment = next(line for line in playlist.splitlines() if line and not line.startswith("#"))
        init_data = request(media_path(urllib.parse.urljoin(BASE + child_url, init.group(1))))
        fragment_data = request(media_path(urllib.parse.urljoin(BASE + child_url, fragment)))
        (ROOT / f"{name}-fragment.mp4").write_bytes(init_data + fragment_data)
        probe = subprocess.check_output([
            "docker", "run", "--rm", "--label", "campaign=dekopon", "--name", os.environ["PROBE_NAME"],
            "-v", str(ROOT) + ":/e:ro", "--entrypoint", "/usr/lib/jellyfin-ffmpeg/ffprobe", IMAGE,
            "-v", "error", "-show_streams", "-of", "json", f"/e/{name}-fragment.mp4",
        ])
        streams = json.loads(probe)["streams"]
        # Probe output contains synthetic-fixture metadata only, never request URLs/tokens.
        (ROOT / f"{name}-probe.json").write_bytes(probe)
        check(name + " executed video and AAC6", any(s["codec_name"] == codec for s in streams)
              and any(s["codec_name"] == "aac" and s.get("channels") == 6 for s in streams))
    print(f"{len(RESULTS)}/{len(RESULTS)} synthetic checks passed; native C2 acceptance NOT tested")


try:
    run()
except Exception as error:
    # HTTP exceptions may embed access-token-bearing media URLs: report type only.
    print(f"LG candidate smoke failed: {type(error).__name__}; inspect sanitized results", file=sys.stderr)
    sys.exit(1)
finally:
    if TOKEN:
        try:
            request("/Sessions/Logout", "POST")
        except Exception:
            pass
