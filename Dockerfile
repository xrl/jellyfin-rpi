# syntax=docker/dockerfile:1.7

# Official 12.1 multi-platform index, including ARM64 child
# sha256:690b2dcb8f18f144d1091d728208a36e90cbf84a8811c9275b1e3bd96d52944f.
ARG UPSTREAM_BASE=docker.io/jellyfin/jellyfin:12.1@sha256:78d3ea1207d1322471fcac39a614f004f2ccf7e878f95ab2977d752f07e4dd7e
ARG UPSTREAM_TAG=12.1
ARG WEB_TAG=v12.1-xrl.1
ARG WEB_SHA256
ARG SERVER_SOURCE_COMMIT=7f58555af527f63d580ca3f6c66ae4cfb81bebf9
ARG SERVER_SDK=mcr.microsoft.com/dotnet/sdk:10.0.401@sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317
ARG SERVER_API_SHA256=00ddae34fb5830aeb455277c192e671adbdf53dcf809c87e80290f1b6c7f80d5

# BUILDPLATFORM builds ordinary AnyCPU IL once for both final architectures.
FROM --platform=$BUILDPLATFORM ${SERVER_SDK} AS server-api
ARG SERVER_SOURCE_COMMIT
WORKDIR /src
RUN set -eux; \
    test "${#SERVER_SOURCE_COMMIT}" = 40; \
    git init; \
    git remote add origin https://github.com/xrl/jellyfin.git; \
    git fetch --depth=1 origin "${SERVER_SOURCE_COMMIT}"; \
    git checkout --detach FETCH_HEAD; \
    test "$(git rev-parse HEAD)" = "${SERVER_SOURCE_COMMIT}"; \
    dotnet build Jellyfin.Api --configuration Release -p:PublishReadyToRun=false --verbosity minimal

FROM ${UPSTREAM_BASE}

ARG UPSTREAM_BASE
ARG UPSTREAM_TAG
ARG WEB_TAG
ARG WEB_SHA256
ARG SERVER_SOURCE_COMMIT
ARG SERVER_SDK
ARG SERVER_API_SHA256

COPY --from=server-api /src/Jellyfin.Api/bin/Release/net10.0/Jellyfin.Api.dll /jellyfin/Jellyfin.Api.dll
RUN echo "${SERVER_API_SHA256}  /jellyfin/Jellyfin.Api.dll" | sha256sum -c -

LABEL org.opencontainers.image.source="https://github.com/xrl/jellyfin-rpi" \
      org.opencontainers.image.description="Official Jellyfin runtime with the XRL iOS AAC API patch and webOS playback bundle" \
      org.opencontainers.image.base.name="${UPSTREAM_BASE}" \
      io.xrl.jellyfin.base-arm64-manifest="sha256:690b2dcb8f18f144d1091d728208a36e90cbf84a8811c9275b1e3bd96d52944f" \
      io.xrl.jellyfin.upstream-tag="${UPSTREAM_TAG}" \
      io.xrl.jellyfin.web-tag="${WEB_TAG}" \
      io.xrl.jellyfin.web-sha256="${WEB_SHA256}" \
      io.xrl.jellyfin.server-source="https://github.com/xrl/jellyfin" \
      io.xrl.jellyfin.server-source-commit="${SERVER_SOURCE_COMMIT}" \
      io.xrl.jellyfin.server-sdk="${SERVER_SDK}" \
      io.xrl.jellyfin.server-api-sha256="${SERVER_API_SHA256}"

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
