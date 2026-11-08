#!/bin/sh
# test_HC_002_ci-dev-main-promotion.sh — CI + dev/main promotion (beaconry-style)
# Story:  docs/stories/HC-002-ci-dev-main-promotion.md
# Plan:   docs/plan/HC-002-ci-dev-main-promotion-plan.md
# CAPs:   workflow.ci-stratified, workflow.release-promotion,
#         workflow.version-sync-gate, workflow.pre-push-gate,
#         workflow.hooks-via-pre-commit

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

assert_grep() { pat=$1; file=$2
  if grep -Eq "$pat" "$file" 2>/dev/null; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL grep '$pat' in $file"; fi; }

# Resolve repo root relative to this script so the test is CWD-independent.
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1

# ----- Scenario 1 — hook install works without core.hooksPath conflict -----
# The Makefile recipe must defensively unset core.hooksPath before calling
# pre-commit install. We test the recipe's logic WITHOUT touching the real
# user's git config: simulate by grepping the recipe for both invariants.
assert_grep '^\s*@git config --unset-all core.hooksPath'  Makefile
assert_grep 'pre-commit install --hook-type commit-msg'   Makefile
assert_grep 'pre-commit install.*--hook-type pre-commit'  Makefile
assert_grep 'pre-commit install.*--hook-type pre-push'    Makefile
# And a direct recipe parse (make -n install-hooks) must succeed:
assert_rc 0 make -n install-hooks
# And .githooks/ must be gone (its contents moved to scripts/).
assert_absent .githooks

# ----- Scenario 2 — CI workflow files present + valid YAML + jobs ----------
assert_exists .github/workflows/ci.yml
assert_exists .github/workflows/release.yml

# Validate YAML syntax via python (ships with every runner we'd target).
if command -v python3 >/dev/null 2>&1; then
  for y in .github/workflows/ci.yml .github/workflows/release.yml; do
    assert_rc 0 python3 -c "import yaml, sys; yaml.safe_load(open('$y'))"
  done
fi

# ci.yml has the three stratified job names (exact names matter for
# release.yml's check-run assertion).
assert_grep '^  fast-check:'    .github/workflows/ci.yml
assert_grep '^  full-check:'    .github/workflows/ci.yml
assert_grep '^  release-check:' .github/workflows/ci.yml
# release.yml uses workflow_dispatch and asserts CI green before promoting.
assert_grep 'workflow_dispatch' .github/workflows/release.yml
assert_grep 'Full check \(make check\)' .github/workflows/release.yml
assert_grep 'merge --ff-only'   .github/workflows/release.yml

# ----- Scenario 3 — VERSION semver + CHANGELOG entry -----------------------
assert_exists VERSION
assert_exists CHANGELOG.md

v=$(tr -d '[:space:]' < VERSION 2>/dev/null || echo "")
case "$v" in
  *[!0-9.]*|"")  fail=$((fail + 1)); echo "FAIL VERSION has non-digit chars: '$v'" ;;
  *.*.*)          pass=$((pass + 1)) ;;
  *)              fail=$((fail + 1)); echo "FAIL VERSION '$v' is not M.m.p" ;;
esac

# CHANGELOG has the heading for the current VERSION.
assert_grep "^## \[v${v}\]" CHANGELOG.md

# ----- Scenario 4 — verify-version-bumped behaviour ------------------------
assert_exec scripts/verify-version-bumped.sh

# Bypass path: HEALTHY_SKIP_VERSION_BUMP=1 always exits 0.
assert_rc 0 env HEALTHY_SKIP_VERSION_BUMP=1 bash scripts/verify-version-bumped.sh

# verify-version-bumped intentionally short-circuits on branch 'main' (main
# advances via release.yml, not direct pushes). On main, the force-fail and
# pass paths below can't be exercised — the script returns 0 unconditionally.
# HC-003: guard the branch so the test is correct on main too.
cur_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

if [ "$cur_branch" = "main" ]; then
  # On main, the short-circuit IS the behaviour under test.
  # The real gate for 'VERSION unchanged' only applies off-main.
  assert_rc 0 bash scripts/verify-version-bumped.sh
elif git rev-parse --verify --quiet origin/main >/dev/null 2>&1 \
     && git show origin/main:VERSION >/dev/null 2>&1; then
  # Off main with an origin/main:VERSION present → exercise both paths.
  orig=$(tr -d '[:space:]' < VERSION)
  mainver=$(git show origin/main:VERSION | tr -d '[:space:]')

  # `env -u HEALTHY_SKIP_VERSION_BUMP` because the operator may have exported
  # the bypass for the surrounding `git push` (legitimate — e.g. folding a
  # fix into the current VERSION without bumping). Inside this test we need
  # the gate to run for real, so strip the bypass for these two subprocesses.
  # Same bug class beaconry caught as BC-071.

  # Force-fail path: VERSION identical to origin/main's → gate MUST fail.
  echo "$mainver" > VERSION
  env -u HEALTHY_SKIP_VERSION_BUMP bash scripts/verify-version-bumped.sh >/dev/null 2>&1; rc_fail=$?
  # Pass path: VERSION set to a value NOT in origin/main → gate MUST pass.
  echo "999.999.999" > VERSION
  env -u HEALTHY_SKIP_VERSION_BUMP bash scripts/verify-version-bumped.sh >/dev/null 2>&1; rc_pass=$?
  echo "$orig" > VERSION

  if [ "$rc_fail" != 0 ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL verify-version-bumped should fail when VERSION unchanged vs origin/main"; fi

  if [ "$rc_pass" = 0 ]; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL verify-version-bumped should pass when VERSION differs from origin/main"; fi
else
  # Upstream has no VERSION — only exercise the short-circuit path.
  assert_rc 0 bash scripts/verify-version-bumped.sh
fi

# ----- Scenario 5 — verify-changelog behaviour -----------------------------
assert_exec scripts/verify-changelog.sh

# Bypass path must succeed unconditionally.
assert_rc 0 env HEALTHY_SKIP_CHANGELOG=1 bash scripts/verify-changelog.sh

# Normal path with our well-formed CHANGELOG + VERSION: must succeed.
assert_rc 0 bash scripts/verify-changelog.sh

# Force-fail path: swap VERSION to a value we know has no CHANGELOG entry.
# Strip any inherited HEALTHY_SKIP_CHANGELOG from the surrounding env so the
# gate runs for real (same BC-071-class leak concern as version-bumped).
orig_v=$(tr -d '[:space:]' < VERSION)
echo "99.99.99" > VERSION
env -u HEALTHY_SKIP_CHANGELOG bash scripts/verify-changelog.sh >/dev/null 2>&1; rc=$?
echo "$orig_v" > VERSION
if [ "$rc" != 0 ]; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL verify-changelog should fail for a VERSION with no entry"; fi

# ----- Scenario 6 — conventional-commit gate still works -------------------
hook=scripts/check-commit-msg.sh
assert_exec "$hook"
tmp=$(mktemp)
for bad in "garbage message" "WIP: something" "Added feature" "feat no colon"; do
  printf '%s\n' "$bad" > "$tmp"
  assert_rc 1 bash "$hook" "$tmp"
done
for ok in "feat(hc): add ipv6 support" \
          "fix: correct build flag order" \
          "chore(ci): pin zig to 0.17.1" \
          "Merge branch 'feat/x' into main" \
          "Revert \"feat(hc): foo\""; do
  printf '%s\n' "$ok" > "$tmp"
  assert_rc 0 bash "$hook" "$tmp"
done
rm -f "$tmp"

# ----- Scenario 7 — pre-push covers the majority of issues -----------------
# .pre-commit-config.yaml must wire make check + verify-version-bumped
# + verify-changelog into the pre-push stage. We grep the YAML; a proper
# parse would be nicer but shellcheck-only hosts don't have pyyaml.
cfg=.pre-commit-config.yaml
assert_grep 'id: make-check'            "$cfg"
assert_grep 'id: verify-version-bumped' "$cfg"
assert_grep 'id: verify-changelog'      "$cfg"
assert_grep 'stages: \[pre-push\]'      "$cfg"
# And the commit-msg stage must reference our script.
assert_grep 'id: conventional-commit'   "$cfg"
assert_grep 'stages: \[commit-msg\]'    "$cfg"
# No reference to the old .githooks/ layout anywhere.
if ! grep -rq '\.githooks' Makefile .pre-commit-config.yaml 2>/dev/null; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL stale .githooks reference in Makefile or .pre-commit-config.yaml"
fi

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
