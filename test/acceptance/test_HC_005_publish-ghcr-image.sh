#!/bin/sh
# test_HC_005_publish-ghcr-image.sh — hc is packaged as a scratch GHCR image.
# Story: docs/stories/HC-005-publish-ghcr-image.md
# Plan:  docs/plan/HC-005-publish-ghcr-image-plan.md
# CAPs:  image.scratch-single-file, workflow.publish-ghcr-image

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

# Grep within a release.yml slice from one anchor to another.
in_release_section() {
  pat=$1; start=$2; stop=$3
  awk -v s="$start" -v e="$stop" '
    $0 ~ s { inside=1; next }
    inside && $0 ~ e { exit }
    inside { print }
  ' .github/workflows/ci-release.yml | grep -Eq "$pat"
}
assert_in_publish() { pat=$1; label=$2
  if in_release_section "$pat" '^  publish-image:' '^  [a-z_]+:'; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL (in publish-image: $label) grep '$pat'"; fi; }

# ----- Scenario 1 — Dockerfile shape ---------------------------------------
# HC-005 guarantees: runtime image is scratch + /hc + ENTRYPOINT + OCI label.
# HC-007 added a builder stage (which legitimately has RUN/WORKDIR/etc.) — the
# runtime-stage assertions below are now scoped to the slice after the final
# `FROM scratch` to preserve HC-005's original "no implicit runtime surface"
# intent.

assert_grep '^FROM scratch\s*$'        Dockerfile
assert_grep '^ENTRYPOINT \["\/hc"\]$'  Dockerfile
# OCI source label for upstream discovery
assert_grep 'org.opencontainers.image.source' Dockerfile

# Runtime stage is the slice from the final `FROM scratch` to end-of-file.
runtime_stage() {
  awk '/^FROM scratch/,0' Dockerfile
}
assert_absent_in_runtime() { pat=$1
  if runtime_stage | grep -qE "$pat"; then
    fail=$((fail + 1)); echo "FAIL runtime stage carries '$pat' — breaks no-implicit-surface invariant"
  else pass=$((pass + 1)); fi; }

assert_absent_in_runtime '^RUN '
assert_absent_in_runtime '^SHELL '
assert_absent_in_runtime '^CMD-SHELL'
assert_absent_in_runtime '^USER '
assert_absent_in_runtime '^WORKDIR '

# ----- Scenario 2 — release.yml publish-image job is wired correctly ------
assert_grep '^  publish-image:' .github/workflows/ci-release.yml
assert_in_publish 'needs: promote'                          "needs"
assert_in_publish 'packages: write'                         "packages: write"
assert_in_publish 'docker/login-action'                     "docker login"
assert_in_publish 'registry: ghcr.io'                       "ghcr registry"
# Both platforms built
assert_in_publish 'linux/amd64'                             "amd64 build"
assert_in_publish 'linux/arm64'                             "arm64 build"
# Manifest list with the four tags
assert_in_publish 'buildx imagetools create'                "manifest create"
assert_in_publish 'IMAGE:latest'                            ":latest tag"
# HC-007: Zig source build now happens inside the Dockerfile's builder stage,
# not via pipx on the runner. The publish-image job no longer needs pipx
# install or scripts/build.sh invocation.
assert_in_publish 'ZIG_TARGET=x86_64-linux'                 "amd64 ZIG_TARGET build-arg"
assert_in_publish 'ZIG_TARGET=aarch64-linux'                "arm64 ZIG_TARGET build-arg"

# ----- Scenario 3 — Local amd64 build produces a single-file scratch image
# (docker-availability-gated — developers without docker get a skip note,
# CI runners always have docker).
# HC-007: the Dockerfile now builds hc.zig inside its builder stage. No
# host-side bin/ pre-step needed — the build-arg is ZIG_TARGET, not HC_BIN.
if command -v docker >/dev/null 2>&1; then
  tag=hc-test-hc005:local
  if docker build --quiet --build-arg ZIG_TARGET=x86_64-linux -t "$tag" . >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "FAIL docker build of Dockerfile failed"
  fi

  # Entrypoint = ["/hc"]
  ep=$(docker image inspect "$tag" --format '{{json .Config.Entrypoint}}' 2>/dev/null)
  if [ "$ep" = '["/hc"]' ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL entrypoint: got '$ep'"; fi

  # Image size: sanity ceiling
  sz=$(docker image inspect "$tag" --format '{{.Size}}' 2>/dev/null)
  if [ -n "$sz" ] && [ "$sz" -gt 0 ] && [ "$sz" -lt 500000 ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL image size $sz bytes (want 0 < sz < 500000)"; fi

  # Image layer contains ONLY /hc (filter out Docker's runtime overlay:
  # .dockerenv + /dev/* + /proc + /sys + /etc/{hostname,hosts,mtab,resolv.conf}
  # which are injected at container-create time, not in the image).
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

  # Run containerized hc with a bogus URL → exit 2 (usage). Proves /hc is the
  # entrypoint AND it's executable in the published scratch image shape.
  rc=0
  docker run --rm "$tag" ftp://x:1 >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "2" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL docker run rc: want 2 (usage) got $rc"; fi

  docker image rm "$tag" >/dev/null 2>&1 || true
else
  echo "note: docker not available — skipping online image-shape assertions"
fi

# ----- Scenario 4 — CAPs registered ----------------------------------------
assert_grep '^### image\.scratch-single-file'      docs/CAPABILITIES.md
assert_grep '^### workflow\.publish-ghcr-image'    docs/CAPABILITIES.md

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
