#!/bin/sh
# test_HC_008_shepherd_poc.sh — Shepherd Release 0 POC on healthy.
# Story:  docs/stories/HC-008-shepherd-poc.md
# Plan:   docs/plan/HC-008-shepherd-poc-plan.md
# CAPs:   shepherd.scan-trivy, shepherd.sandbox.no-secrets,
#         shepherd.sandbox.diff-only, shepherd.blocklist.protected-files,
#         shepherd.gate.diff-size, shepherd.scope.level-1,
#         supply-chain.sha-pin-all-actions

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

wf=.github/workflows/shepherd-poc.yml
validate=scripts/shepherd-poc/validate.sh
install=scripts/shepherd-poc/install-trivy.sh

# ----- Scenario 1 — Workflow is scheduled and dispatch-triggerable ---------
assert_exists "$wf"
assert_contains "$wf" "cron:"
assert_contains "$wf" "workflow_dispatch:"

# ----- Scenario 2 — No third-party Action wrapper for Trivy (SH-001) -------
assert_not_contains "$wf" "aquasecurity/trivy-action"
# Every third-party `uses:` must be 40-hex SHA-pinned.
bad=$(grep -E '^\s*(-\s+)?uses:\s+' "$wf" | awk -F'@' '{print $2}' | awk '{print $1}' \
      | awk 'length($0) != 40 || tolower($0) !~ /^[0-9a-f]{40}$/' \
      || true)
if [ -z "$bad" ]; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL $wf has non-SHA uses: refs: $bad"; fi

# ----- Scenario 3 — scripts exist + executable ----------------------------
for s in install-trivy.sh agent-call.sh validate.sh open-pr.sh; do
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
assert_contains scripts/shepherd-poc/agent-call.sh "dependencies and lockfiles"
assert_contains scripts/shepherd-poc/agent-call.sh ".shepherd.yml"
assert_contains scripts/shepherd-poc/agent-call.sh "NO_FIX_POSSIBLE"

# ----- Sandbox invariant — agent step only sees ANTHROPIC_API_KEY ---------
# The agent step's env: block must not reference GITHUB_TOKEN or secrets.GITHUB_TOKEN.
awk_prog='
  /^      - name: Agent call/ { in_step = 1 }
  in_step && /^      - name:/ && !/^      - name: Agent call/ { in_step = 0 }
  in_step { print }
'
agent_block=$(awk "$awk_prog" "$wf")
if printf '%s' "$agent_block" | grep -q "GITHUB_TOKEN"; then
  fail=$((fail + 1)); echo "FAIL agent step env: contains GITHUB_TOKEN"
else pass=$((pass + 1)); fi

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
