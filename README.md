# jellyfin-rpi

A multi-architecture Jellyfin image that replaces the web bundle in the official `jellyfin/jellyfin` server image with the tested LG webOS playback bundle from [`xrl/jellyfin-web`](https://github.com/xrl/jellyfin-web). The 12.1 candidate also replaces only `Jellyfin.Api.dll` with the XRL iOS video AAC policy patch. The official self-contained runtime, remaining server assemblies, FFmpeg, OS and entrypoint are retained.

## LG 12.3 candidate (local-only)

`Dockerfile.lg-candidate` is an additive **12.3-xrl.1 candidate** recipe. It uses
stock official 12.3 server assemblies and a matching, patched 12.3 web artifact.
It does **not** install the 12.1-only iOS API DLL overlay in `Dockerfile`; that
existing recipe and its native-amd64 gates are unchanged. Production's earlier
12.1 image did not contain that overlay either. Adopting the iOS policy on 12.3
requires a separately rebuilt and reviewed server artifact.

The candidate pins the official 12.3 multi-platform index to
`sha256:2038fe038ab3876a80f6e7b7e0aef6607b032c7dc0c9b3ad3296d0b2eba3bbb5`
(ARM64 child `sha256:2fe4523231dee34a7144d6fcd0313a60730c25695fa4e9f6ae09f98d4dbe9370`,
amd64 child `sha256:720ad28968e040f1ea049749f4ce546b28c7251244a6eb8aacf9147d8afbc24d`).
It includes upstream fixes #18186 (remux segment cleanup) and #18300 (Profile 8
HEVC `hvc1` tag). The latter deliberately does not change Profile 7, so it is
**not a demonstrated Paddington fix**. Existing LG DTS, HDR fallback, fMP4 and
bounded recovery changes live in the web source repository.

Build and check the web bundle in `xrl/jellyfin-web` first, using that repository's
Node version, lockfile, tests, typecheck, production build, ES5 check and
`scripts/assert-lg-bundle.cjs`. Archive the **contents** of `dist/` at the tar root
as `jellyfin-web-dist.tar.gz` in an artifact directory outside either checkout.
Record the source commit, Node version, lockfile SHA-256 and archive SHA-256.
This repository never clones or compiles the web or server sources. Both a local
archive and a later downloaded release archive use the same named-context and
checksum-verification path; no second installation recipe is needed.

From this repository, with those independently recorded inputs:

```sh
export WEB_ASSET_DIR=/absolute/path/to/web-artifact-directory
export WEB_SHA256=<reviewed-archive-sha256>
export WEB_SOURCE_COMMIT=<reviewed-40-character-web-commit>
export WEB_NODE_VERSION=<producer-node-version>
export WEB_LOCK_SHA256=<producer-lockfile-sha256>
export LG_CANDIDATE_RESULTS=/absolute/path/to/scratch-results
bash tests/lg-candidate.sh
```

The local gate uses a dedicated labelled BuildKit container/cache and the Docker
host's native architecture. It rejects an incorrect archive checksum, builds
this exact recipe, checks provenance labels, starts a fresh loopback-only server
and exercises synthetic H.264/HEVC video-copy plus six-channel AAC conversion
through real fMP4 HLS fragments, with compatible AAC as a direct-play control.
It retains sanitized results/runtime identity and removes its containers,
candidate image, private builder cache and scratch configuration on exit. It
never mounts production config/media, publishes an image or modifies Kubernetes.
Run only one gate at a time: its loopback ports are 12359 and 18097.

This candidate is not wired into existing publication CI while its web asset is
unpublished. Source PRs/builds do not publish release tags, release assets,
registry images or `latest`. A future release is named `12.3-xrl.1`, not
`12.1-xrl.2`, and needs separate publication approval.

**Production cutover remains blocked on real LG C2 acceptance:** Paddington cold
start, resume/seek and sustained playback, a DV Profile 8 title and H.264/DTS
playback. Synthetic fragments and desktop playback cannot satisfy that gate.
Database migration plus backup/restore must also be rehearsed on isolated state
before using the candidate with a copy of the current library. No old server may
open a database migrated by the candidate. No deployment is authorized here.

## Current release

`ghcr.io/xrl/jellyfin-rpi:10.11.11-xrl.2` combines:

- `jellyfin/jellyfin:10.11.11`
- `xrl/jellyfin-web:v10.11.11-xrl.2`

The web release asset is SHA-256 verified during the image build. Images are published for `linux/amd64` and `linux/arm64` with provenance and SBOM attestations. The 12.1 overlay recipe on this branch is **candidate source only**, not a published image. It uses the existing checksummed `v12.1-xrl.1` web release.

## Web playback patches

The source and rationale are documented in [`xrl/jellyfin-web/XRL_PATCHES.md`](https://github.com/xrl/jellyfin-web/blob/release-10.11.z-xrl/XRL_PATCHES.md). The current bundle carries:

- conservative DTS detection to prevent silent audio on LG models that cannot decode DTS;
- broader webOS Dolby Vision/HDR fallback ranges for the LG C2;
- fragmented-MP4/CMAF HLS by default on webOS to preserve Dolby Vision and HDR10+ signaling; and
- bounded native-HLS stall recovery for LG clients that stop requesting segments without a media error.

The earlier MKV-progressive experiment is not included because it had no runtime effect.

## Release process

1. Port and test the patches on the matching upstream `jellyfin-web` release.
2. Tag that fork, for example `v10.11.11-xrl.2`. Its release workflow publishes `jellyfin-web-dist.tar.gz` and a SHA-256 file.
3. Verify the pinned official 12.1 index and both platform manifests, the public server release DLL and provenance, and the existing `v12.1-xrl.1` web release/checksum.
4. Only after exact-head build/asset checks, a passing PR native-amd64 media gate, other required native architecture gates, and separate publication approval, dispatch the manual workflow from this reviewed branch. It publishes only `ghcr.io/xrl/jellyfin-rpi:12.1-manual-<run-id>-<run-attempt>` (distinct even on reruns). No image is published merely by pushing a tag: tag-triggered publication and `latest` are deliberately disabled for this candidate to prevent collisions with the existing 10.11 release path. Do not reuse a manual run's image tag.
5. Independently rehearse backup/restore, migration and browser acceptance before any explicitly approved single-writer deployment in `xrl/rpi-homelab`. Native LG C2 acceptance is deferred, not a cutover blocker; source checks do not imply TV validation.

## Local build

The server repository owns compilation and public GitHub Release assets. This consumer never clones or compiles foreign source. It downloads `Jellyfin.Api.dll` (SHA-256 `ec256cfaf1a72819c71566963862319bb261da5a1c555b87e22d82abb1d0b1e4`) and `Jellyfin.Api.provenance.json` (SHA-256 `d64d873396ac90fd9320341d8ac7ff06fb9ba5808fbcf7a84d572f7e2a4dbc70`) anonymously from `xrl/jellyfin` release `v12.1-rpi.2`, bound to source `19432f27fa3af78c4045550c2cc21ef169f15420`. The same audited ordinary AnyCPU IL assembly serves both image architectures.

The Dockerfile defaults and assertions pin both public assets and the existing web release SHA-256. Manual workflow checksum inputs default to those reviewed values; supplying other values fails before publication (and image build checks the downloaded bytes). The Dockerfile checks both hashes and the producer's canonical, indented provenance fields (source/tag/base/SDK/AnyCPU identity); it does not trust a mutable downloaded checksum as the sole pin. It retains the verified manifest as server metadata. The existing SDK compile stage has been removed. No image publication or deployment is implied by these pins.

The official pinned index and both platform children are verified directly, independently of mutable upstream tag movement. Native architecture media validation and real-device playback acceptance remain required before publication/deployment.

For the existing matching web release:

```sh
WEB_TAG=v12.1-xrl.1
WEB_SHA256=d07c1121f42beb81efa96e46a00fe309ac9cbc9ea4f415fe9f399f23a6af500e
docker buildx build \
  --platform linux/arm64 \
  --build-arg "WEB_TAG=$WEB_TAG" \
  --build-arg "WEB_SHA256=$WEB_SHA256" \
  --load \
  -t jellyfin-rpi:12.1-candidate .
```

The Dockerfile pins the official upstream **12.1** multi-platform base digest and checks the supplied web asset checksum. This branch has not published or deployed an image. The overlay changes only the API assembly plus the existing patched-web installation and metadata. Source, SDK, base, web and compiled DLL identities are recorded in image labels. Builds fail on unexpected release-asset checksums and incompatible provenance. No SDK or source build cache is involved in the consumer path.

## Image integration gate

`.github/workflows/native-amd64.yml` builds this exact Dockerfile on a native x86_64 GitHub-hosted runner, uses the inherited FFmpeg to create synthetic EAC3/AAC/mixed-track fixtures, and exercises 18 image-composition endpoint controls including progressive/HLS AAC stereo, video-copy logs, exact forbidden response, and non-iOS controls. It runs on pull requests and is also a prerequisite within the manual image publication workflow; no check by itself authorizes publication. It uses loopback-only access and isolated temporary config/cache/media. Only sanitized pass/fail results, FFprobe streams and the forbidden error body are uploaded; access-token-bearing negotiations and server logs stay local and are deleted. The dedicated labelled BuildKit container, volume, candidate image and scratch server are removed after each job; no shared Docker cache is pruned. ARM64 native media evidence and native device acceptance remain separate.
