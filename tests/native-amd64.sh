#!/usr/bin/env bash
set -euo pipefail

[ "$(uname -m)" = x86_64 ]
[ "$(docker info --format '{{.Architecture}}')" = x86_64 ]
[ "$(docker info --format '{{.OSType}}')" = linux ]

SCRATCH=$(mktemp -d)
IMAGE=dekopon-native-aac:${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}
BUILDER=dekopon-native-aac-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}
SERVER=dekopon-native-aac-server
BUILDKIT=moby/buildkit@sha256:cec9f139f45e93c5c69c60f8b07cfad9f43f4ef6b6a6cd917527fea5ff2e3dea
# The only published test artifacts are allowlisted results, stream probes and error bodies.
ARTIFACTS="${RUNNER_TEMP:-/tmp}/native-aac-results"
mkdir -p "$ARTIFACTS" "$SCRATCH/media" "$SCRATCH/config" "$SCRATCH/cache"
cleanup() {
  status=$?
  if [ -f "$SCRATCH/endpoint-results.json" ]; then cp "$SCRATCH/endpoint-results.json" "$ARTIFACTS/"; fi
  for f in progressive-probe.json hls-probe.json video-denied-probe.json http-error-403.txt; do
    if [ -f "$SCRATCH/$f" ]; then cp "$SCRATCH/$f" "$ARTIFACTS/"; fi
  done
  docker rm -f "$SERVER" "$BUILDER" >/dev/null 2>&1 || true
  docker buildx rm "$BUILDER" >/dev/null 2>&1 || true
  docker image rm "$IMAGE" "$BUILDKIT" >/dev/null 2>&1 || true
  # Only this task's labelled BuildKit cache volume; never prune the shared builder.
  docker volume rm "$BUILDER-cache" >/dev/null 2>&1 || true
  rm -rf "$SCRATCH"
  exit "$status"
}
trap cleanup EXIT

# Dedicated BuildKit container and volume carry explicit campaign labels.
docker volume create --label campaign=dekopon --name "$BUILDER-cache" >/dev/null
docker run -d --platform linux/amd64 --privileged --network host --label campaign=dekopon --name "$BUILDER" \
  -v "$BUILDER-cache:/var/lib/buildkit" "$BUILDKIT" --addr tcp://127.0.0.1:12349 >/dev/null
docker buildx create --driver remote --name "$BUILDER" tcp://127.0.0.1:12349 >/dev/null
for attempt in $(seq 1 30); do
  if docker buildx inspect "$BUILDER" >/dev/null 2>&1; then break; fi
  sleep 2
done
docker buildx inspect "$BUILDER" >/dev/null
# Dockerfile pins all sources/assets; no fork server source is cloned or built.
docker buildx build --builder "$BUILDER" --platform linux/amd64 --pull \
  --label campaign=dekopon --load -t "$IMAGE" .
[ "$(docker image inspect "$IMAGE" --format '{{.Architecture}}')" = amd64 ]
export CANDIDATE_IMAGE="$IMAGE" SMOKE_DIR="$SCRATCH"
# Generate the same eight-second H264/EAC3, AAC and mixed-track sources used by the ARM64 smoke.
ffmpeg() {
  docker run --rm --label campaign=dekopon --name dekopon-native-fixture \
    -v "$SCRATCH/media:/media" --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg "$IMAGE" -hide_banner -loglevel error -y "$@"
}
ffmpeg -f lavfi -i testsrc2=size=320x180:rate=24 -f lavfi -i anullsrc=r=48000:cl=5.1 \
  -t 8 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a eac3 -b:a 448k /media/eac3.mkv
ffmpeg -i /media/eac3.mkv -map 0:v:0 -map 0:a:0 -c:v copy -c:a aac -ac 2 -b:a 128k /media/aac.mkv
ffmpeg -i /media/aac.mkv -i /media/eac3.mkv -map 0:v:0 -map 0:a:0 -map 1:a:0 -c copy /media/mixed.mkv

docker run -d --label campaign=dekopon --name "$SERVER" --platform linux/amd64 \
  -p 127.0.0.1:18096:8096 -v "$SCRATCH/config:/config" -v "$SCRATCH/cache:/cache" \
  -v "$SCRATCH/media:/media:ro" "$IMAGE" >/dev/null
ready=0
for attempt in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:18096/System/Info/Public >/dev/null 2>&1; then ready=1; break; fi
  if [ "$(docker inspect "$SERVER" --format '{{.State.Running}}')" != true ]; then break; fi
  sleep 2
done
[ "$ready" -eq 1 ] || { echo 'Scratch server did not become ready' >&2; exit 1; }
python3 tests/endpoint-smoke.py
# Actual transcode logs must prove video-copy + AAC2 for progressive and HLS paths.
docker logs "$SERVER" 2>&1 | grep -E -- '-codec:v:0 copy.*-codec:a:0 libfdk_aac -ac 2' | grep -q -- '-f mp4'
docker logs "$SERVER" 2>&1 | grep -E -- '-codec:v:0 copy.*-codec:a:0 libfdk_aac -ac 2' | grep -q -- '-f hls'
python3 - "$SCRATCH/endpoint-results.json" <<'PY'
import json, sys
results = json.load(open(sys.argv[1]))
assert len(results) == 18 and all(r['passed'] for r in results)
print('Native amd64: 18/18 checks and progressive/HLS video-copy commands passed')
PY
