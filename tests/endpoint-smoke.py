import json, urllib.request, urllib.parse, urllib.error, time, pathlib, subprocess, re, os, sys
E=pathlib.Path(os.environ['SMOKE_DIR'])
BASE='http://127.0.0.1:18096'
CANDIDATE_IMAGE=os.environ['CANDIDATE_IMAGE']
results=[]
# Server-generated URLs may contain test access tokens; never emit traceback URLs to CI logs.
sys.excepthook = lambda kind, value, trace: print(f'Endpoint smoke failed: {kind.__name__}', file=sys.stderr)
def req(path, method='GET', body=None, token=None, client='Jellyfin iOS'):
    headers={'Authorization':f'MediaBrowser Client="{client}", Device="isolated-test", DeviceId="{client}", Version="1.8.0"'}
    if token: headers['Authorization'] += f', Token="{token}"'
    if body is not None: headers['Content-Type']='application/json'
    r=urllib.request.urlopen(urllib.request.Request(BASE+urllib.parse.quote(path,safe='/?&=,%:+'), data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method),timeout=90)
    data=r.read()
    return json.loads(data) if data and 'json' in r.headers.get('Content-Type','') else data

def check(name, condition, detail=None):
    results.append({'name':name,'passed':bool(condition)})
    (E/'endpoint-results.json').write_text(json.dumps(results,indent=2))
    assert condition, name

if not req('/System/Info/Public')['StartupWizardCompleted']:
    req('/Startup/Configuration','POST',{'UICulture':'en-US','MetadataCountryCode':'US','PreferredMetadataLanguage':'en'})
    req('/Startup/User')
    req('/Startup/User','POST',{'Name':'scratch','Password':'scratch-isolated-only'})
    req('/Startup/Complete','POST',{})
auth={c:req('/Users/AuthenticateByName','POST',{'Username':'scratch','Pw':'scratch-isolated-only'},client=c) for c in ['Jellyfin iOS','Jellyfin Android','Safari','Jellyfin iOS unofficial']}
admin=auth['Jellyfin iOS']['AccessToken']; user=auth['Jellyfin iOS']['User']['Id']
policy=auth['Jellyfin iOS']['User']['Policy']; policy['EnableVideoPlaybackTranscoding']=False; policy['EnableAudioPlaybackTranscoding']=True; policy['EnablePlaybackRemuxing']=True
req('/Users/'+user+'/Policy','POST',policy,admin)
if not req('/Library/VirtualFolders',token=admin):
    req('/Library/VirtualFolders?'+urllib.parse.urlencode({'name':'Scratch','collectionType':'movies','refreshLibrary':'true'}),'POST',{'LibraryOptions':{'PathInfos':[{'Path':'/media'}],'EnableRealtimeMonitor':False}},admin)
items=[]
for _ in range(60):
    items=req('/Items?Recursive=true&IncludeItemTypes=Movie&Fields=MediaSources&UserId='+user,token=admin)['Items']
    if len(items)==3 and all(i.get('MediaSources') for i in items): break
    time.sleep(2)
check('scratch library scanned',len(items)==3,[i['Name'] for i in items])
items={pathlib.Path(i['MediaSources'][0]['Path']).stem:i for i in items}
def negotiate(name,protocol='http',client='Jellyfin iOS',track=1):
    token=auth[client]['AccessToken']
    profile={'DirectPlayProfiles':[{'Type':'Video','Container':'mkv,mp4','VideoCodec':'h264','AudioCodec':'aac,eac3'}], 'TranscodingProfiles':[{'Type':'Video','Container':'mp4','VideoCodec':'h264','AudioCodec':'aac,eac3','Protocol':protocol,'Context':'Streaming'}]}
    body={'MediaSourceId':items[name]['MediaSources'][0]['Id'],'UserId':user,'DeviceProfile':profile,'AudioStreamIndex':track,'MaxAudioChannels':6,'EnableDirectPlay':True,'EnableDirectStream':True,'EnableTranscoding':True,'AllowVideoStreamCopy':True,'AllowAudioStreamCopy':True,'IsPlayback':True}
    result=req('/Items/'+items[name]['Id']+'/PlaybackInfo','POST',body,token,client)
    return result['MediaSources'][0], result, token
for client in ['Jellyfin Android','Safari','Jellyfin iOS unofficial']:
    source,_,_=negotiate('eac3',client=client)
    check('non-iOS unchanged '+client,source['SupportsDirectPlay'],source)
source,_,_=negotiate('aac')
check('AAC stereo passthrough',source['SupportsDirectPlay'],source)
for protocol in ['http','hls']:
    source,result,token=negotiate('eac3',protocol)
    check(protocol+' AAC stereo negotiation',not source['SupportsDirectPlay'] and 'AudioCodec=aac' in source.get('TranscodingUrl','') and 'MaxAudioChannels=2' in source['TranscodingUrl'],source)
    url=source['TranscodingUrl']
    data=req('/'+url.lstrip('/')+('&' if '?' in url else '?')+'api_key='+token,token=token)
    if protocol=='http':
        output=E/'progressive.mp4'; output.write_bytes(data)
        subprocess.run(['docker','run','--rm','--label','campaign=dekopon','--name','dekopon-native-probe-http','-v',str(E)+':/e:ro','--entrypoint','/usr/lib/jellyfin-ffmpeg/ffprobe',CANDIDATE_IMAGE,'-v','error','-show_streams','-of','json','/e/progressive.mp4'],stdout=(E/'progressive-probe.json').open('w'),check=True)
        streams=json.load(open(E/'progressive-probe.json'))['streams']
        check('progressive executed AAC stereo H264',any(s['codec_name']=='aac' and s['channels']<=2 for s in streams) and any(s['codec_name']=='h264' for s in streams),streams)
    else:
        (E/'hls-master.m3u8').write_bytes(data)
        # Download the media playlist and first fragment using server-generated URLs.
        playlist=data.decode(); baseurl=urllib.parse.urljoin(BASE+'/',url)
        child=next(l for l in playlist.splitlines() if l and not l.startswith('#'))
        childurl=urllib.parse.urljoin(baseurl,child)
        media=req(childurl.removeprefix(BASE),token=token)
        (E/'hls-media.m3u8').write_bytes(media)
        # Probe server-generated stream while the isolated server is reachable from the host.
        check('HLS media playlist returned',b'#EXTINF' in media,media.decode())
        text=media.decode()
        init=re.search(r'#EXT-X-MAP:URI="([^"]+)"',text).group(1)
        fragment=next(l for l in text.splitlines() if l and not l.startswith('#'))
        initdata=req(urllib.parse.urljoin(childurl,init).removeprefix(BASE),token=token)
        fragdata=req(urllib.parse.urljoin(childurl,fragment).removeprefix(BASE),token=token)
        (E/'hls-fragment.mp4').write_bytes(initdata+fragdata)
        subprocess.run(['docker','run','--rm','--label','campaign=dekopon','--name','dekopon-native-probe-hls','-v',str(E)+':/e:ro','--entrypoint','/usr/lib/jellyfin-ffmpeg/ffprobe',CANDIDATE_IMAGE,'-v','error','-show_streams','-of','json','/e/hls-fragment.mp4'],stdout=(E/'hls-probe.json').open('w'),check=True)
        streams=json.load(open(E/'hls-probe.json'))['streams']
        check('HLS fragment executed AAC stereo H264',any(s['codec_name']=='aac' and s['channels']<=2 for s in streams) and any(s['codec_name']=='h264' for s in streams),streams)
source,_,_=negotiate('mixed',track=2)
check('selected EAC3 second track negotiation',not source['SupportsDirectPlay'] and 'AudioStreamIndex=2' in source.get('TranscodingUrl',''),source)
source,_,_=negotiate('mixed',track=1)
check('selected AAC first track dynamic path',not source['SupportsDirectPlay'],source)
# A static request must not return the original EAC3 file; incompatible requested video must not encode.
def status(path):
    try: req(path,token=admin); return 200
    except urllib.error.HTTPError as e:
        (E/f'http-error-{e.code}.txt').write_bytes(e.read())
        return e.code
item=items['eac3']
path='/Videos/'+item['Id']+'/stream.mp4?'+urllib.parse.urlencode({'MediaSourceId':item['MediaSources'][0]['Id'],'AudioStreamIndex':1,'Static':'true'})
code=status(path)
check('static bypass rejected',code==400,code)
source,_,_=negotiate('eac3')
url=source['TranscodingUrl']
url=re.sub(r'VideoCodec=h264','VideoCodec=hevc',url)+'&AllowVideoStreamCopy=false'
data=req(url,token=admin)
(E/'video-denied.mp4').write_bytes(data)
subprocess.run(['docker','run','--rm','--label','campaign=dekopon','--name','dekopon-native-probe-video-denied','-v',str(E)+':/e:ro','--entrypoint','/usr/lib/jellyfin-ffmpeg/ffprobe',CANDIDATE_IMAGE,'-v','error','-show_streams','-of','json','/e/video-denied.mp4'],stdout=(E/'video-denied-probe.json').open('w'),check=True)
streams=json.load(open(E/'video-denied-probe.json'))['streams']
check('video permission cannot be overridden by HEVC request',any(s['codec_name']=='h264' for s in streams),streams)
policy['EnableAudioPlaybackTranscoding']=False
req('/Users/'+user+'/Policy','POST',policy,admin)
source,_,_=negotiate('eac3')
check('no audio permission does not offer encoding',not source['SupportsDirectPlay'] and not source['SupportsTranscoding'],source)
path='/Videos/'+item['Id']+'/stream.mp4?'+urllib.parse.urlencode({'MediaSourceId':item['MediaSources'][0]['Id'],'AudioStreamIndex':1,'AudioCodec':'copy','VideoCodec':'h264'})
code=status(path)
check('audio permission execution rejected',code==403 and (E/'http-error-403.txt').read_bytes()==b'Error processing request.',code)
policy['EnableAudioPlaybackTranscoding']=True; policy['EnablePlaybackRemuxing']=False
req('/Users/'+user+'/Policy','POST',policy,admin)
source,_,_=negotiate('eac3')
check('remux and video unavailable does not offer dynamic playback',not source['SupportsTranscoding'] and not source.get('TranscodingUrl'),source)
source,_,_=negotiate('aac')
check('AAC direct playback survives denied dynamic permissions',source['SupportsDirectPlay'],source)
print(f'{sum(r["passed"] for r in results)}/{len(results)} endpoint controls passed')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
