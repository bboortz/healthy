# HC-005: publish hc as a scratch container image.
#
# Pre-build the binary first (via scripts/build.sh), then:
#   docker build --build-arg HC_BIN=bin/hc-x86_64-linux  -t hc:amd64 .
#   docker build --build-arg HC_BIN=bin/hc-aarch64-linux -t hc:arm64 .
#
# No builder stage: scripts/build.sh already produces static ELF binaries
# for each cross-target (see memory/project.md). docker's job here is
# purely to package the existing binary into an OCI image.

# hadolint ignore=DL3006
FROM scratch

ARG HC_BIN=bin/hc-x86_64-linux

LABEL org.opencontainers.image.source="https://github.com/bboortz/healthy"
LABEL org.opencontainers.image.description="Tiny static TCP / TLS 1.3 / HTTP(S) health check probe. Scratch-safe. No libc, no heap."
LABEL org.opencontainers.image.licenses="MIT"

COPY ${HC_BIN} /hc

ENTRYPOINT ["/hc"]
