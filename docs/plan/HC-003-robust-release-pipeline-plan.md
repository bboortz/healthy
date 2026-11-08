---
id: HC-003
slug: robust-release-pipeline
story: docs/stories/HC-003-robust-release-pipeline.md
branch: feat/HC-003-robust-release-pipeline
status: shipped
shipped: 2026-11-08
---

# HC-003 plan — Robust release pipeline

**Story:** [HC-003](../stories/HC-003-robust-release-pipeline.md)

## Design delta

Three small changes, all converging on "the release gate is correct and
testable."

**A. Extract the jq into `scripts/latest-ci-status.jq`.** Single file,
single source of truth. `release.yml`'s "Assert CI is green" step pipes the
Checks API JSON through `jq -r -f scripts/latest-ci-status.jq`. The acceptance
test runs the same file against fixture JSON.

```jq
[.check_runs[]
  | select(.name == "Full check (make check)" and .conclusion != "skipped")]
  | sort_by(.started_at)
  | .[-1].conclusion // "not-yet-run"
```

Difference from HC-002's inline jq:
- Adds `and .conclusion != "skipped"` to the select — excludes skips.
- Adds `// "not-yet-run"` fallback — handles the "no matching runs" case
  (empty array after filtering) without jq erroring.

**B. Fixture JSON.** Four files under `test/acceptance/fixtures/hc-003/`
mirroring the four Gherkin scenarios in §8 of the story. Each is minimal —
one or two `check_runs` entries per file, enough to exercise one path through
the jq.

**C. `test_HC_002` branch-aware guard.** Wrap the Scenario-4 force-fail block
in `if [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" != "main" ]`. On
`main`, replace with a positive assertion that `verify-version-bumped`
correctly short-circuits (exit 0 with the "on main — skipping" message).

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Fold the jq fix inline in `release.yml`, keep the duplicate in the acceptance test | Two copies always drift. The HC-002 BC-071 leak was caught because we had a dedicated verify-version-bumped script; a similar single-source extraction for the jq is the same discipline. |
| Filter by `trigger_event` / branch in the jq instead of by conclusion | Brittle — the API shape for triggers is less stable than `conclusion`. "Not skipped" is the invariant that matters semantically. |
| Delete all skipped check-runs via API before release.yml dispatch | Destructive, API-rate-limited, and tries to "fix" GitHub's correct behaviour. Our jq should adapt, not the data. |
| Make `verify-version-bumped` not skip on `main` | The skip is correct — main advances via `release.yml`, not direct pushes. Fixing the test is the right half. |
| Turn the Scenario-4 force-fail into a mock / non-subprocess assertion | The subprocess invocation is the realistic use case we want to protect against regressions (BC-071 leak taught us that). Guard, don't mock. |

## Breaking changes

- [ ] No. `release.yml`'s semantics are unchanged from the operator's view —
  dispatch Run workflow, it either promotes or aborts. The abort cases
  expand (now "not-yet-run" is an explicit output) but no operator workflow
  depends on specific failure messages.

## Rollout

- [x] Scripts: `scripts/latest-ci-status.jq` added, consumed by `release.yml`
- [x] Fixtures: `test/acceptance/fixtures/hc-003/*.json` added
- [x] Acceptance test: `test/acceptance/test_HC_003_robust-release-pipeline.sh`
- [x] `test/acceptance/test_HC_002_…` updated for branch-aware Scenario-4
- [x] CHANGELOG — new entries under `v0.1.0`'s `### Fixed (HC-003 follow-up)`
- [x] `docs/CAPABILITIES.md` — two new CAPs
- [x] `docs/stories/INDEX.md` — HC-003 row
- [ ] **Post-merge**: dispatch `release.yml` with `ref=dev` — this time the
  gate accepts the mixed-topology check-runs and promotes correctly. Still
  warns "tag v0.1.0 already exists" (expected — VERSION hasn't moved).

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (story §8) | Test pointer | Status |
|---|---|---|
| jq picks latest non-skipped success | `test/acceptance/test_HC_003_robust-release-pipeline.sh` (mix fixture) | ✅ |
| jq picks latest non-skipped failure | same file (failure-after-success fixture) | ✅ |
| jq reports "not-yet-run" for only-skipped | same file (only-skipped fixture) | ✅ |
| jq reports "not-yet-run" for empty | same file (empty fixture) | ✅ |
| release.yml + test consume the same jq | same file (greps `release.yml` for the path) | ✅ |
| test_HC_002 Scenario-4 is skipped on main | HC-002 test's updated branch guard | ✅ |

### Lens 2 — Behaviour symmetry

| CAP delivered | ≥ 1 test? | Status |
|---|---|---|
| `workflow.release-check-filter` | ✅ (4 fixture assertions) | ✅ |
| `workflow.release-check-testable` | ✅ (jq-file existence assertion + grep in release.yml) | ✅ |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys its own §7 (out-of-scope) — no verify-version-bumped behaviour change; no retag of v0.1.0 | ✅ |
| New CAPs in §9 all in `docs/CAPABILITIES.md` | ✅ |
| `make check` green on this branch | ✅ |
| `make verify-traceability` green (now 30 CAPs) | ✅ |
| jq script passes `jq --help`-level sanity (`jq -n -f scripts/latest-ci-status.jq` against each fixture) | ✅ |

## Post-merge notes

Third DD-TGD story, first to land under the full workflow (branch off `dev`,
PR to `dev`, release.yml promotes). Also the first story whose implementation
is **purely tooling** — no `hc.zig` touched, no CLI change — the capability
matrix stays honest because the two new CAPs describe genuinely observable
behaviours (operator dispatches release.yml → gate picks the right check-run →
promotion succeeds).

Design note worth remembering: extracting the jq into a file was the single
decision that made HC-003 cheap to ship. Inline jq would have required
duplicating the query between `release.yml` and the test, or shelling out to a
one-liner — both drift-prone. Fixture-driven jq testing should be the default
pattern whenever `release.yml` or `ci.yml` gets a non-trivial expression.

Open follow-ups (own stories):
- HC-004 (tentative): relax `verify-version-bumped` so CHANGELOG-only fixes to
  the current release can land without `HEALTHY_SKIP_VERSION_BUMP=1`. The
  bypass works but the pattern is becoming routine, and routine bypasses
  erode the gate.
- GitHub branch protection on `main` once HC-004 settles the push semantics.
