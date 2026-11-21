#!/bin/sh
# test_HC_008_shepherd_poc.sh — Shepherd on healthy.
# R1 rewrite: the R0 inline-script POC (scripts/shepherd-poc/ + inline
# shepherd-poc.yml) was retired when SH-007 landed the reusable-workflow
# caller. The agent-step sandbox invariants, Setup/Regen/Validate steps
# and Trivy install path now live inside bboortz/shepherd's own test
# suite. This file asserts the caller WIRING on healthy: shepherd.yml +
# shepherd-gates.yml pin the reusable workflow at an SHA.
#
# Story:  docs/stories/HC-008-shepherd-poc.md
# Plan:   docs/plan/HC-008-shepherd-poc-plan.md
# CAPs:   supply-chain.sha-pin-all-actions

set -u
pass=0; fail=0

assert_exists() { f=$1
  if [ -e "$f" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL missing: $f"; fi; }

assert_contains() { file=$1; needle=$2
  if [ -f "$file" ] && grep -Fq -- "$needle" "$file"; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL $file does not contain: $needle"; fi; }

assert_not_contains() { file=$1; needle=$2
  if [ -f "$file" ] && grep -Fq -- "$needle" "$file"; then
    fail=$((fail + 1)); echo "FAIL $file should not contain: $needle"
  else pass=$((pass + 1)); fi; }

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1

wf=.github/workflows/shepherd.yml
gates=.github/workflows/shepherd-gates.yml

# ----- Scenario 1 — Caller is scheduled and dispatch-triggerable ----------
assert_exists "$wf"
assert_exists "$gates"
assert_contains "$wf" "cron:"
assert_contains "$wf" "workflow_dispatch:"

# ----- Scenario 2 — Callers pin the reusable workflow to a 40-hex SHA -----
# SH-001 invariant: every `uses:` references a commit SHA, not a mutable tag.
for f in "$wf" "$gates"; do
  bad=$(grep -E '^\s*(-\s+)?uses:\s+' "$f" | awk -F'@' '{print $2}' | awk '{print $1}' \
        | awk 'length($0) != 40 || tolower($0) !~ /^[0-9a-f]{40}$/' \
        || true)
  if [ -z "$bad" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL $f has non-SHA uses: refs: $bad"; fi
done
assert_contains "$wf" "bboortz/shepherd/.github/workflows/reusable-shepherd.yml@"
assert_contains "$gates" "bboortz/shepherd/.github/workflows/reusable-shepherd-gates.yml@"

# ----- Scenario 3 — No third-party Trivy wrapper (SH-001 invariant) -------
assert_not_contains "$wf" "aquasecurity/trivy-action"

# ----- .shepherd.yml must exist (SH-007 required-config gate) -------------
assert_exists .shepherd.yml

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
