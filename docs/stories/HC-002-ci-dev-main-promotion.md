---
id: HC-002
slug: ci-dev-main-promotion
status: shipped
created: 2026-11-07
shipped: 2026-11-07
owner: @benni
---

# HC-002 — CI pipeline + dev/main promotion (beaconry-style)

## 1. Who is the consumer?

**The maintainer** pushing branches, and anyone opening a PR. CI is the second
pair of eyes; the pre-push hook is the first.

## 2. When does the story fire?

Every `git push`. Local pre-push runs the heavy gate (`make check` + VERSION +
CHANGELOG); CI mirrors it in a stratified pipeline so broken pushes get caught
the same way whether the operator bypasses hooks or not.

## 3. What does success look like?

Observable at merge time:

- `make install-hooks` succeeds on a fresh clone (no `core.hooksPath` /
  pre-commit framework conflict).
- Pre-push hook runs the full local gate: `make check` + `verify-changelog` +
  `verify-version-bumped`. A push that would fail CI fails pre-push first.
- `.github/workflows/ci.yml` stratifies by branch:
  - feature push → `fast-check` (lint + traceability, ~30s)
  - `dev` push / PR to `dev` → `full-check` (`make check`, ~2–3min)
  - `main` push → `release-check` (CHANGELOG + VERSION sync + tag presence, ~15s)
- `.github/workflows/release.yml` promotes `dev` → `main` on manual
  `workflow_dispatch`, asserts CI was green on `dev`, fast-forwards `main`, and
  tags `v<VERSION>`.
- `VERSION` + `CHANGELOG.md` live at the repo root; every push to `dev`+ must
  bump `VERSION` and name that version in `CHANGELOG.md`.
- Docs-only diffs short-circuit the heavy CI job.
- Any CI failure optionally pings a Telegram webhook (no-op without secrets).

## 4. How urgent?

**Correctness** — the DD-TGD contract says gates exist. Until CI runs, the only
gate is the operator's local box; anyone bypassing with `--no-verify` reaches
`main` unchallenged. Not security-critical, but foundationally blocking before
HC-003.

## 5. Happy path

```sh
# From main:
git checkout -b feat/HC-NNN-<slug>                  # branch off main (temporary — becomes dev after HC-002 ships)
# ...edit, bump VERSION, add CHANGELOG entry...
git commit -m "feat(hc): <description>"              # commit-msg gate: conventional commits
git push                                             # pre-push gate: make check + verify-version-bumped + verify-changelog
#                                                      → CI fast-check runs on the branch
gh pr create --base dev                              # once dev exists, PRs target it
#                                                      → CI full-check runs on the PR
# ...review + squash-merge not used — merge-commit preserves PR boundary...
# Operator clicks "Run workflow" on .github/workflows/release.yml
#                                                      → asserts CI green on dev → fast-forwards main → tags v<VERSION>
```

## 6. Edge cases / failure modes that matter

- `pre-commit` isn't installed yet (fresh clone): `make install-hooks` must
  print a clear error, not silently skip.
- `core.hooksPath` is already set (from the old HC-001 Makefile): `make
  install-hooks` must unset it defensively before calling `pre-commit install`.
- `VERSION` isn't bumped since `origin/main`: `verify-version-bumped` must
  fail the push with a one-line fix hint. `HEALTHY_SKIP_VERSION_BUMP=1` is the
  emergency bypass.
- `CHANGELOG.md` is missing an entry for the current `VERSION`:
  `verify-changelog` must fail with the exact missing heading. Bypass:
  `HEALTHY_SKIP_CHANGELOG=1`.
- `dev` branch doesn't exist yet (HC-002 is itself the first PR): the CI
  `full-check` trigger on `dev` simply doesn't fire. HC-002 lands on `main` as
  the last direct push; the plan's rollout section creates `dev` from `main`.
- CI runs on `dev` but hasn't finished when the operator clicks
  `workflow_dispatch`: the release workflow must fail loudly ("CI not yet
  green"), not race.
- Docs-only push: `full-check` must short-circuit so a typo fix doesn't burn
  3 min of CI.
- Operator's shell has a stale `python-zig` symlink / stale pipx venv (seen
  during HC-001): `make tools` is still the entry point, and the acceptance
  test exercises it via `make -n tools`.

## 7. Out of scope

- Publishing the binary anywhere. No GHCR push, no release-artefact upload.
  That's a later story once a consumer actually asks.
- Signing / SBOM / supply-chain gates. Not applicable to a self-built static
  binary without a distribution channel.
- Branch protection on `main` / `dev`. The release-workflow uses the default
  `GITHUB_TOKEN` with `contents:write`; if branch protection goes on later,
  swap to a PAT (noted in `release.yml`).
- Changing `hc.zig` behaviour. Still frozen.
- Removing the `test/acceptance/test_HC_001_…` assertion about the commit-msg
  gate — it gets *updated* (path moves from `.githooks/commit-msg` to
  `scripts/check-commit-msg.sh`) but the Gherkin is preserved.

## 8. Acceptance (Gherkin → shell assertions)

```gherkin
Scenario: Hook install works without core.hooksPath conflict
  Given a working tree with pre-commit installed
  And   `git config core.hooksPath` is unset or set to anything
  When  I run `make install-hooks`
  Then  it exits 0
  And   `git config --get core.hooksPath` returns empty
  And   .git/hooks/commit-msg, pre-commit, pre-push are all pre-commit shims

Scenario: Workflow files are present and valid
  Then .github/workflows/ci.yml exists and parses as YAML
  And  .github/workflows/release.yml exists and parses as YAML
  And  ci.yml declares 'fast-check', 'full-check', 'release-check' jobs
  And  release.yml uses workflow_dispatch

Scenario: VERSION is semver, CHANGELOG has entry
  Then VERSION matches /^[0-9]+\.[0-9]+\.[0-9]+$/
  And  CHANGELOG.md contains "## [v$(cat VERSION)]" on some line

Scenario: verify-version-bumped fails when VERSION unchanged
  Given VERSION matches origin/main:VERSION
  When  I run `scripts/verify-version-bumped.sh`
  Then  it exits non-zero (unless HEALTHY_SKIP_VERSION_BUMP=1)

Scenario: verify-changelog fails when entry missing
  Given CHANGELOG.md has no entry for the current VERSION
  When  I run `scripts/verify-changelog.sh`
  Then  it exits non-zero (unless HEALTHY_SKIP_CHANGELOG=1)

Scenario: Commit-msg gate still rejects garbage, accepts well-formed
  When  I feed "garbage message" through scripts/check-commit-msg.sh
  Then  it exits 1
  When  I feed "feat(hc): valid conventional commit" through it
  Then  it exits 0

Scenario: Pre-push hook list covers the majority of issues
  Then .pre-commit-config.yaml has a pre-push stage that invokes `make check`
  And  it also invokes verify-version-bumped and verify-changelog on pre-push
```

## 9. Capabilities delivered or extended

- `workflow.ci-stratified` — GitHub Actions matrix stratified by branch: fast-check on feature branches, full-check on dev + PRs to dev, release-check on main.
- `workflow.release-promotion` — manual `workflow_dispatch` release workflow fast-forwards `main` from `dev`, asserts CI was green, and tags `v<VERSION>`.
- `workflow.version-sync-gate` — `scripts/verify-version-bumped.sh` + `scripts/verify-changelog.sh` enforce VERSION monotonicity and CHANGELOG entries per push.
- `workflow.pre-push-gate` — pre-push hook runs `make check` + `verify-version-bumped` + `verify-changelog` — the primary gate catching the majority of issues before CI sees them.
- `workflow.hooks-via-pre-commit` — `make install-hooks` installs commit-msg + pre-commit + pre-push via the `pre-commit` framework into `.git/hooks/`, unsetting any pre-existing `core.hooksPath` defensively.
