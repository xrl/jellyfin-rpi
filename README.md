# jellyfin-rpi

A multi-architecture Jellyfin image that replaces the web bundle in the official `jellyfin/jellyfin` server image with the tested LG webOS playback bundle from [`xrl/jellyfin-web`](https://github.com/xrl/jellyfin-web). This is an image remix, not a fork of the Jellyfin server or FFmpeg.

## Current release

`ghcr.io/xrl/jellyfin-rpi:10.11.11-xrl.2` combines:

- `jellyfin/jellyfin:10.11.11`
- `xrl/jellyfin-web:v10.11.11-xrl.2`

The web release asset is SHA-256 verified during the image build. Images are published for `linux/amd64` and `linux/arm64` with provenance and SBOM attestations.

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
3. Update this repository's Dockerfile defaults to the matching official server tag, web tag, and web asset checksum.
4. Tag this repository with the same version. Tag builds derive the server and web versions from the tag and publish:
   - `ghcr.io/xrl/jellyfin-rpi:<version>`
   - `ghcr.io/xrl/jellyfin-rpi:latest`
5. Update the explicit image tag in `xrl/rpi-homelab` and deploy through Argo CD only after LG C2 validation.

Manual workflow runs publish a uniquely named image and deliberately do not move `latest`.

## Local build

```sh
docker buildx build \
  --platform linux/arm64 \
  --load \
  -t jellyfin-rpi:10.11.11-xrl.2 .
```

The Dockerfile defaults are sufficient for the current release. Override `UPSTREAM_TAG`, `WEB_TAG`, and `WEB_SHA256` together when testing another combination.
