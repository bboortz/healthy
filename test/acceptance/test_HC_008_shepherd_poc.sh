#!/bin/sh
# test_HC_008_shepherd_poc.sh — Shepherd on healthy.
# R1 rewrite: the R0 inline-script POC migrated to the shepherd reusable
# workflow (SH-007). The agent-step sandbox invariants, Setup/Regen/Validate
# steps, and Trivy install path now live in bboortz/shepherd's own test suite.
# Here we assert the caller WIRING: shepherd.yml + shepherd-gates.yml pin
# the reusable workflow at an SHA, `.shepherd.yml` + scripts/shepherd-poc/*
# are still present, and validate.sh still rejects the protected-path and
# oversize fixtures.
#
# Story:  docs/stories/HC-008-shepherd-poc.md
# Plan:   docs/plan/HC-008-shepherd-poc-plan.md
# CAPs:   shepherd.blocklist.protected-files, shepherd.gate.diff-size,
#         shepherd.scope.level-1, supply-chain.sha-pin-all-actions

set -u
pass=0; fail=0

assert_rc() { want=$1; shift; "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL want=$want got=$rc: $*"; fi; }

assert_exists() { f=$1
  if [ -e "$f" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL missing: $f"; fi; }

assert_exec() { f=$1
  if [ -x "$f" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL not executable: $f"; fi; }

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
validate=scripts/shepherd-poc/validate.sh
install=scripts/shepherd-poc/install-trivy.sh

# ----- Scenario 1 — Caller is scheduled and dispatch-triggerable ----------
assert_exists "$wf"
assert_exists "$gates"
assert_contains "$wf" "cron:"
assert_contains "$wf" "workflow_dispatch:"

# ----- Scenario 2 — Callers pin the reusable workflow to a 40-hex SHA ------
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

# ----- Scenario 3 — scripts exist + executable ----------------------------
# The R0 scripts are retained on dev as fixture providers for the validate/
# install assertions below; the agent itself no longer runs them (R1 moved
# the sandbox into the reusable workflow).
for s in install-trivy.sh agent-call.sh validate.sh regen-lockfile.sh open-pr.sh; do
  assert_exists  "scripts/shepherd-poc/$s"
  assert_exec    "scripts/shepherd-poc/$s"
done

# ----- Scenario 4 — validate.sh blocks a diff touching .github/workflows/ -
assert_rc 2 "$validate" test/acceptance/fixtures/HC_008_blocked_workflow.patch

# ----- Scenario 5 — validate.sh blocks a diff touching .shepherd.yml ------
assert_rc 2 "$validate" test/acceptance/fixtures/HC_008_blocked_shepherd_yml.patch

# ----- Scenario 6 — validate.sh blocks an oversize diff --------------------
assert_rc 2 "$validate" test/acceptance/fixtures/HC_008_oversize.patch

# ----- Scenario 7 — validate.sh accepts a small allowed diff --------------
assert_rc 0 "$validate" test/acceptance/fixtures/HC_008_ok_small.patch

# ----- Scenario 8 — install-trivy.sh --dry-run names cosign verify-blob ---
out=$("$install" --dry-run 2>&1 || true)
if printf '%s' "$out" | grep -q "cosign verify-blob"; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL install-trivy.sh --dry-run missing cosign mention"; fi
if printf '%s' "$out" | grep -q "sigstore"; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL install-trivy.sh --dry-run missing sigstore bundle reference"; fi

# ----- Scope level 1 — the prompt forbids workflow + .shepherd.yml writes --
assert_contains scripts/shepherd-poc/agent-call.sh "manifest files only"
assert_contains scripts/shepherd-poc/agent-call.sh ".shepherd.yml"
assert_contains scripts/shepherd-poc/agent-call.sh "NO_FIX_POSSIBLE"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
