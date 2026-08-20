# syntax=docker/dockerfile:1.7

ARG UPSTREAM_TAG=10.11.11
ARG WEB_TAG=v10.11.11-xrl.1
ARG WEB_SHA256=11f403101a2d4018edd4146d0760c8d2301a16fa7523d7c25aaa770bd91bf103

FROM jellyfin/jellyfin:${UPSTREAM_TAG}

ARG UPSTREAM_TAG
ARG WEB_TAG
ARG WEB_SHA256

LABEL org.opencontainers.image.source="https://github.com/xrl/jellyfin-rpi" \
      org.opencontainers.image.description="Official Jellyfin server with the XRL webOS playback bundle" \
      org.opencontainers.image.base.name="docker.io/jellyfin/jellyfin:${UPSTREAM_TAG}" \
      io.xrl.jellyfin.upstream-tag="${UPSTREAM_TAG}" \
      io.xrl.jellyfin.web-tag="${WEB_TAG}" \
      io.xrl.jellyfin.web-sha256="${WEB_SHA256}"

USER root

RUN set -eux; \
    rm -rf /jellyfin/jellyfin-web/* /jellyfin/jellyfin-web/.[!.]*; \
    curl --retry 5 --retry-all-errors -fsSL \
      "https://github.com/xrl/jellyfin-web/releases/download/${WEB_TAG}/jellyfin-web-dist.tar.gz" \
      -o /tmp/jellyfin-web-dist.tar.gz; \
    echo "${WEB_SHA256}  /tmp/jellyfin-web-dist.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/jellyfin-web-dist.tar.gz -C /jellyfin/jellyfin-web; \
    rm /tmp/jellyfin-web-dist.tar.gz; \
    echo "${UPSTREAM_TAG}" > /jellyfin/jellyfin-web/.xrl-server-tag; \
    echo "${WEB_TAG}" > /jellyfin/jellyfin-web/.xrl-web-tag
