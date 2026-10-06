# jellyfin-rpi

A multi-architecture Jellyfin image that replaces the web bundle in the official `jellyfin/jellyfin` server image with the tested LG webOS playback bundle from [`xrl/jellyfin-web`](https://github.com/xrl/jellyfin-web). The 12.1 candidate also replaces only `Jellyfin.Api.dll` with the XRL iOS video AAC policy patch. The official self-contained runtime, remaining server assemblies, FFmpeg, OS and entrypoint are retained.

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
3. Verify the matching official server index and ARM64 child digests and pin the base. Supply the verified matching web release asset checksum as a build argument; the 12.1 Dockerfile deliberately has no checksum default.
4. Only after exact-head build/asset checks and separate publication approval, tag this repository with the same version. Tag builds derive the server and web versions from the tag and publish:
   - `ghcr.io/xrl/jellyfin-rpi:<version>`
   - `ghcr.io/xrl/jellyfin-rpi:latest`
5. Independently rehearse backup/restore, migration and browser acceptance before any explicitly approved single-writer deployment in `xrl/rpi-homelab`. Native LG C2 acceptance is deferred, not a cutover blocker; source checks do not imply TV validation.

Manual workflow runs publish a uniquely named image and deliberately do not move `latest`.

## Local build

The candidate defaults pin the server source commit, .NET 10 SDK index and compiled API checksum in `Dockerfile`. The build fetches that exact commit (no branch fallback), compiles ordinary AnyCPU IL on `BUILDPLATFORM`, and verifies the replacement checksum. The same IL assembly is used for both final architectures. To change the server patch, rebuild from the new immutable commit with the pinned SDK, validate assembly references and endpoint/media execution, then update both source and checksum pins; do not replace additional dependencies piecemeal.

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

The Dockerfile pins the official upstream **12.1** multi-platform base digest and checks the supplied web asset checksum. This branch has not published or deployed an image. The overlay changes only the API assembly plus the existing patched-web installation and metadata. Source, SDK, base, web and compiled DLL identities are recorded in image labels. Builds fail on an unexpected compiled DLL checksum rather than silently accepting restore/compiler drift.
