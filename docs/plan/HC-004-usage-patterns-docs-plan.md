---
id: HC-004
slug: usage-patterns-docs
story: docs/stories/HC-004-usage-patterns-docs.md
branch: feat/HC-004-usage-patterns-docs
status: shipped
shipped: 2026-11-08
---

# HC-004 plan — Usage-patterns docs

**Story:** [HC-004](../stories/HC-004-usage-patterns-docs.md)

## Design delta

Single file-of-interest change: `README.md` grows a new section titled
**"Usage patterns"**. The existing short "Docker Compose" subsection (one
yaml block) folds into it. Three new subsections + one migration table.

```
README.md before:
  # healthy
  …
  ## Build
  ## Docker Compose     ← one yaml block, 7 lines
  ## Test
  ## Notes and limitations

README.md after:
  # healthy
  …
  ## Build
  ## Usage patterns     ← new, ~80 lines total
    ### Docker (Dockerfile HEALTHCHECK + compose)
    ### Kubernetes (startup + readiness + liveness)
    ### Ansible (smoke task, command module)
    ### Migrating from urllib / curl / wget / nc
  ## Test
  ## Notes and limitations
```

**Decisions**:

- **Exec form only** for all orchestrators. `CMD`, not `CMD-SHELL`.
  `command:`, not `shell:`. `exec:`, not `httpGet:`. This is the only shape
  that works in a `FROM scratch` image and keeps `hc`'s no-shell invariant
  readable in the examples.
- **Both `-t 1` and `-t 5` are shown.** Evidence base: hetzner-staging
  measurements from 2026-11-08 (240 iterations across 4 services, loopback;
  p99 3–5 ms steady-state, max 18 ms cold-start). The startup-vs-steady
  split matches what Kubernetes `startupProbe` is literally for, and what
  Docker 25+'s `start_interval` enables for compose.
- **Migration table is concrete, not abstract.** Each row maps a literal
  string that exists in `homelab/docker/*/docker-compose.yml` today to the
  `hc` replacement. Operators can grep-replace.
- **No link to homelab.** The healthy repo is public-contract-stable;
  linking to a sibling repo bakes in a coupling we don't need. Patterns
  speak for themselves.

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Separate `docs/USAGE.md` instead of growing README | README is the first thing a reader sees. Operators don't expect to click through to find integration patterns for a 400 KB binary. One-file README is the right size here. |
| Add a `man hc(1)` page | Non-trivial maintenance (new tooling in CI, pandoc, packaging). Markdown in README is zero overhead. Revisit if the project grows a distribution channel. |
| Show `httpGet` probes for Kubernetes | `httpGet` bypasses `hc` entirely — the whole point is to use our binary for CA pinning / body match / status range. Must be `exec:`. |
| Include benchmark data inline | The 240-iteration table lives in the prior conversation context but putting measurement data in the README dates it. Reference the methodology, keep numbers in `docs/plan/IDEAS.md` if captured there. |
| Document `shell:` form of Ansible task | Breaks the "no shell dependency" story of `hc`. Doesn't match homelab's existing `command:` convention for binary-driven smoke. Omit. |
| Add a "theory of healthchecks" section | README is a reference, not a teaching document. The "why `-t 1` vs `-t 5`" explanation goes in a one-line note; deep rationale lives in `memory/project.md`. |

## Breaking changes

- [ ] No. README section reorganizes but no public contract changes. The
  old "Docker Compose" yaml block carries forward as a sub-example inside
  the new "Docker" subsection. All existing copy-pasted snippets from the
  old section remain valid.

## Rollout

- [x] README.md — new "Usage patterns" section (replacing the old short
  "Docker Compose" one-block section)
- [x] `test/acceptance/test_HC_004_usage-patterns-docs.sh` — grep-based
  content assertions
- [x] `docs/CAPABILITIES.md` — `docs.integration-patterns` CAP
- [x] `docs/stories/INDEX.md` — HC-004 row
- [x] `CHANGELOG.md` — `### Added (HC-004)` entry under v0.1.0
- [ ] **Post-merge**: optional downstream task (homelab repo): migrate the
  6 `urllib.request.urlopen` compose files to `/hc`. Not blocking; filed
  as `homelab-TBD` in homelab's backlog, not tracked here.

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (story §8) | Test pointer | Status |
|---|---|---|
| Usage patterns section + 3 env subsections | `test/acceptance/test_HC_004_usage-patterns-docs.sh` (Scenario 1) | ✅ |
| Docker patterns cover HEALTHCHECK + compose + startup/steady | same file (Scenario 2) | ✅ |
| Kubernetes snippet shows the three-probe pattern | same file (Scenario 3) | ✅ |
| Ansible snippet matches homelab's retry pattern | same file (Scenario 4) | ✅ |
| Migration table covers urllib / curl / wget / nc | same file (Scenario 5) | ✅ |

### Lens 2 — Behaviour symmetry

| CAP delivered | ≥ 1 test? | Status |
|---|---|---|
| `docs.integration-patterns` | ✅ (acceptance test greps README for every required substring) | ✅ |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys its own §7 (out-of-scope) — no code change, no default change, no man page | ✅ |
| New CAP in §9 is in `docs/CAPABILITIES.md` | ✅ |
| `make check` green on this branch | ✅ |
| `make verify-traceability` green (31 CAPs) | ✅ |
| Size budget untouched (docs-only story) | ✅ |
| Migration table maps to literal strings in homelab (grep-verified via `grep -rhE 'python3.*urlopen\|curl -sf\|wget -qO-\|nc -z' ~/git/homelab/docker/`) | ✅ |

## Post-merge notes

First docs-only HC story; proves the DD-TGD motion holds for pure
documentation deltas without becoming ceremony. The acceptance-test
pattern — grep for required substrings, scoped to a subsection via `awk`
range — is the right shape for doc coverage: catches silent drift (section
removed, snippet rewritten in the wrong direction) without breaking on
cosmetic edits.

Worth remembering: the acceptance test caught my own false-positive during
development (the Ansible section says "not `shell:`" in prose; the naïve
`grep shell:` matched that). Tightening to `^\s+shell:` (YAML-key form)
fixed it. When writing grep-based doc tests, anchor on the structural form
you actually care about — flag words in prose are noise.

Open follow-ups (own stories if adopted):
- HC-005 candidate: migrate homelab's 6 `urllib.request.urlopen` compose
  files to `/hc`. Lives in the homelab repo's backlog; healthy's job is
  just to have made the pattern obvious.
- Man page (`man hc(1)`) — generated from README via pandoc. Optional;
  only worth doing if the project grows a distribution channel (apt / dnf
  / brew) that expects one.
