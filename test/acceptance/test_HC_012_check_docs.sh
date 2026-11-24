#!/bin/sh
# test_HC_012_check_docs.sh — fleet-wide check-docs wrapper (HC-012 / SH-055)
# Story:  docs/stories/HC-012-sh055-check-docs.md
# Plan:   docs/plan/HC-012-sh055-check-docs-plan.md
# CAPs:   shepherd.check-docs

set -u
pass=0; fail=0

assert_rc() { want=$1; shift; "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL want=$want got=$rc: $*"; fi; }

assert_grep() { pattern=$1; shift
  if "$@" 2>&1 | grep -Fq -- "$pattern"; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL output missing '$pattern' from $*"; fi; }

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1

# ----- Scenario 1 — check-docs declared .PHONY ---------------------------
# Line-continuation tolerant: fold logical .PHONY: line to one line then grep.
phony=$(awk '/^\.PHONY:/{flag=1} flag{printf "%s ", $0; if ($0 !~ /\\$/) {print ""; flag=0}}' Makefile)
if printf '%s' "$phony" | grep -Fq "check-docs"; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL .PHONY missing check-docs"; fi

# ----- Scenario 2 — check-docs target exists with prerequisites -----------
if grep -qE '^check-docs:' Makefile; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL check-docs: target not declared in Makefile"; fi

# Healthy's delegate chain: verify-traceability + verify-version-bumped + verify-changelog.
# HC-013 (SH-056) adds verify-index-status at the front — match anywhere in the prerequisite list.
if grep -qE '^check-docs:.* verify-traceability' Makefile; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL check-docs doesn't declare verify-traceability as prerequisite"; fi

if grep -qE '^check-docs:.* verify-version-bumped' Makefile; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL check-docs doesn't declare verify-version-bumped as prerequisite"; fi

if grep -qE '^check-docs:.* verify-changelog' Makefile; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL check-docs doesn't declare verify-changelog as prerequisite"; fi

# ----- Scenario 3 — PUSH_STEPS + BRANCH_STEPS include check-docs ---------
if grep -qE '^PUSH_STEPS.*check-docs' Makefile; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL PUSH_STEPS missing check-docs"; fi

if grep -qE '^BRANCH_STEPS.*check-docs' Makefile; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL BRANCH_STEPS missing check-docs"; fi

# ----- Scenario 4 — make -n check-docs resolves cleanly ------------------
assert_rc 0 make -n check-docs

# ----- Scenario 5 — make -n check-docs invokes the delegate chain --------
# Recipe expands to the underlying scripts.
assert_grep "scripts/verify-traceability.sh"    make -n check-docs
assert_grep "scripts/verify-version-bumped.sh"  make -n check-docs
assert_grep "scripts/verify-changelog.sh"       make -n check-docs

# ----- Scenario 6 — docs files exist -------------------------------------
assert_rc 0 test -f docs/stories/HC-012-sh055-check-docs.md
assert_rc 0 test -f docs/plan/HC-012-sh055-check-docs-plan.md

# ---------------------------------------------------------------------------
echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
