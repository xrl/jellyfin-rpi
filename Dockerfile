# syntax=docker/dockerfile:1.7

ARG UPSTREAM_TAG=10.11.5
ARG WEB_TAG=v10.11.5-xrl.1

FROM jellyfin/jellyfin:${UPSTREAM_TAG}

ARG WEB_TAG

USER root

RUN set -eux; \
    rm -rf /jellyfin/jellyfin-web/* /jellyfin/jellyfin-web/.[!.]*; \
    curl -fsSL "https://github.com/xrl/jellyfin-web/releases/download/${WEB_TAG}/jellyfin-web-dist.tar.gz" \
      -o /tmp/jellyfin-web-dist.tar.gz; \
    tar -xzf /tmp/jellyfin-web-dist.tar.gz -C /jellyfin/jellyfin-web; \
    rm /tmp/jellyfin-web-dist.tar.gz; \
    echo "${WEB_TAG}" > /jellyfin/jellyfin-web/.xrl-web-tag; \
    grep -q 'enableMkvProgressive:!0' /jellyfin/jellyfin-web/main.jellyfin.bundle.js \
      || (echo "patch verification failed: enableMkvProgressive marker missing" >&2; exit 1); \
    grep -qE 'tizenVersion>=3\|\|[a-z]\.A\.vidaa\|\|[a-z]\.A\.web0s' /jellyfin/jellyfin-web/main.jellyfin.bundle.js \
      || (echo "patch verification failed: web0s HDR10+ marker missing" >&2; exit 1)
