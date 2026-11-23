#!/bin/sh
# test_HC_011_hook_tiers.sh — hook-commit + hook-push fleet-tier wrappers (HC-011 / SH-042)
# Story:  docs/stories/HC-011-sh042-hook-tiers.md
# Plan:   docs/plan/HC-011-sh042-hook-tiers-plan.md
# CAPs:   shepherd.hook-commit, shepherd.hook-push

set -u
pass=0; fail=0

assert_rc() { want=$1; shift; "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL want=$want got=$rc: $*"; fi; }

assert_grep() { needle=$1; shift
  if "$@" 2>&1 | grep -Fq -- "$needle"; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL output missing '$needle' from $*"; fi; }

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1

# ----- Scenario 1 — hook-commit + hook-push declared .PHONY ---------------
# Line-continuation tolerant: fold logical .PHONY: line to one line then grep.
phony=$(awk '/^\.PHONY:/{flag=1} flag{printf "%s ", $0; if ($0 !~ /\\$/) {print ""; flag=0}}' Makefile)
if printf '%s' "$phony" | grep -Fq "hook-commit"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL .PHONY missing hook-commit"; fi
if printf '%s' "$phony" | grep -Fq "hook-push";   then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL .PHONY missing hook-push"; fi

# ----- Scenario 2 — dry-run resolves without executing recipes ------------
assert_rc 0 make -n hook-commit
assert_rc 0 make -n hook-push

# ----- Scenario 3 — hook-commit dry-run invokes the commit steps ----------
# The recipe expands to the underlying commands, so match those markers.
assert_grep "zig fmt --check"              make -n hook-commit
assert_grep "shellcheck"                   make -n hook-commit
assert_grep "scripts/verify-traceability.sh" make -n hook-commit

# ----- Scenario 4 — hook-push dry-run invokes the push steps --------------
assert_grep "scripts/build.sh"                 make -n hook-push
assert_grep "./test/run.sh"                    make -n hook-push
assert_grep "scripts/verify-version-bumped.sh" make -n hook-push
assert_grep "scripts/verify-changelog.sh"      make -n hook-push

# ----- Scenario 5 — docs link resolves ------------------------------------
assert_rc 0 test -f docs/stories/HC-011-sh042-hook-tiers.md
assert_rc 0 test -f docs/plan/HC-011-sh042-hook-tiers-plan.md

# ---------------------------------------------------------------------------
echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
