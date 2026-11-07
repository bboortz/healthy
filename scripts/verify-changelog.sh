#!/usr/bin/env bash
# Refuse pushes that don't carry a CHANGELOG.md entry for the current VERSION.
#
# Asserts that CHANGELOG.md contains a line matching "## [v<VERSION>]"
# where <VERSION> is the content of ./VERSION. Idempotent, side-effect-free.
#
# Bypass with HEALTHY_SKIP_CHANGELOG=1 (emergencies only — document in the PR).
set -euo pipefail

if [[ "${HEALTHY_SKIP_CHANGELOG:-}" == "1" ]]; then
  echo "verify-changelog: skipped (HEALTHY_SKIP_CHANGELOG=1)"
  exit 0
fi

if [[ ! -f VERSION ]]; then
  echo "FAIL: VERSION file missing at repo root" >&2
  exit 1
fi
if [[ ! -f CHANGELOG.md ]]; then
  echo "FAIL: CHANGELOG.md missing at repo root" >&2
  exit 1
fi

version=$(tr -d '[:space:]' < VERSION)
heading="## [v${version}]"

if ! grep -Fq "$heading" CHANGELOG.md; then
  echo "FAIL: CHANGELOG.md has no entry for VERSION $version" >&2
  echo "      expected a line starting with: $heading" >&2
  echo "      add an entry, then re-stage. bypass: HEALTHY_SKIP_CHANGELOG=1" >&2
  exit 1
fi

echo "verify-changelog: ok (v$version has an entry)"
