#!/bin/sh
# test_HC_003_robust-release-pipeline.sh — release.yml gate picks the
# right check-run.
# Story: docs/stories/HC-003-robust-release-pipeline.md
# Plan:  docs/plan/HC-003-robust-release-pipeline-plan.md
# CAPs:  workflow.release-check-filter, workflow.release-check-testable

set -u
pass=0; fail=0

# Resolve repo root relative to this script so the test is CWD-independent.
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1

JQ_FILE=scripts/latest-ci-status.jq
FIXTURES=test/acceptance/fixtures/hc-003

assert_exists() { f=$1
  if [ -e "$f" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL missing: $f"; fi; }

assert_jq_output() { want=$1; fixture=$2
  got=$(jq -r -f "$JQ_FILE" "$fixture" 2>&1)
  if [ "$got" = "$want" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL $(basename "$fixture"): want='$want' got='$got'"; fi; }

assert_grep() { pat=$1; file=$2
  if grep -Eq "$pat" "$file" 2>/dev/null; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL grep '$pat' in $file"; fi; }

# ----- Scenario 1 — jq file + fixtures exist -------------------------------
assert_exists "$JQ_FILE"
assert_exists "$FIXTURES/mix_success_then_skipped.json"
assert_exists "$FIXTURES/success_then_failure.json"
assert_exists "$FIXTURES/only_skipped.json"
assert_exists "$FIXTURES/empty.json"

# ----- Scenario 2 — jq output matches the four Gherkin scenarios -----------
# Mix: success (earlier) + skipped (later). Gate must return success.
assert_jq_output "success"     "$FIXTURES/mix_success_then_skipped.json"
# Success (earlier) + failure (later) → failure wins.
assert_jq_output "failure"     "$FIXTURES/success_then_failure.json"
# Only skipped → not-yet-run.
assert_jq_output "not-yet-run" "$FIXTURES/only_skipped.json"
# Empty check_runs → not-yet-run.
assert_jq_output "not-yet-run" "$FIXTURES/empty.json"

# ----- Scenario 3 — release.yml consumes the same jq file ------------------
# Guard against the "two copies, one drifts" failure mode. release.yml must
# reference the jq file; if someone inlines the query again, this breaks.
assert_grep 'scripts/latest-ci-status\.jq' .github/workflows/release.yml

# ----- Scenario 4 — jq file is self-contained (no external deps) -----------
# A fresh jq binary must consume the file without errors on at least one
# fixture. If someone references undefined functions or uses jq extensions
# that aren't in the base distribution, this catches it.
if ! jq -r -f "$JQ_FILE" "$FIXTURES/empty.json" >/dev/null 2>&1; then
  fail=$((fail + 1)); echo "FAIL jq -f $JQ_FILE errored on an empty fixture"
else
  pass=$((pass + 1))
fi

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
