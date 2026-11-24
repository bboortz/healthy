#!/bin/sh
# test_HC_013_verify_index_status.sh — INDEX ↔ frontmatter status drift (HC-013 / SH-056)
# Story:  docs/stories/HC-013-sh056-verify-index-status.md
# Plan:   docs/plan/HC-013-sh056-verify-index-status-plan.md
# CAPs:   shepherd.verify-index-status

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

SCRIPT="$repo/scripts/verify-index-status.sh"
INDEX="$repo/docs/stories/INDEX.md"

# ----- Scenario 1 — script exists + executable ---------------------------
assert_rc 0 test -f "$SCRIPT"
assert_rc 0 test -x "$SCRIPT"

# ----- Scenario 2 — healthy itself passes (dogfood) ----------------------
assert_rc 0 "$SCRIPT"
assert_grep "ok (INDEX.md matches frontmatter for all stories)" "$SCRIPT"

# ----- Scenario 3 — drift catch: flip HC-012 row to draft ----------------
cp "$INDEX" /tmp/hc-013-index.bak
trap 'cp /tmp/hc-013-index.bak "$INDEX"; rm -f /tmp/hc-013-index.bak' EXIT

sed -i 's/| HC-012 | shipped |/| HC-012 | draft |/' "$INDEX"
assert_rc 1 "$SCRIPT"
assert_grep "HC-012" "$SCRIPT"
assert_grep "INDEX row status='draft' but frontmatter says 'shipped'" "$SCRIPT"
cp /tmp/hc-013-index.bak "$INDEX"

# ----- Scenario 4 — drift catch: delete HC-012 row -----------------------
grep -v "^| HC-012 " "$INDEX" > /tmp/hc-013-index.notrow
cp /tmp/hc-013-index.notrow "$INDEX"
assert_rc 1 "$SCRIPT"
assert_grep "HC-012: missing INDEX.md row" "$SCRIPT"
cp /tmp/hc-013-index.bak "$INDEX"
rm -f /tmp/hc-013-index.notrow

# ----- Scenario 5 — Makefile exposes verify-index-status -----------------
# .PHONY may span multi-line with backslash continuations; fold then grep.
phony=$(awk '/^\.PHONY:/{flag=1} flag{printf "%s ", $0; if ($0 !~ /\\$/) {print ""; flag=0}}' Makefile)
if printf '%s' "$phony" | grep -Fq "verify-index-status"; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL .PHONY missing verify-index-status"; fi
if grep -qE '^verify-index-status:' Makefile; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL Makefile missing 'verify-index-status:' target"; fi

# ----- Scenario 6 — check-docs includes verify-index-status --------------
if grep -qE '^check-docs:.* verify-index-status' Makefile; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL check-docs doesn't depend on verify-index-status"; fi

# ----- Scenario 7 — make -n verify-index-status resolves cleanly --------
assert_rc 0 make -n verify-index-status
assert_grep "scripts/verify-index-status.sh" make -n verify-index-status

# ----- Scenario 8 — no-op guard when INDEX absent ------------------------
# Use a temp fixture outside the repo so script's root-style guard fires.
tmp=$(mktemp -d)
mkdir -p "$tmp/scripts" "$tmp/docs/stories"
cp "$SCRIPT" "$tmp/scripts/"
# Script resolves root relative to its own dir — run from the fixture.
( cd "$tmp" && ./scripts/verify-index-status.sh ) >/dev/null 2>&1
rc=$?
if [ "$rc" = 0 ]; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL no-INDEX guard: expected exit 0, got $rc"; fi
rm -rf "$tmp"

# ---------------------------------------------------------------------------
echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
