# jellyfin-rpi

Custom Jellyfin server image that bakes a patched `jellyfin-web` bundle into the official `jellyfin/jellyfin` server. This is an image remix — not a fork of the Jellyfin server itself.

## What's patched

- **MKV progressive playback** enabled by default (`enableMkvProgressive`)
- **LG WebOS HDR10+ / Dolby Vision** support extended to WebOS C2 and newer (`tizenVersion>=3 || web0s` path)

Patches live in [xrl/jellyfin-web](https://github.com/xrl/jellyfin-web) and are released as `jellyfin-web-dist.tar.gz` tarballs.

## Image reference

```
ghcr.io/xrl/jellyfin-rpi:<tag>
ghcr.io/xrl/jellyfin-rpi:latest
```

Example:
```sh
docker pull ghcr.io/xrl/jellyfin-rpi:10.11.5-xrl.1
```

## How to bump

1. Build and tag a new release in [xrl/jellyfin-web](https://github.com/xrl/jellyfin-web) — e.g. `v10.11.5-xrl.2`.
2. Push a matching tag here:
   ```sh
   git tag v10.11.5-xrl.2
   git push origin v10.11.5-xrl.2
   ```
   The tag triggers the `build-and-push` workflow. The leading `v` is stripped so the image tag becomes `10.11.5-xrl.2`.

For a new upstream Jellyfin version, update the `ARG UPSTREAM_TAG` default in the `Dockerfile` and the workflow `default` values, then tag accordingly.

## Upstream sources

- Jellyfin server: [jellyfin/jellyfin](https://github.com/jellyfin/jellyfin) — `jellyfin/jellyfin:<tag>` on Docker Hub
- Patched web UI: [xrl/jellyfin-web](https://github.com/xrl/jellyfin-web) — releases at `github.com/xrl/jellyfin-web/releases`
