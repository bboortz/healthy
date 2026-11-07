#!/usr/bin/env bash
# Refuse pushes that don't bump VERSION since origin/main.
#
# Compares the working-tree VERSION to `git show origin/main:VERSION`. Fails
# iff they are string-equal. Idempotent and side-effect-free; safe to re-run.
#
# Bypass with HEALTHY_SKIP_VERSION_BUMP=1 (emergencies only — document in the PR).
set -euo pipefail

if [[ "${HEALTHY_SKIP_VERSION_BUMP:-}" == "1" ]]; then
  echo "verify-version-bumped: skipped (HEALTHY_SKIP_VERSION_BUMP=1)"
  exit 0
fi

if [[ ! -f VERSION ]]; then
  echo "FAIL: VERSION file missing at repo root" >&2
  exit 1
fi

current=$(tr -d '[:space:]' < VERSION)
if ! [[ "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "FAIL: VERSION '$current' is not semver (M.m.p)" >&2
  exit 1
fi

# If origin/main doesn't exist yet (first push, no upstream), the check is
# vacuous — treat as a pass. Also treat a push *from* main as vacuous.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ "$branch" == "main" ]]; then
  echo "verify-version-bumped: on main — skipping (main advances via release.yml)"
  exit 0
fi

if ! git rev-parse --verify --quiet origin/main >/dev/null; then
  echo "verify-version-bumped: origin/main not fetched — skipping"
  exit 0
fi

previous=$(git show origin/main:VERSION 2>/dev/null | tr -d '[:space:]' || echo "")
if [[ -z "$previous" ]]; then
  echo "verify-version-bumped: origin/main has no VERSION yet — skipping (this is HC-002 or earlier)"
  exit 0
fi

if [[ "$current" == "$previous" ]]; then
  echo "FAIL: VERSION ($current) unchanged vs origin/main — bump it" >&2
  echo "      edit VERSION, then re-stage. bypass: HEALTHY_SKIP_VERSION_BUMP=1" >&2
  exit 1
fi

echo "verify-version-bumped: ok ($previous → $current)"
