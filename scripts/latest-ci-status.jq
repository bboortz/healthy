# Single source of truth for release.yml's "Assert CI is green" gate.
# Consumed by:
#   - .github/workflows/release.yml  (production)
#   - test/acceptance/test_HC_003_robust-release-pipeline.sh  (fixtures)
#
# Input: JSON payload from GitHub's `GET /repos/{owner}/{repo}/commits/{ref}/check-runs`.
# Output: the conclusion of the latest *non-skipped* check-run named
#         "Full check (make check)", or "not-yet-run" if no such run exists.
#
# Why filter skipped: the same SHA often carries multiple check-runs with
# the same name — one from the dev push (success), one from a later main push
# (skipped because full-check's `if:` evaluated false). Without the filter,
# `sort_by(.started_at) | .[-1]` picks the skip, masking the real success.
[.check_runs[]
  | select(.name == "Full check (make check)" and .conclusion != "skipped")]
| sort_by(.started_at)
| .[-1].conclusion // "not-yet-run"
