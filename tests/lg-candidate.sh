#!/usr/bin/env bash
# Local-only candidate gate. Never mounts production config/media or publishes an image.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${WEB_ASSET_DIR:?directory containing source-owner-built jellyfin-web-dist.tar.gz}"
: "${WEB_SHA256:?reviewed archive checksum}"
: "${WEB_SOURCE_COMMIT:?web source commit}"
: "${WEB_NODE_VERSION:?producer Node version}"
: "${WEB_LOCK_SHA256:?producer package-lock.json checksum}"
: "${LG_CANDIDATE_RESULTS:?directory outside the source checkout}"

ARCH=$(docker info --format '{{.Architecture}}')
case "$ARCH" in aarch64|arm64) PLATFORM=linux/arm64;; x86_64|amd64) PLATFORM=linux/amd64;; *) exit 1;; esac
SCRATCH=$(mktemp -d)
RUN_ID="$(date -u +%Y%m%d%H%M%S)-$$"
IMAGE="jellyfin-lg-candidate:12.3-$RUN_ID"
BUILDER="jellyfin-123-builder-$RUN_ID"
SERVER="jellyfin-123-server-$RUN_ID"
FIXTURE="jellyfin-123-fixture-$RUN_ID"
export PROBE_NAME="jellyfin-123-probe-$RUN_ID"
BUILDKIT=moby/buildkit@sha256:cec9f139f45e93c5c69c60f8b07cfad9f43f4ef6b6a6cd917527fea5ff2e3dea
mkdir -p "$LG_CANDIDATE_RESULTS" "$SCRATCH/media" "$SCRATCH/config" "$SCRATCH/cache"
cleanup() {
  status=$?
  trap - EXIT
  set +e
  for file in endpoint-results.json h264-probe.json hevc-probe.json runtime.txt image-labels.json; do
    if [ -f "$SCRATCH/$file" ]; then cp "$SCRATCH/$file" "$LG_CANDIDATE_RESULTS/"; fi
  done
  docker rm -f "$SERVER" "$FIXTURE" "$PROBE_NAME" "$BUILDER" >/dev/null 2>&1
  docker buildx rm "$BUILDER" >/dev/null 2>&1
  docker image rm "$IMAGE" >/dev/null 2>&1
  docker volume rm "$BUILDER-cache" >/dev/null 2>&1
  rm -rf "$SCRATCH"
  exit "$status"
}
trap cleanup EXIT

docker volume create --label campaign=dekopon --name "$BUILDER-cache" >/dev/null
docker run -d --platform "$PLATFORM" --privileged --label campaign=dekopon --name "$BUILDER" \
  -p 127.0.0.1:12359:1234 -v "$BUILDER-cache:/var/lib/buildkit" "$BUILDKIT" --addr tcp://0.0.0.0:1234 >/dev/null
docker buildx create --driver remote --name "$BUILDER" tcp://127.0.0.1:12359 >/dev/null
ready=0
for attempt in $(seq 1 30); do
  if docker buildx inspect --bootstrap "$BUILDER" >/dev/null 2>&1; then ready=1; break; fi
  sleep 2
done
[ "$ready" -eq 1 ] || { echo 'Dedicated builder did not become ready' >&2; exit 1; }

build() {
  docker buildx build --builder "$BUILDER" --platform "$PLATFORM" --label campaign=dekopon \
    -f Dockerfile.lg-candidate --build-context "web-asset=$WEB_ASSET_DIR" \
    --build-arg "WEB_SHA256=$1" --build-arg "WEB_SOURCE_COMMIT=$WEB_SOURCE_COMMIT" \
    --build-arg "WEB_NODE_VERSION=$WEB_NODE_VERSION" --build-arg "WEB_LOCK_SHA256=$WEB_LOCK_SHA256" \
    --load -t "$IMAGE" .
}
# A valid-length but wrong digest must fail during checksum verification, not elsewhere.
if build "$(printf '%064d' 0)" > "$LG_CANDIDATE_RESULTS/checksum-negative.log" 2>&1; then
  echo 'ERROR: incorrect web checksum was accepted' >&2; exit 1
fi
grep -q 'FAILED' "$LG_CANDIDATE_RESULTS/checksum-negative.log"
build "$WEB_SHA256"
docker image inspect "$IMAGE" --format '{{json .Config.Labels}}' > "$SCRATCH/image-labels.json"
export CANDIDATE_IMAGE="$IMAGE" SMOKE_DIR="$SCRATCH"
python3 - <<'PY'
import json, os, pathlib
labels = json.loads((pathlib.Path(os.environ['SMOKE_DIR']) / 'image-labels.json').read_text())
for key, value in [('web-sha256','WEB_SHA256'), ('web-source-commit','WEB_SOURCE_COMMIT'), ('web-node-version','WEB_NODE_VERSION'), ('web-lock-sha256','WEB_LOCK_SHA256')]:
    assert labels['io.xrl.jellyfin.' + key] == os.environ[value]
assert labels['io.xrl.jellyfin.upstream-tag'] == '12.3'
PY

docker run --rm --label campaign=dekopon --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg "$IMAGE" -version > "$SCRATCH/runtime.txt"
printf '\nnative platform=%s\n' "$PLATFORM" >> "$SCRATCH/runtime.txt"
ffmpeg() {
  docker run --rm --label campaign=dekopon --name "$FIXTURE" -v "$SCRATCH/media:/media" \
    --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg "$IMAGE" -hide_banner -loglevel error -y "$@"
}
ffmpeg -f lavfi -i testsrc2=size=320x180:rate=24 -f lavfi -i anullsrc=r=48000:cl=5.1 \
  -t 8 -c:v libx264 -preset ultrafast -g 48 -pix_fmt yuv420p -c:a eac3 -b:a 448k /media/h264.mkv
ffmpeg -i /media/h264.mkv -c:v libx265 -preset ultrafast -x265-params pools=1:frame-threads=1:log-level=error \
  -pix_fmt yuv420p -c:a copy /media/hevc.mkv
ffmpeg -i /media/h264.mkv -c:v copy -c:a aac -ac 2 /media/aac.mkv

docker run -d --label campaign=dekopon --name "$SERVER" --platform "$PLATFORM" \
  -p 127.0.0.1:18097:8096 -v "$SCRATCH/config:/config" -v "$SCRATCH/cache:/cache" \
  -v "$SCRATCH/media:/media:ro" "$IMAGE" >/dev/null
ready=0
for attempt in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:18097/Startup/Configuration >/dev/null 2>&1; then ready=1; break; fi
  [ "$(docker inspect "$SERVER" --format '{{.State.Running}}')" = true ] || break
  sleep 2
done
[ "$ready" -eq 1 ] || { echo 'Scratch server did not become ready' >&2; exit 1; }
python3 tests/lg-candidate-smoke.py
# Actual commands, not only successful negotiations, must copy video and convert audio.
docker logs "$SERVER" > "$SCRATCH/server.log" 2>&1
grep -E -- '-codec:v:0 copy.*-codec:a:0 libfdk_aac -ac 6' "$SCRATCH/server.log" > "$SCRATCH/copy-commands.txt"
for fixture in h264 hevc; do
  grep -F "/media/$fixture.mkv" "$SCRATCH/copy-commands.txt" > "$SCRATCH/fixture-command.txt"
  grep -q -- '-f hls' "$SCRATCH/fixture-command.txt"
done
echo 'Candidate image/checksum/native synthetic gates passed. LG C2 and migration gates remain untested.'
