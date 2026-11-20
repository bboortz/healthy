#!/bin/sh
# test_HC_007_build-from-source.sh — Dockerfile builds hc.zig from source
# inside the image (forge FG-072 builder) instead of packaging a pre-built
# binary via ARG HC_BIN.
# Story: docs/stories/HC-007-build-from-source.md
# Plan:  docs/plan/HC-007-build-from-source-plan.md
# CAPs:  image.builds-from-source
# Extends: workflow.publish-ghcr-image

set -u
pass=0; fail=0

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1

assert_rc() { want=$1; shift; "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL want=$want got=$rc: $*"; fi; }

assert_grep() { pat=$1; file=$2
  if grep -Eq "$pat" "$file" 2>/dev/null; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL grep '$pat' in $file"; fi; }

assert_absent_in_file() { pat=$1; file=$2
  if grep -Eq "$pat" "$file" 2>/dev/null; then
    fail=$((fail + 1)); echo "FAIL $file should NOT contain '$pat'"
  else pass=$((pass + 1)); fi; }

# release.yml slice-grep (same awk-range technique HC-005 uses).
in_release_section() {
  pat=$1; start=$2; stop=$3
  awk -v s="$start" -v e="$stop" '
    $0 ~ s { inside=1; next }
    inside && $0 ~ e { exit }
    inside { print }
  ' .github/workflows/release.yml | grep -Eq "$pat" 2>/dev/null
}
assert_in_publish() { pat=$1; label=$2
  if in_release_section "$pat" '^  publish-image:' '^  [a-z_]+:'; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL (in publish-image: $label) grep '$pat'"; fi; }
assert_absent_in_publish() { pat=$1; label=$2
  if in_release_section "$pat" '^  publish-image:' '^  [a-z_]+:'; then
    fail=$((fail + 1)); echo "FAIL (publish-image should NOT contain $label) grep '$pat'"
  else pass=$((pass + 1)); fi; }

# ----- Scenario 1 — multi-stage Dockerfile (builder + scratch runtime) -----
# Exactly two FROM instructions.
from_count=$(grep -cE '^FROM' Dockerfile 2>/dev/null)
if [ "$from_count" = "2" ]; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL expected 2 FROM instructions, got $from_count"; fi
# First FROM references the forge Zig builder; second is scratch.
assert_grep '^FROM --platform=linux/amd64 \$\{?FORGE_BUILDER_ZIG_REF' Dockerfile
assert_grep '^FROM scratch\s*$'                                       Dockerfile
# No ARG HC_BIN anywhere (clean break from HC-005's contract).
assert_absent_in_file '^ARG HC_BIN'            Dockerfile
assert_absent_in_file 'build-arg HC_BIN'       Dockerfile
# New build-arg is ZIG_TARGET with a semver-ish default.
assert_grep '^ARG ZIG_TARGET='                 Dockerfile
# COPY from the builder stage lands at /hc.
assert_grep '^COPY --from=builder /hc /hc\s*$' Dockerfile

# ----- Scenario 2 — builder uses forge's Zig; healthy owns no toolchain ----
# Reference to the forge builder image is explicit.
assert_grep 'ghcr.io/bboortz/forge-builder-zig-trixie' Dockerfile
# The healthy Dockerfile must NOT install Zig or any apt package itself —
# the forge base owns the toolchain. Both anti-patterns would reintroduce
# the state HC-007 is trying to delete.
assert_absent_in_file 'pipx install'    Dockerfile
assert_absent_in_file '^RUN apt-get'    Dockerfile
assert_absent_in_file 'ziglang=='       Dockerfile
# The RUN that builds hc passes TARGET=${ZIG_TARGET} so build.sh's env
# picks it up (the bug we caught in pre-flight).
assert_grep '^RUN TARGET=\$\{ZIG_TARGET\}' Dockerfile

# ----- Scenario 3 — docker build from a fresh checkout works end-to-end ---
# Docker-availability-gated (same shape as HC-005's online block).
if command -v docker >/dev/null 2>&1; then
  tag=hc-test-hc007:local
  if docker build --quiet --build-arg ZIG_TARGET=x86_64-linux -t "$tag" . >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "FAIL docker build from source failed"
  fi

  # Runtime behavior: default URL probe exits 0 against a known-good host.
  if docker run --rm "$tag" -k https://benni.tech/ >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "FAIL docker run of build-from-source image failed (expected exit 0 for -k https://benni.tech/)"
  fi

  # Image shape invariant from HC-005 still holds: /hc is the only regular
  # file in the layer (filter Docker's runtime overlay).
  cid=$(docker create "$tag" 2>/dev/null)
  if [ -n "$cid" ]; then
    contents=$(docker export "$cid" 2>/dev/null \
      | tar -t \
      | grep -vE '^\.dockerenv$|^(dev|proc|sys|etc)(/|$)' \
      || true)
    docker rm "$cid" >/dev/null 2>&1
    if [ "$(printf '%s\n' "$contents" | wc -l)" = "1" ] && [ "$contents" = "hc" ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAIL image layer should contain exactly /hc; got:"
      printf '  %s\n' "$contents"
    fi
  else
    fail=$((fail + 1)); echo "FAIL could not docker-create from $tag"
  fi

  docker image rm "$tag" >/dev/null 2>&1 || true
else
  echo "note: docker not available — skipping online build-from-source scenario"
fi

# ----- Scenario 4 — image size is in the right order of magnitude ---------
# Keep HC-005's ceiling (<500 KB) — the whole point is "the image stays tiny."
# The floor is intentionally loose (>50 KB catches "truncated / nothing in
# the layer") — the forge builder image's Zig stdlib build may produce
# smaller artefacts than a pipx-installed Zig on the host (observed CI
# 2026-11-20: 185 KB from forge base vs 404 KB from pipx), and that's a
# legitimately working hc. Scenario 3's `docker run ... exit 0` is the
# real functional check.
if command -v docker >/dev/null 2>&1; then
  tag=hc-test-hc007-size:local
  if docker build --quiet --build-arg ZIG_TARGET=x86_64-linux -t "$tag" . >/dev/null 2>&1; then
    sz=$(docker image inspect "$tag" --format '{{.Size}}' 2>/dev/null)
    if [ -n "$sz" ] && [ "$sz" -gt 50000 ] && [ "$sz" -lt 500000 ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1)); echo "FAIL image size $sz bytes (want 50000 < sz < 500000)"
    fi
    docker image rm "$tag" >/dev/null 2>&1 || true
  else
    fail=$((fail + 1)); echo "FAIL docker build for size check failed"
  fi
fi

# ----- Scenario 5 — release.yml publish-image job slimmed -----------------
# Assert the actual step `- name:` lines, not raw substrings — the removed
# names appear in a surviving explanatory comment, so a bare grep would
# false-flag. [-] prevents grep -E from parsing leading hyphens as flags.
assert_absent_in_publish '- name: Install Zig 0\.17\.1 via pipx' "removed pipx install step"
assert_absent_in_publish 'scripts/build\.sh' "removed scripts/build.sh invocation"
assert_absent_in_publish '[-][-]build-arg HC_BIN='   "removed HC_BIN build-arg"
# Present build-args use ZIG_TARGET.
assert_in_publish '[-][-]build-arg ZIG_TARGET=x86_64-linux'  "amd64 ZIG_TARGET"
assert_in_publish '[-][-]build-arg ZIG_TARGET=aarch64-linux' "arm64 ZIG_TARGET"
# OCI label provenance passes through.
assert_in_publish '[-][-]build-arg GIT_SHA='        "GIT_SHA build-arg"
assert_in_publish '[-][-]build-arg BUILD_TIMESTAMP=' "BUILD_TIMESTAMP build-arg"

# ----- Scenario 6 — .dockerignore is tight (allowlist) --------------------
# The allowlist shape: `*` then `!<path>` for each file the Dockerfile
# COPIes. Protects against accidental growth of the build context.
assert_grep '^\*\s*$' .dockerignore
assert_grep '^!hc\.zig\s*$' .dockerignore
assert_grep '^!scripts/build\.sh\s*$' .dockerignore

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
