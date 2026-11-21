# shepherd-poc scripts — Release 0

This directory holds the four scripts the `shepherd-poc` workflow runs. See [`docs/stories/HC-008-shepherd-poc.md`](../../docs/stories/HC-008-shepherd-poc.md) for the story, and [`bboortz/shepherd SH-004`](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-004-r0-poc-on-healthy.md) for the product design.

## Files

| Script | Role |
|---|---|
| `install-trivy.sh` | Download Trivy v0.69.3 and verify the sigstore bundle with `cosign`. No `aquasecurity/trivy-action` wrapper — CVE-2026-33634 proved that class of attack is live. |
| `agent-call.sh` | `curl` to the Anthropic Messages API with the Trivy findings. Hard rules in the prompt: scope level 1 (deps + lockfiles only), diff ≤ 50 lines, do not touch `.github/workflows/`, `.shepherd.yml`, `scripts/release.sh`, `VERSION`, `*.env`. Returns `NO_FIX_POSSIBLE` or a unified diff. |
| `validate.sh` | Gate the candidate diff against the blocklist + a 50-line cap. Exits 2 on any violation. The *only* line of defence in R0, so keep it narrow and auditable. |
| `open-pr.sh` | `git apply --check`, create branch, commit, push, `gh pr create` against `dev` with labels `shepherd-poc` and `needs-review`. |

## Operator setup (one-time)

Before the first scheduled run:

1. Set `ANTHROPIC_API_KEY` in this repo's Actions secrets.
   - `gh secret set ANTHROPIC_API_KEY -R bboortz/healthy`
2. Trigger `workflow_dispatch` manually to verify. The first run should be either "No findings" or a reviewable PR.

## R0 sandbox gap (explicit)

R0 runs the agent on a standard GitHub-hosted runner with normal egress. The protective envelope is:

- The agent step only sees `ANTHROPIC_API_KEY` in its `env:` — no git credentials, no deploy keys.
- The agent's output is a diff, not direct writes.
- `validate.sh` is between the agent and the PR.

R1 adds a container-level or namespace-level network lockdown so the agent can only reach `api.anthropic.com`. See [DESIGN §12](https://github.com/bboortz/shepherd/blob/main/docs/DESIGN.md) for the target invariant.
