---
id: HC-008
slug: shepherd-poc
story: docs/stories/HC-008-shepherd-poc.md
branch: feat/HC-008-shepherd-poc
status: in-progress
---

# HC-008 plan — Shepherd POC (Release 0) on `healthy`

**Story:** [HC-008](../stories/HC-008-shepherd-poc.md) · **Companion:** [bboortz/shepherd SH-004](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-004-r0-poc-on-healthy.md)

## Design delta

New workflow and a small scripts directory. No touch to `hc.zig`, `build.sh`, or any existing invariant.

**Files added**

- `.github/workflows/shepherd-poc.yml` — cron (05:00 UTC) + `workflow_dispatch`. Six steps: checkout, install Trivy (sigstore-verified), scan, agent call, validate, open PR.
- `scripts/shepherd-poc/install-trivy.sh` — downloads Trivy v0.69.3 (last known-safe pre-TeamPCP binary per GHSA-69fq-xp46-6x23) and verifies with `cosign verify-blob`. No `aquasecurity/trivy-action`.
- `scripts/shepherd-poc/agent-call.sh` — `curl` to `https://api.anthropic.com/v1/messages` with the findings JSON and a tight prompt. Writes `/tmp/diff.patch`. Hard-coded: `max_tokens=4096` (approximates the €1/run cap), retries up to 3, scope-level-1 wording.
- `scripts/shepherd-poc/validate.sh` — reads a unified diff on `argv[1]`. Blocklist: `.github/workflows/**`, `.shepherd.yml`, `scripts/release.sh`, `VERSION`, `*.env`. Size cap: 50 changed lines (`+`/`-` lines, excluding `+++`/`---`). Exits 0 on accept, 2 on block.
- `scripts/shepherd-poc/open-pr.sh` — `git apply --check`, branch `shepherd-poc/<iso-timestamp>`, commit, push, `gh pr create` against `dev` with labels `shepherd-poc,needs-review`.
- `test/acceptance/test_HC_008_shepherd_poc.sh` — 8 Gherkin scenarios as shell assertions. Uses `test/acceptance/fixtures/HC_008_*` for diff fixtures. No network.
- `test/acceptance/fixtures/HC_008_blocked_workflow.patch` — a diff touching `.github/workflows/x.yml`.
- `test/acceptance/fixtures/HC_008_blocked_shepherd_yml.patch` — a diff touching `.shepherd.yml`.
- `test/acceptance/fixtures/HC_008_oversize.patch` — a diff with 60 `+`/`-` lines.
- `test/acceptance/fixtures/HC_008_ok_small.patch` — a 5-line diff against `build.zig`.

**Files modified**

- `docs/stories/INDEX.md` — HC-008 row.
- `docs/CAPABILITIES.md` — new `shepherd.*` rows (in-progress at R0 level).
- `Makefile` — `test-acceptance` already picks up `test_HC_*.sh` via glob (no change needed); confirm during test.
- `README.md` — optional one-liner pointing at HC-008 for anyone reading the repo.

## Alternatives rejected

| Alternative | Why not |
|---|---|
| `aquasecurity/trivy-action` | SH-001 forbids third-party-Action wrappers in the critical path. CVE-2026-33634 proved the attack class live. |
| Shell out to `claude` CLI | Wider surface than `curl` + `jq`. The CLI auto-configures and can read `$CLAUDE_CONFIG_DIR`. |
| Open the PR to `main` directly | healthy's convention: PRs target `dev`. Promotion `dev → main` runs via `release.yml`. |
| Use GitHub's `GITHUB_TOKEN` for agent step | R0 principle: no secrets of its own in the agent step. Only `ANTHROPIC_API_KEY` is passed to `agent-call.sh`. `open-pr.sh` is a separate, trusted step with `GITHUB_TOKEN`. |
| Install Trivy latest | `v0.69.3` is the last version protected by GitHub immutable releases pre-TeamPCP; also the sigstore bundle exists. The `trivy-action` advisory explicitly names it. |
| Run the agent step in a container with restricted network | R0 scope-note: sandbox perimeter is R1 work. R0 approximates with blocklist + diff size. |

## Breaking changes

- [ ] No — strictly additive.
- A new secret is required: `ANTHROPIC_API_KEY`. Documented in the PR body and in `scripts/shepherd-poc/README.md`.

## Rollout

- [ ] `make check` green with the new files (no regression on existing HC-NNN acceptance)
- [ ] Acceptance test `test_HC_008_shepherd_poc.sh` added and green
- [ ] `docs/CAPABILITIES.md` updated
- [ ] `docs/stories/INDEX.md` updated
- [ ] PR body calls out the new `ANTHROPIC_API_KEY` secret + the sandbox gap
- [ ] After merge: operator sets `ANTHROPIC_API_KEY` in healthy's repo secrets
- [ ] After merge: operator runs `workflow_dispatch` manually; observes a clean "no findings" or a first real PR

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (from story §8) | Test pointer | Status |
|---|---|---|
| Workflow is scheduled and dispatch-triggerable | `test_HC_008_shepherd_poc.sh` | pending |
| No third-party Action wrapper for Trivy | `test_HC_008_shepherd_poc.sh` | pending |
| validate.sh exists and is executable | `test_HC_008_shepherd_poc.sh` | pending |
| validate.sh blocks `.github/workflows/**` | `test_HC_008_shepherd_poc.sh` + fixture | pending |
| validate.sh blocks `.shepherd.yml` | `test_HC_008_shepherd_poc.sh` + fixture | pending |
| validate.sh blocks oversize diff | `test_HC_008_shepherd_poc.sh` + fixture | pending |
| validate.sh accepts a small allowed diff | `test_HC_008_shepherd_poc.sh` + fixture | pending |
| install-trivy.sh --dry-run prints the cosign command | `test_HC_008_shepherd_poc.sh` | pending |

### Lens 2 — CAP evidence

| CAP | ≥1 test? | Status |
|---|---|---|
| `shepherd.scan-trivy` | workflow file assertion | pending |
| `shepherd.sandbox.no-secrets` | `env:` block audit | pending |
| `shepherd.sandbox.diff-only` | step-ordering assertion | pending |
| `shepherd.blocklist.protected-files` | validate.sh + 2 fixtures | pending |
| `shepherd.gate.diff-size` | validate.sh + fixture | pending |
| `shepherd.scope.level-1` | prompt text assertion | pending |
| `supply-chain.sha-pin-all-actions` | 40-hex regex over uses: lines | pending |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys §7 (no R1 features) | pending |
| New CAPs in §9 all appear in `docs/CAPABILITIES.md` | pending |
| `make check` green | pending |
| Sandbox gap honestly documented in the PR body | pending |
| No `aquasecurity/trivy-action` anywhere | pending |

## Post-merge notes

<To fill after the PR merges and the operator triggers the first live run.>
