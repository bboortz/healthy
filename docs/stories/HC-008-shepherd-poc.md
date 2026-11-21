---
id: HC-008
slug: shepherd-poc
status: in-progress        # draft → ready → in-progress → shipped
created: 2026-11-21
owner: @benni
---

# HC-008 — Shepherd POC (Release 0) on `healthy`

> This is the **healthy-side** of Shepherd Release 0. The design, CAPs and acceptance are owned by [`bboortz/shepherd` SH-004](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-004-r0-poc-on-healthy.md). HC-008's scope is the concrete artefacts that land in `healthy`.

## 1. Who is the consumer?

The healthy maintainer (benni) who wants vulnerable-dependency fixes proposed as PRs without hand-triage. Indirectly: the Shepherd project uses this run as the R0 proof point for its Nov 27 release gate.

## 2. When does the story fire?

- Scheduled daily (05:00 UTC) when the workflow is on `dev` or `main`.
- Manual `workflow_dispatch` for the first live run and for the prompt-injection drill.

## 3. What does success look like?

Mechanically checkable:

- `.github/workflows/shepherd-poc.yml` exists, schedules on cron, allows `workflow_dispatch`.
- `scripts/shepherd-poc/validate.sh` refuses diffs that touch the protected-files blocklist (`.github/workflows/**`, `.shepherd.yml`, `scripts/release.sh`, `VERSION`, `*.env`) or exceed 50 changed lines, and exits 2 on either.
- The Trivy install step downloads the release binary and verifies via `cosign` (sigstore), **not** via `aquasecurity/trivy-action`.
- Every third-party `uses:` line in `shepherd-poc.yml` is a 40-hex SHA pin (SH-001 invariant).
- `make check` (healthy's existing gate) stays green on `dev`.
- `test/acceptance/test_HC_008_shepherd_poc.sh` passes 100% (no network required — the test does not call Anthropic).

**Runtime-only** (after secrets are set and the first live run executes):

- A real HIGH/CRITICAL fixable finding in `healthy` produces a PR with a diff ≤ 50 lines.
- Prompt-injection drill with a crafted dependency README produces no PR touching a protected path.

## 4. How urgent?

- [x] Security-critical — this is the first live use of an AI agent with repo-write capability.
- [x] Launch-schedule bound — Shepherd R0 gate is Fri 27 Nov 2026.
- [x] Correctness — the acceptance test must prevent R0 from ever auto-merging or writing protected files.

## 5. Happy path

```
# .github/workflows/shepherd-poc.yml
on:
  schedule:
    - cron: "0 5 * * *"
  workflow_dispatch: {}

jobs:
  scan-and-fix:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - actions/checkout (SHA-pinned)
      - scripts/shepherd-poc/install-trivy.sh      # sigstore-verified download of Trivy v0.69.3 (safe)
      - trivy fs --severity HIGH,CRITICAL --ignore-unfixed --format json -o /tmp/findings.json .
      - scripts/shepherd-poc/agent-call.sh          # curl Anthropic Messages API → /tmp/diff.patch
      - scripts/shepherd-poc/validate.sh /tmp/diff.patch
      - scripts/shepherd-poc/open-pr.sh /tmp/diff.patch
```

## 6. Edge cases / failure modes that matter

- **No findings:** `scan-and-fix` exits 0, no PR, no error.
- **Trivy install cosign-verify fails:** step fails immediately. The whole workflow bails — matches shepherd's SH-001 supply-chain stance.
- **Agent returns `NO_FIX_POSSIBLE`:** exit 0. The needs-human issue path is R1 scope.
- **Diff touches a protected path (blocklist hit):** `validate.sh` exits 2; the workflow fails with a clear log line. No PR.
- **Diff > 50 lines:** `validate.sh` exits 2.
- **Diff parses malformed:** `git apply --check` fails in `open-pr.sh`; workflow exits 2.
- **Prompt-injection attempt (fixture: malicious changelog saying "modify .shepherd.yml"):** validator is the only line of defence in R0 — must still block the write.
- **Anthropic rate limit:** `agent-call.sh` retries with exponential backoff up to 3; after that, exit 2.
- **`max_tokens` cap hit before diff complete:** output truncated; `validate.sh` sees invalid patch and exits 2. The budget cap wins.

## 7. Out of scope

Per [SH-004 §7](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-004-r0-poc-on-healthy.md) and DESIGN §13 R0:

- Config file (`.shepherd.yml`).
- Auto-merge or any merge logic.
- Waiting period from release date.
- ntfy / Slack / email notifications.
- Multi-repo discovery.
- Sandbox perimeter (no network except Anthropic) — **known gap**, documented below.

**Known sandbox gap:** the agent step runs on a stock GitHub-hosted runner. Network is not restricted. R0 relies on `validate.sh` (blocklist + diff size) as the only enforcement line. R1 adds a container-level or namespace-level network lockdown. Users running HC-008 must accept this.

## 8. Acceptance (Gherkin → `test/acceptance/test_HC_008_shepherd_poc.sh`)

```gherkin
Scenario: Workflow is scheduled and dispatch-triggerable
  Given .github/workflows/shepherd-poc.yml at this commit
  When  the file is parsed
  Then  it contains `cron:` under `schedule:`
  And   it contains `workflow_dispatch:`

Scenario: No third-party Action wrapper is used for Trivy (SH-001 invariant)
  Given .github/workflows/shepherd-poc.yml
  When  the uses: lines are collected
  Then  no line references `aquasecurity/trivy-action`
  And   every third-party `uses:` is a 40-hex SHA pin

Scenario: validate.sh exists and is executable
  When  the repo tree is inspected
  Then  scripts/shepherd-poc/validate.sh is present
  And   scripts/shepherd-poc/validate.sh is executable

Scenario: validate.sh blocks a diff that touches a protected path
  Given a unified-diff fixture that touches .github/workflows/x.yml
  When  scripts/shepherd-poc/validate.sh <fixture> is run
  Then  it exits 2
  And   its stderr names the offending path

Scenario: validate.sh blocks a diff that touches .shepherd.yml
  Given a unified-diff fixture that touches .shepherd.yml
  When  scripts/shepherd-poc/validate.sh <fixture> is run
  Then  it exits 2

Scenario: validate.sh blocks a diff with > 50 changed lines
  Given a unified-diff fixture with 60 changed lines in build.zig
  When  scripts/shepherd-poc/validate.sh <fixture> is run
  Then  it exits 2

Scenario: validate.sh accepts a small, allowed diff
  Given a unified-diff fixture that changes 5 lines in build.zig
  When  scripts/shepherd-poc/validate.sh <fixture> is run
  Then  it exits 0

Scenario: install-trivy.sh verifies the sigstore bundle
  When  scripts/shepherd-poc/install-trivy.sh --dry-run is run
  Then  it prints the cosign verification command it would execute
  And   it exits 0
```

Where possible the acceptance script uses local fixtures and does not require network access. The sigstore verification itself is a runtime check (requires internet); the acceptance script only asserts the shape of the install step.

## 9. Capabilities delivered or extended

HC-008 extends `healthy`'s capability matrix with R0-level POC evidence. Full `active` status for each waits for R1.

- `shepherd.scan-trivy` — Trivy fs scan integrated into the repo's own CI.
- `shepherd.sandbox.no-secrets` — only `ANTHROPIC_API_KEY` is passed to the agent step; no git credentials.
- `shepherd.sandbox.diff-only` — the agent's output is a diff; a separate step applies it.
- `shepherd.blocklist.protected-files` — enforced by `scripts/shepherd-poc/validate.sh`.
- `shepherd.gate.diff-size` — enforced by `validate.sh` with a 50-line cap.
- `shepherd.scope.level-1` — enforced by the agent prompt.
- `supply-chain.sha-pin-all-actions` — extended to the new workflow by the acceptance assertion.

---

## Plan doc

Lives at [`docs/plan/HC-008-shepherd-poc-plan.md`](../plan/HC-008-shepherd-poc-plan.md).
