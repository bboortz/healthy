#!/bin/sh
# scripts/test-affected.sh — diff-aware wrapper for `make test-affected`.
# Mirrors shepherd SH-036 pattern; adapted to healthy's two test tiers:
#   1. test/run.sh            — functional TLS/HTTP/idle tests against hc binary
#   2. test/acceptance/test_HC_<N>_*.sh — DD-TGD acceptance tests
#
# Full-run bailouts: Makefile, build.zig, .github/workflows/**,
# docs/CAPABILITIES.md, scripts/test-affected.sh itself.
#
# Opt-out: TEST_AFFECTED_BASE=<ref> overrides diff base.
#
# Usage:
#   scripts/test-affected.sh           # emit selection + run
#   scripts/test-affected.sh --list    # emit only

set -eu

mode=${1:-run}

base="${TEST_AFFECTED_BASE:-}"
if [ -z "$base" ]; then
  if git rev-parse --verify origin/dev >/dev/null 2>&1; then
    base=$(git merge-base HEAD origin/dev 2>/dev/null || git rev-parse origin/dev)
  elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    base=$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse origin/main)
  else
    base=HEAD
  fi
fi

{
  git diff --name-only "$base"...HEAD 2>/dev/null
  git diff --name-only
  git diff --cached --name-only
} | sort -u | grep -v '^$' > /tmp/hc-affected-changed.txt || true

FULL_RE='^(Makefile|build\.zig|\.github/workflows/|docs/CAPABILITIES\.md|scripts/test-affected\.sh)$'

run_functional=0
acceptance_tests=""

if grep -Eq "$FULL_RE" /tmp/hc-affected-changed.txt; then
  echo "test-affected: full-run (diff touches build/workflow/CAPABILITIES surface)"
  run_functional=1
  acceptance_tests=$(ls test/acceptance/test_HC_*.sh 2>/dev/null || true)
elif ! [ -s /tmp/hc-affected-changed.txt ]; then
  echo "test-affected: no changes vs $base — running full suite"
  run_functional=1
  acceptance_tests=$(ls test/acceptance/test_HC_*.sh 2>/dev/null || true)
else
  rm -f /tmp/hc-affected-select.txt; touch /tmp/hc-affected-select.txt

  while IFS= read -r f; do
    case "$f" in
      hc.zig|scripts/*.sh|test/run.sh|test/srv.py)
        run_functional=1
        ;;
      test/acceptance/test_HC_*.sh)
        echo "$f" >> /tmp/hc-affected-select.txt
        ;;
      docs/stories/HC-*.md|docs/plan/HC-*.md)
        n=$(echo "$f" | sed -n 's|.*/HC-\([0-9][0-9]*\)-.*|\1|p')
        [ -n "$n" ] && ls test/acceptance/test_HC_"${n}"_*.sh 2>/dev/null >> /tmp/hc-affected-select.txt || true
        ;;
      *)
        # Unknown path: always include the first 2 acceptance tests as a safety net
        # (traceability + docs-layout equivalents on healthy).
        # shellcheck disable=SC2012
        ls test/acceptance/test_HC_*.sh 2>/dev/null | head -2 >> /tmp/hc-affected-select.txt || true
        ;;
    esac
  done < /tmp/hc-affected-changed.txt

  acceptance_tests=$(sort -u /tmp/hc-affected-select.txt | grep -v '^$' || true)

  if [ "$run_functional" = 1 ] && [ -z "$acceptance_tests" ]; then
    echo "test-affected: diff-aware (functional-only — binary/scripts touched, no acceptance test affected)"
  elif [ "$run_functional" = 1 ] && [ -n "$acceptance_tests" ]; then
    n=$(printf '%s\n' "$acceptance_tests" | wc -l | tr -d ' ')
    echo "test-affected: diff-aware (functional + $n acceptance test(s))"
  elif [ -n "$acceptance_tests" ]; then
    n=$(printf '%s\n' "$acceptance_tests" | wc -l | tr -d ' ')
    echo "test-affected: diff-aware ($n acceptance test(s) selected from diff)"
  else
    echo "test-affected: no mappable tests from diff"
  fi
fi

# ---- show selection -----------------------------------------------------
[ "$run_functional" = 1 ] && echo "  test/run.sh"
printf '%s\n' "$acceptance_tests" | sed 's/^/  /'

[ "$mode" = "--list" ] && exit 0

# ---- run ---------------------------------------------------------------
fail=0

if [ "$run_functional" = 1 ]; then
  echo "→ test/run.sh"
  if ! make -s test; then
    fail=$((fail + 1))
    echo "FAIL test/run.sh (via make test)"
  fi
fi

for t in $acceptance_tests; do
  echo "→ $t"
  if ! sh "$t"; then
    fail=$((fail + 1))
    echo "FAIL $t"
  fi
done

if [ "$fail" != 0 ]; then
  echo "test-affected: $fail failure(s)"
  exit 1
fi
echo "test-affected: all passed"
