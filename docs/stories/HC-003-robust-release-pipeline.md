---
id: HC-003
slug: robust-release-pipeline
status: shipped
created: 2026-11-08
shipped: 2026-11-08
owner: @benni
---

# HC-003 — Robust release pipeline (skipped-filter + fixture-tested gate)

## 1. Who is the consumer?

**The maintainer.** The operator who clicks "Run workflow" on `release.yml` and
expects it to Just Work when CI was green. HC-002 established the shape; HC-003
makes it survive real-world check-run topologies.

## 2. When does the story fire?

Every time `release.yml` is dispatched. The check-runs API returns **every**
`Full check (make check)` entry that ever existed on the target SHA — PR-level,
dev-push, manual main-push, re-runs. The gate must pick the right one.

## 3. What does success look like?

Observable:

- `release.yml` dispatched after `dev` + `main` both point at the same SHA
  (dev-merged + manual-promoted — exactly the state this repo is in now)
  **succeeds** at the "Assert CI is green" step. Previously fails with
  `status=skipped` because the latest check-run (from the main push) is a skip,
  masking the earlier success (from the dev push).
- `release.yml` dispatched after a re-run where the newer `Full check (make
  check)` **failed** correctly blocks.
- The jq query that implements this logic lives in a single file,
  `scripts/latest-ci-status.jq`, consumed by both `release.yml` and the
  acceptance test. No "keep in sync" split-brain.
- `test_HC_002`'s Scenario-4 force-fail assertion no longer breaks when run
  with HEAD at `main` (where `verify-version-bumped` short-circuits by design).

## 4. How urgent?

**Correctness.** The release pipeline is the only way to produce tagged releases
from HC-003 onward. Every release attempt currently hits one of the two bugs.
Not security-critical, but foundationally blocking the next real tag (v0.1.1+).

## 5. Happy path

```sh
# On dev — all CI green:
git push                                     # dev push → full-check CI (~2m, success)

# Operator opens the Release workflow in Actions UI → Run workflow:
#   - Use workflow from: main (default)
#   - ref: dev (default)
# Click Run.
#
# Expected: workflow succeeds. Promotes main from dev. Tags v<VERSION>.
```

## 6. Edge cases / failure modes that matter

- **Same SHA, dev push + main push (current bootstrap state)**: success + skipped
  mix. Gate must pick the success. Previously picked the latest-started (the
  skip) and incorrectly blocked.
- **Re-run of full-check after a success**: the latest non-skipped run wins.
  If the re-run failed, the gate must fail.
- **No full-check runs at all on SHA** (e.g. dev was auto-created and never
  pushed, or user force-pushed and discarded CI): no `success` and no
  `failure` — only skipped or empty. Gate must abort with "not-yet-run".
- **Multiple check-run names with the exact string `"Full check (make check)"`**:
  all of them considered; non-skipped winner picked by `started_at`.
- **test_HC_002 on `main`**: `verify-version-bumped` intentionally skips on
  `main` (main advances only via `release.yml`). The Scenario-4 force-fail
  assertion assumed a non-main branch; breaks when operator pushes to main
  locally (HC-002 bootstrap, HC-003 bootstrap, future manual bypasses). Guard.

## 7. Out of scope

- Changing `verify-version-bumped`'s branch-aware skip behaviour. The skip is
  correct; only the test's assumption is wrong.
- Changing the pre-push gate so fixes can land without a VERSION bump. That's
  a separate conversation — HC-004 territory. HC-003 continues to use
  `HEALTHY_SKIP_VERSION_BUMP=1` as the documented emergency bypass for
  CHANGELOG-only fixes to the current release.
- GitHub branch protection on `main` / `dev`. Deferred until HC-004 or later.
- Re-tagging `v0.1.0`. It stays at the bootstrap merge SHA (`ac9c2af`); HC-003
  fixes fold into `v0.1.0`'s `### Fixed` CHANGELOG section.
- Signing, SBOM, publish to registry. Out of scope for `healthy`'s current
  distribution model.

## 8. Acceptance (Gherkin → shell assertions)

```gherkin
Scenario: jq picks latest non-skipped success
  Given a Checks API payload with
    - Full check (make check) @ T1 = success
    - Full check (make check) @ T2 = skipped   (T2 > T1)
  When I run scripts/latest-ci-status.jq against the payload
  Then the output is "success"

Scenario: jq picks the latest non-skipped failure
  Given a payload with
    - Full check (make check) @ T1 = success
    - Full check (make check) @ T2 = failure   (T2 > T1)
  When I run the jq
  Then the output is "failure"

Scenario: jq reports "not-yet-run" for only-skipped
  Given a payload containing only skipped Full-check entries
  When I run the jq
  Then the output is "not-yet-run"

Scenario: jq reports "not-yet-run" for empty check_runs
  Given a payload with an empty check_runs array
  When I run the jq
  Then the output is "not-yet-run"

Scenario: release.yml and the test consume the same jq
  Then .github/workflows/release.yml references scripts/latest-ci-status.jq
  And  the acceptance test runs the same file

Scenario: test_HC_002 Scenario-4 force-fail is skipped on main
  Given HEAD is on branch "main"
  When I run test_HC_002
  Then the Scenario-4 force-fail assertion is not exercised
  And  the test still passes (verify-version-bumped's main-branch short-
       circuit is covered by a positive assertion instead)
```

## 9. Capabilities delivered or extended

- `workflow.release-check-filter` — `release.yml`'s "Assert CI is green" step picks the latest non-skipped `Full check (make check)` check-run via `scripts/latest-ci-status.jq`, correctly handling the common bootstrap topology where the same SHA fires both a dev-push success and a main-push skip.
- `workflow.release-check-testable` — the jq filter is a single file consumed by both `release.yml` and the acceptance test; four fixture JSON files under `test/acceptance/fixtures/hc-003/` cover success-after-skip, failure-after-success, only-skipped, and empty topologies.
