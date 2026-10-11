# syntax=docker/dockerfile:1.7

# Official 12.1 multi-platform index, including ARM64 child
# sha256:690b2dcb8f18f144d1091d728208a36e90cbf84a8811c9275b1e3bd96d52944f.
ARG UPSTREAM_BASE=docker.io/jellyfin/jellyfin:12.1@sha256:78d3ea1207d1322471fcac39a614f004f2ccf7e878f95ab2977d752f07e4dd7e
ARG UPSTREAM_TAG=12.1
ARG WEB_TAG=v12.1-xrl.1
ARG WEB_SHA256

FROM ${UPSTREAM_BASE}

ARG UPSTREAM_BASE
ARG UPSTREAM_TAG
ARG WEB_TAG
ARG WEB_SHA256

LABEL org.opencontainers.image.source="https://github.com/xrl/jellyfin-rpi" \
      org.opencontainers.image.description="Official Jellyfin server with the XRL webOS playback bundle" \
      org.opencontainers.image.base.name="${UPSTREAM_BASE}" \
      io.xrl.jellyfin.base-arm64-manifest="sha256:690b2dcb8f18f144d1091d728208a36e90cbf84a8811c9275b1e3bd96d52944f" \
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
