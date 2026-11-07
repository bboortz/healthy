#!/bin/sh
# test_HC_001_dd-tgd-bootstrap.sh — foundational DD-TGD scaffold + bin/+scripts/ layout
# Story:  docs/stories/HC-001-dd-tgd-bootstrap.md
# Plan:   docs/plan/HC-001-dd-tgd-bootstrap-plan.md
# CAPs:   workflow.local-gate-check, workflow.tools-bootstrap,
#         workflow.traceability-gate, workflow.commit-msg-gate,
#         build.out-dir-bin, build.scripts-dir

set -u
pass=0; fail=0

assert_rc() { want=$1; shift; "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL want=$want got=$rc: $*"; fi; }

assert_exists() { f=$1
  if [ -e "$f" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL missing: $f"; fi; }

assert_absent() { f=$1
  if [ ! -e "$f" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL should not exist: $f"; fi; }

assert_exec() { f=$1
  if [ -x "$f" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL not executable: $f"; fi; }

assert_line_cap() { f=$1; cap=$2
  if [ -f "$f" ]; then
    n=$(wc -l < "$f")
    if [ "$n" -le "$cap" ]; then pass=$((pass + 1))
    else fail=$((fail + 1)); echo "FAIL $f has $n lines (cap $cap)"; fi
  else fail=$((fail + 1)); echo "FAIL $f missing for size check"; fi; }

# Resolve repo root relative to this script so the test is CWD-independent.
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1

# ----- Scenario 1 — scaffold files exist -----------------------------------
assert_exists docs/stories/_template.md
assert_exists docs/stories/_9-questions.md
assert_exists docs/stories/INDEX.md
assert_exists docs/plan/_template.md
assert_exists docs/plan/IDEAS.md
assert_exists docs/CAPABILITIES.md
assert_exec   scripts/verify-traceability.sh
assert_exec   .githooks/commit-msg
assert_exists .pre-commit-config.yaml
assert_exists memory/MEMORY.md
assert_exists CLAUDE.md

# ----- Scenario 2 — traceability gate green --------------------------------
assert_rc 0 bash scripts/verify-traceability.sh

# ----- Scenario 3 — build outputs land under bin/ --------------------------
assert_exists bin/hc-x86_64-linux
for stray in hc-x86_64-linux hc-aarch64-linux hc-riscv64-linux \
             hc-arm-linux-musleabihf hc-x86-linux hc-x86_64-linux-notls; do
  assert_absent "$stray"
done

# ----- Scenario 4 — build driver lives under scripts/ ----------------------
assert_exec   scripts/build.sh
assert_absent build.sh

# ----- Scenario 5 — size caps enforced -------------------------------------
assert_line_cap CLAUDE.md 150
for f in memory/*.md; do
  [ "$(basename "$f")" = "MEMORY.md" ] && continue
  assert_line_cap "$f" 150
done

# ----- Scenario 6 — flowflow targets exist and parse -----------------------
for t in tools build cross test test-acceptance lint zig-fmt shell-lint \
         verify-traceability size check install-hooks clean distclean; do
  assert_rc 0 make -n "$t"
done

# ----- Scenario 7 — conventional-commit gate -------------------------------
hook=.githooks/commit-msg
tmp=$(mktemp)
# bad subjects → rc=1
for bad in "garbage message" "WIP: something" "Added feature" "feat no colon"; do
  printf '%s\n' "$bad" > "$tmp"
  assert_rc 1 bash "$hook" "$tmp"
done
# good subjects → rc=0
for ok in "feat(hc): add ipv6 support" \
          "fix: correct build flag order" \
          "chore(ci): pin zig to 0.17.1" \
          "Merge branch 'feat/x' into main" \
          "Revert \"feat(hc): foo\""; do
  printf '%s\n' "$ok" > "$tmp"
  assert_rc 0 bash "$hook" "$tmp"
done
rm -f "$tmp"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
