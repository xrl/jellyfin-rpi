# syntax=docker/dockerfile:1.7

# Verified official 12.1 index (amd64 + arm64); do not resolve a mutable tag.
ARG UPSTREAM_BASE=docker.io/jellyfin/jellyfin:12.1@sha256:78d3ea1207d1322471fcac39a614f004f2ccf7e878f95ab2977d752f07e4dd7e
ARG UPSTREAM_TAG=12.1
ARG WEB_TAG=v12.1-xrl.1
ARG WEB_SHA256=d07c1121f42beb81efa96e46a00fe309ac9cbc9ea4f415fe9f399f23a6af500e
ARG SERVER_TAG=v12.1-rpi.2
ARG SERVER_SOURCE_COMMIT=19432f27fa3af78c4045550c2cc21ef169f15420
ARG SERVER_SHA256=ec256cfaf1a72819c71566963862319bb261da5a1c555b87e22d82abb1d0b1e4
ARG SERVER_PROVENANCE_SHA256=d64d873396ac90fd9320341d8ac7ff06fb9ba5808fbcf7a84d572f7e2a4dbc70

FROM ${UPSTREAM_BASE}

ARG UPSTREAM_BASE
ARG UPSTREAM_TAG
ARG WEB_TAG
ARG WEB_SHA256
ARG SERVER_TAG
ARG SERVER_SOURCE_COMMIT
ARG SERVER_SHA256
ARG SERVER_PROVENANCE_SHA256

LABEL org.opencontainers.image.source="https://github.com/xrl/jellyfin-rpi" \
      org.opencontainers.image.description="Official Jellyfin runtime with the XRL iOS AAC API patch and webOS playback bundle" \
      org.opencontainers.image.base.name="${UPSTREAM_BASE}" \
      io.xrl.jellyfin.base-arm64-manifest="sha256:690b2dcb8f18f144d1091d728208a36e90cbf84a8811c9275b1e3bd96d52944f" \
      io.xrl.jellyfin.upstream-tag="${UPSTREAM_TAG}" \
      io.xrl.jellyfin.web-tag="${WEB_TAG}" \
      io.xrl.jellyfin.web-sha256="${WEB_SHA256}" \
      io.xrl.jellyfin.server-source="https://github.com/xrl/jellyfin" \
      io.xrl.jellyfin.server-source-commit="${SERVER_SOURCE_COMMIT}" \
      io.xrl.jellyfin.server-tag="${SERVER_TAG}" \
      io.xrl.jellyfin.server-sdk="mcr.microsoft.com/dotnet/sdk:10.0.401@sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317" \
      io.xrl.jellyfin.server-api-sha256="${SERVER_SHA256}" \
      io.xrl.jellyfin.server-provenance-sha256="${SERVER_PROVENANCE_SHA256}"

USER root

RUN set -eux; \
    test "${UPSTREAM_BASE}" = 'docker.io/jellyfin/jellyfin:12.1@sha256:78d3ea1207d1322471fcac39a614f004f2ccf7e878f95ab2977d752f07e4dd7e'; \
    test "${SERVER_TAG}" = 'v12.1-rpi.2'; \
    test "${SERVER_SOURCE_COMMIT}" = '19432f27fa3af78c4045550c2cc21ef169f15420'; \
    test "${WEB_TAG}" = 'v12.1-xrl.1'; \
    test "${WEB_SHA256}" = 'd07c1121f42beb81efa96e46a00fe309ac9cbc9ea4f415fe9f399f23a6af500e'; \
    test "${SERVER_SHA256}" = 'ec256cfaf1a72819c71566963862319bb261da5a1c555b87e22d82abb1d0b1e4'; \
    test "${SERVER_PROVENANCE_SHA256}" = 'd64d873396ac90fd9320341d8ac7ff06fb9ba5808fbcf7a84d572f7e2a4dbc70'; \
    curl --retry 5 --retry-all-errors -fsSL \
      "https://github.com/xrl/jellyfin/releases/download/${SERVER_TAG}/Jellyfin.Api.dll" \
      -o /tmp/Jellyfin.Api.dll; \
    echo "${SERVER_SHA256}  /tmp/Jellyfin.Api.dll" | sha256sum -c -; \
    curl --retry 5 --retry-all-errors -fsSL \
      "https://github.com/xrl/jellyfin/releases/download/${SERVER_TAG}/Jellyfin.Api.provenance.json" \
      -o /tmp/Jellyfin.Api.provenance.json; \
    echo "${SERVER_PROVENANCE_SHA256}  /tmp/Jellyfin.Api.provenance.json" | sha256sum -c -; \
    grep -Fx '  "sourceRepository": "https://github.com/xrl/jellyfin",' /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx "  \"sourceTag\": \"${SERVER_TAG}\"," /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx "  \"sourceSha\": \"${SERVER_SOURCE_COMMIT}\"," /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx '  "baseIndexDigest": "sha256:78d3ea1207d1322471fcac39a614f004f2ccf7e878f95ab2977d752f07e4dd7e",' /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx "  \"sha256\": \"${SERVER_SHA256}\"," /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx '  "sdkVersion": "10.0.401",' /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx '  "sdkImage": "mcr.microsoft.com/dotnet/sdk:10.0.401@sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317",' /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx '  "architecture": "AnyCPU",' /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx '    "name": "Jellyfin.Api",' /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx '    "version": "1.0.0.0",' /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx '    "flags": "ILOnly",' /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx '    "machine": "I386",' /tmp/Jellyfin.Api.provenance.json; \
    grep -Fx '    "managedNativeHeaderSize": 0,' /tmp/Jellyfin.Api.provenance.json; \
    mv /tmp/Jellyfin.Api.dll /jellyfin/Jellyfin.Api.dll; \
    mv /tmp/Jellyfin.Api.provenance.json /jellyfin/.xrl-api-provenance.json

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
