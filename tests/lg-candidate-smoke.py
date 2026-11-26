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
AUTH_CLIENT = "LG candidate smoke"
RESULTS = []


def request(path, method="GET", body=None):
    headers = {"Authorization": f'MediaBrowser Client="{AUTH_CLIENT}", Device="scratch", DeviceId="lg-candidate-smoke", Version="1"'}
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
    global TOKEN, AUTH_CLIENT
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
    request("/Library/VirtualFolders?name=Scratch&collectionType=movies&paths=/media&refreshLibrary=true", "POST", {
        "LibraryOptions": {"PathInfos": [{"Path": "/media"}], "EnableRealtimeMonitor": False,
                           "EnableInternetProviders": False, "EnableAutomaticSeriesGrouping": False}
    })
    items = []
    for attempt in range(60):
        items = request(f"/Items?Recursive=true&IncludeItemTypes=Movie&Fields=MediaSources&UserId={user}")["Items"]
        if len(items) == 4 and all(i.get("MediaSources") for i in items):
            break
        if attempt == 12:
            request("/Library/Refresh", "POST")
        time.sleep(2)
    # Keep only synthetic names/counts, never negotiations or token-bearing URLs.
    (ROOT / "scan-summary.json").write_text(json.dumps({"count": len(items), "names": [i["Name"] for i in items]}, indent=2))
    check("four synthetic fixtures scanned", len(items) == 4 and all(i.get("MediaSources") for i in items))
    fixture_names = {"SyntheticAlpha": "h264", "SyntheticBravo": "hevc", "SyntheticCharlie": "aac", "SyntheticDelta": "mixed"}
    items = {fixture_names[pathlib.Path(i["MediaSources"][0]["Path"]).stem]: i for i in items}
    profile = {
        "MaxStreamingBitrate": 200000000,
        "DirectPlayProfiles": [{"Type": "Video", "Container": "mkv,mp4", "VideoCodec": "h264,hevc", "AudioCodec": "aac"}],
        "TranscodingProfiles": [{"Type": "Video", "Container": "mp4", "VideoCodec": "h264,hevc", "AudioCodec": "aac",
                                 "Protocol": "hls", "Context": "Streaming", "MaxAudioChannels": "6", "MinSegments": 1}],
    }

    def negotiate(name, audio_index=1, compatibility=False, max_bitrate=200000000):
        item = items[name]
        body = {"MediaSourceId": item["MediaSources"][0]["Id"], "UserId": user, "DeviceProfile": profile,
                "AudioStreamIndex": audio_index, "MaxAudioChannels": 6, "MaxStreamingBitrate": max_bitrate,
                "EnableDirectPlay": True, "EnableDirectStream": True, "EnableTranscoding": True,
                "AllowVideoStreamCopy": True, "AllowAudioStreamCopy": True, "IsPlayback": True}
        if compatibility:
            video_profile = {**profile["TranscodingProfiles"][0], "MaxAudioChannels": "2"}
            body.update(DeviceProfile={**profile, "DirectPlayProfiles": [], "TranscodingProfiles": [video_profile]},
                        MaxAudioChannels=2, EnableDirectPlay=False, EnableDirectStream=True,
                        AllowAudioStreamCopy=False, AlwaysBurnInSubtitleWhenTranscoding=False)
        return request(f'/Items/{item["Id"]}/PlaybackInfo', "POST", body)

    def probe_stream(name, source):
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
        (ROOT / f"{name}-probe.json").write_bytes(probe)
        return json.loads(probe)["streams"]

    check("AAC compatible direct-play control", negotiate("aac")["MediaSources"][0]["SupportsDirectPlay"])
    for codec in ("h264", "hevc"):
        source = negotiate(codec)["MediaSources"][0]
        check(codec + " offers incompatible-audio remux", not source["SupportsDirectPlay"] and bool(source.get("TranscodingUrl")))
        streams = probe_stream(codec, source)
        check(codec + " executed video and AAC6", any(s["codec_name"] == codec for s in streams)
              and any(s["codec_name"] == "aac" and s.get("channels") == 6 for s in streams))

    AUTH_CLIENT = "Jellyfin iOS"
    for codec, index in (("eac3", 1), ("he-aac", 2)):
        source = negotiate("mixed", index, compatibility=True)["MediaSources"][0]
        url = urllib.parse.urlsplit(source["TranscodingUrl"])
        params = {key.lower(): value for key, value in urllib.parse.parse_qsl(url.query)}
        (ROOT / f"{codec}-negotiation.json").write_text(json.dumps({
            "source": {key: source.get(key) for key in ("SupportsDirectPlay", "SupportsDirectStream", "SupportsTranscoding",
                        "TranscodingSubProtocol", "TranscodingContainer", "DefaultAudioStreamIndex")},
            "manifest": url.path.endswith(".m3u8"),
            "parameters": {key: params.get(key) for key in ("audiocodec", "transcodingmaxaudiochannels",
                           "allowaudiostreamcopy", "segmentcontainer", "audiostreamindex")}
        }, indent=2))
        check(codec + " uses the selected real index and dynamic HLS", not source["SupportsDirectPlay"]
              and not source["SupportsDirectStream"] and source["TranscodingSubProtocol"] == "hls"
              and source["TranscodingContainer"] == "mp4" and source["DefaultAudioStreamIndex"] == index
              and url.path.endswith(".m3u8") and params.get("audiocodec") == "aac"
              and params.get("segmentcontainer") == "mp4" and params.get("audiostreamindex") == str(index)
              and params.get("transcodingmaxaudiochannels") == "2" and params.get("allowaudiostreamcopy") == "false")
        streams = probe_stream(codec, source)
        check(codec + " yields H.264 and AAC-LC stereo", any(s["codec_name"] == "h264" for s in streams)
              and any(s["codec_name"] == "aac" and s.get("profile") == "LC" and s.get("channels") == 2
                      and s.get("channel_layout") == "stereo" for s in streams))

    def probe_denied_request(name, result):
        sources = result.get("MediaSources", [])
        url = next((source["TranscodingUrl"] for source in sources if source.get("TranscodingUrl")), None)
        if url is None:
            return []
        try:
            return probe_stream(name, {"TranscodingUrl": url})
        except urllib.error.HTTPError as error:
            if error.code in (400, 403, 404, 500):
                return []
            raise

    # PlaybackInfo can advertise a URL even when permissions prohibit encoding.
    # Exercise the URL and accept rejection or source copy, never re-encoding.
    streams = probe_denied_request("denied-video", negotiate("mixed", compatibility=True, max_bitrate=100000))
    check("bitrate cannot cause video re-encoding under the remux-only policy", not streams
          or any(s["codec_name"] == "h264" for s in streams))
    policy["EnableAudioPlaybackTranscoding"] = False
    request(f"/Users/{user}/Policy", "POST", policy)
    streams = probe_denied_request("denied-audio", negotiate("mixed", compatibility=True))
    check("audio re-encoding requires permission", not streams or any(s["codec_name"] == "eac3" for s in streams))
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
