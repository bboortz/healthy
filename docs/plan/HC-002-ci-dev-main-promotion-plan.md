---
id: HC-002
slug: ci-dev-main-promotion
story: docs/stories/HC-002-ci-dev-main-promotion.md
branch: feat/HC-002-ci-dev-main-promotion
status: shipped
shipped: 2026-11-07
---

# HC-002 plan — CI pipeline + dev/main promotion (beaconry-style)

**Story:** [HC-002](../stories/HC-002-ci-dev-main-promotion.md)

## Design delta

Four kinds of changes, delivered together because the pre-push gate, the CI
pipeline, and the promotion workflow are three faces of one contract.

**A. Hook install rework** (fixes the reported `make install-hooks` error)
- `.pre-commit-config.yaml` rewritten with three stages:
  - `commit-msg` (local hook → `scripts/check-commit-msg.sh`)
  - `pre-commit` (fast: shellcheck, zig fmt, memory-size, verify-traceability)
  - `pre-push` (heavy: `make check` + `verify-version-bumped` + `verify-changelog`)
- `make install-hooks` recipe now:
  - Unsets `core.hooksPath` defensively (`git config --unset-all core.hooksPath`).
  - Calls `pre-commit install --hook-type commit-msg --hook-type pre-commit --hook-type pre-push`.
- Delete `.githooks/commit-msg` and `.githooks/README.md`; move the commit-msg
  script to `scripts/check-commit-msg.sh` (invoked by the `commit-msg` stage).

**B. CI pipeline** (`.github/workflows/ci.yml`)
- Three jobs, stratified by branch:
  - `fast-check`: `make lint` + `make verify-traceability`. Runs on all `feat/*`,
    `fix/*`, `docs/*`, `chore/*`, `refactor/*`, `test/*`, `ci/*` pushes. ~30s.
  - `full-check`: `make check` + `make verify-changelog`. Runs on `dev` pushes
    and PRs targeting `dev`. ~2–3min. Depends on `detect` for docs-only skip.
  - `release-check`: `make verify-changelog` + VERSION sync + tag-presence
    warning. Runs on `main` pushes. ~15s.
- `detect` precursor job sets `docs_only=true` if the diff only touches `.md`
  files or `docs/`; `full-check` consults it to short-circuit.
- `concurrency: cancel-in-progress` so new commits kill stale CI runs.
- `notify-failure` job pings Telegram on failure *iff* `TELEGRAM_BOT_TOKEN` +
  `TELEGRAM_CHAT_ID` are set as secrets. No-op otherwise.
- Zig is installed via the `pipx install ziglang==0.17.1` recipe from
  `make tools`, then symlinked to `~/.local/bin/zig` to match local dev.

**C. Release pipeline** (`.github/workflows/release.yml`)
- `workflow_dispatch` only. Input `ref` (default `dev`).
- Checks out ref; asserts the most-recent CI check-run named
  `"Full check (make check)"` on that SHA is `success`; aborts if not.
- Fast-forward `main` from `dev`.
- Reads `VERSION`; tags `v<VERSION>` iff tag doesn't already exist.
- Pushes `main` + tag.

**D. VERSION + CHANGELOG + verify-* scripts**
- `VERSION` file at repo root: `0.1.0` (seed for HC-001+HC-002 together).
- `CHANGELOG.md` at repo root, Keep-a-Changelog format. Initial entry
  `## [v0.1.0]` with a summary of HC-001 (bootstrap + layout) and HC-002
  (CI + release pipeline).
- `scripts/verify-version-bumped.sh`: compares working `VERSION` to
  `git show origin/main:VERSION` (if origin/main exists). Fails if equal
  unless `HEALTHY_SKIP_VERSION_BUMP=1`.
- `scripts/verify-changelog.sh`: asserts `CHANGELOG.md` contains a heading
  `## [v<current VERSION>]`. Fails if absent unless `HEALTHY_SKIP_CHANGELOG=1`.
- Makefile adds `verify-version-bumped`, `verify-changelog` targets.

**E. Branch model documentation**
- `memory/workflow.md` updated: `main` is CI-promoted-only; `dev` is the
  integration branch; feature branches target `dev` via PR.
- `CLAUDE.md` git-workflow section updated.
- Rollout step (post-merge): operator creates `dev` from `main` and pushes it.

No change to `hc.zig`. No change to the CLI flag set / URL schemes / exit codes
/ size table.

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Keep `core.hooksPath=.githooks` + custom hook scripts (no pre-commit framework) | pre-commit framework is already installed via `make tools` and already consumed by the user; keeping both leads to the reported conflict. Pick one; pre-commit is more capable (multi-stage, per-file filters, versioned external hooks). |
| Keep `.githooks/` as the layout and bypass pre-commit | Loses shellcheck-pinned-version, memory-size inline check, future external repos. User asked for beaconry-style — beaconry is pre-commit-only. |
| Put all gates in CI only (skip local pre-push) | User explicitly asked pre-push to cover the majority of issues. CI-only means PRs sit red for 3 min before you know you forgot to bump VERSION. Pre-push is the instant signal. |
| Single CI job for everything | Blows up feature-branch push latency to 3 min for every typo. Stratification matches beaconry's shape and the DD-TGD principle: gate at the right scope for the right diff. |
| Create `dev` branch inside this commit | The commit itself needs a base; if we introduced `dev` mid-commit, the branch model would reference a `dev` that only exists post-push. Cleaner to create `dev` as a one-liner in the plan's rollout section after HC-002 merges to `main`. |
| Use GitHub's merge-queue / rebase-merge | Both lose the PR boundary in `git log`. Beaconry uses merge-commits; match that. |

## Breaking changes

- [x] Yes — hook install behaviour:
  - `make install-hooks` no longer sets `core.hooksPath`; it unsets it.
  - `.githooks/commit-msg` moved to `scripts/check-commit-msg.sh`.
  - Anyone who ran the HC-001 `install-hooks` and now re-runs it will get a
    clean install (the `--unset-all` is idempotent).
- [x] Yes — PR target branch for all future stories:
  - `feat/*`, `fix/*`, etc. PRs target `dev` once `dev` exists.
  - HC-002 itself PRs to `main` (last direct PR to `main`).

## Rollout

- [x] README updated — add CHANGELOG / VERSION / dev-main flow pointers
- [x] `memory/workflow.md` — branch flow rewritten
- [x] `CLAUDE.md` — git-workflow section updated
- [x] `docs/CAPABILITIES.md` — 5 new CAPs
- [x] HC-001 acceptance test updated for the `.githooks/` → `scripts/` path move
- [ ] **Post-merge manual step**: `git branch dev main && git push -u origin dev`
  and (optionally) set `dev` as the default integration target in GitHub UI.

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (story §8) | Test pointer | Status |
|---|---|---|
| Hook install works without `core.hooksPath` conflict | `test/acceptance/test_HC_002_ci-dev-main-promotion.sh` (Scenario 1 block) | ✅ |
| Workflow files are present + parse | same file, Scenario 2 block | ✅ |
| VERSION semver + CHANGELOG entry | same file, Scenario 3 block | ✅ |
| verify-version-bumped fails on unchanged VERSION | same file, Scenario 4 block | ✅ |
| verify-changelog fails on missing entry | same file, Scenario 5 block | ✅ |
| Commit-msg gate rejects garbage, accepts well-formed | same file, Scenario 6 block | ✅ |
| Pre-push hook list covers the majority of issues | same file, Scenario 7 block | ✅ |

### Lens 2 — Behaviour symmetry

| CAP delivered | ≥ 1 test? | Status |
|---|---|---|
| `workflow.ci-stratified` | ✅ (Scenario 2 asserts the three job names + `workflow_dispatch`) | ✅ |
| `workflow.release-promotion` | ✅ (Scenario 2 asserts release.yml structure) | ✅ |
| `workflow.version-sync-gate` | ✅ (Scenarios 3+4+5) | ✅ |
| `workflow.pre-push-gate` | ✅ (Scenario 7) | ✅ |
| `workflow.hooks-via-pre-commit` | ✅ (Scenario 1) | ✅ |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys its own §7 (out-of-scope) — no hc.zig change, no publishing | ✅ |
| New CAPs listed in §9 all appear in `docs/CAPABILITIES.md` | ✅ |
| HC-001 acceptance test still green after commit-msg path move | ✅ |
| `make check` green on this branch | ✅ |
| `make verify-traceability` green (now 28 CAPs) | ✅ |
| CHANGELOG has an entry for `VERSION` | ✅ |
| Size budget unaffected (no hc.zig touch) | ✅ |

## Post-merge notes

Second DD-TGD story — first to run on a feat branch (vs HC-001 which landed
directly on main). The HC-002 acceptance test caught one stale `.githooks/`
reference in `make help`'s text that would otherwise have slipped by until
somebody read it — confirming the "scenario-7 negative assertion" pattern
(grep absence of old references) was worth the extra line.

One thing the Shipping evidence table didn't quite capture: the
verify-version-bumped script has three branches (bypass / main-branch skip /
no-upstream-VERSION skip / real check), and only two of those are meaningfully
testable from inside HC-002 (bypass + real-check-passes). The "real-check-fails"
path only becomes exercisable once origin/main carries a VERSION file — i.e.
from HC-003 onward. Scenario 4's conditional block handles that.

Open follow-ups (own stories):
- Branch protection on main (after HC-003 confirms the flow is stable)
- hc --version CLI flag (would make VERSION observable at runtime, not just in git)
