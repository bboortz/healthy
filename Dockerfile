# syntax=docker/dockerfile:1.7
#
# HC-007: multi-stage build-from-source. Stage 1 compiles hc.zig inside
# forge's shared Zig builder (FG-072 — ghcr.io/bboortz/forge-builder-zig-trixie
# provides Zig 0.17.1 + CA bundle + syft + git/curl/jq, apt-upgraded, no
# apt-list cache). Stage 2 is scratch + /hc.
#
# Pre-HC-007 this file carried `ARG HC_BIN` and packaged a pre-built binary
# produced by `scripts/build.sh` on the host / CI runner. HC-007 collapses
# the build step into the Dockerfile itself; see docs/stories/HC-007-build-
# from-source.md.

ARG FORGE_BUILDER_ZIG_REF=ghcr.io/bboortz/forge-builder-zig-trixie:latest

# ── Stage 1: builder (forge-maintained, Zig toolchain pre-baked) ─────────────
# Pre-provides per images/forge-builder-zig-trixie/PROMISES.yaml (FG-072):
#   - /usr/local/bin/zig   (Zig 0.17.1; forge pins via zig-slim-trixie base)
#   - /usr/local/bin/syft  (reserved for HC-008 SBOM follow-up)
#   - /etc/ssl/certs/ca-certificates.crt
#   - apt-upgraded trixie userland (no apt-list cache)
#   - git, curl, jq
#
# Builder is pinned to --platform=linux/amd64 so cross-arch image builds don't
# trigger QEMU-emulated apt + zig startup (which would be minutes per arch).
# Zig cross-compiles cleanly from amd64 to any target.
# hadolint ignore=DL3029
FROM --platform=linux/amd64 ${FORGE_BUILDER_ZIG_REF} AS builder

ARG ZIG_TARGET=x86_64-linux
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

WORKDIR /src

# Directory-preserving COPY so scripts/build.sh's internal
# `repo=$(cd "$here/.." && pwd)` resolves to /src and finds /src/hc.zig via
# `-Mroot="$repo/hc.zig"`. Flattening both files into /src/ would break the
# module-path resolution noted in memory/zig-pitfalls.md.
COPY hc.zig            /src/hc.zig
COPY scripts/build.sh  /src/scripts/build.sh

# Explicit `TARGET=${ZIG_TARGET}` because ARG values are substituted into
# RUN commands, but the forked /bin/sh that runs build.sh doesn't inherit
# the ARG as an env var. Without the explicit prefix, build.sh sees an
# empty $TARGET and silently defaults to its own fallback (x86_64-linux),
# producing the wrong arch on arm64 builds.
RUN TARGET=${ZIG_TARGET} sh /src/scripts/build.sh && \
    mv "bin/hc-${ZIG_TARGET}" /hc && \
    ls -lh /hc

# ── Stage 2: runtime ─────────────────────────────────────────────────────────
FROM scratch

# Re-declare the build-args here so the runtime stage sees them. ARG scoping
# in Docker is per-stage: declarations in the builder stage above don't carry
# across. Without this re-declaration, `LABEL ...revision="${GIT_SHA}"` would
# expand to the empty string (observed post-HC-007 ship, 2026-11-20).
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/healthy"
LABEL org.opencontainers.image.description="Tiny static TCP / TLS 1.3 / HTTP(S) health check probe. Scratch-safe. No libc, no heap."
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=builder /hc /hc
ENTRYPOINT ["/hc"]
