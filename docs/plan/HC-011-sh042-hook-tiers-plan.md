---
id: HC-011
slug: sh042-hook-tiers
story: docs/stories/HC-011-sh042-hook-tiers.md
branch: feat/SH-042-hook-tiers
status: in-progress
---

# HC-011 plan — Adopt shepherd hook-commit + hook-push fleet tiers

**Story:** [HC-011](../stories/HC-011-sh042-hook-tiers.md)

## Design delta

Append a new Makefile section after the `ci-nightly` block:

```make
COMMIT_STEPS ?= zig-fmt shell-lint verify-traceability
PUSH_STEPS   ?= build test verify-version-bumped verify-changelog

.PHONY: hook-commit hook-push
hook-commit: $(COMMIT_STEPS)
hook-push:   $(PUSH_STEPS)
```

- `COMMIT_STEPS` and `PUSH_STEPS` are `?=` so hooks can override from the env without editing the Makefile.
- No existing target is renamed, moved, or recipe-mutated.
- Pattern mirrors shepherd's `/home/benni/git/shepherd/Makefile` (PR #51, commit 20d8f88).

Mapping (per v3 Layer 3, `shepherd/docs/plan/IDEAS-dev-workflow-contract-v3.md`):

| Stage | Native steps |
|---|---|
| hook-commit (~15 s) | `zig-fmt` `shell-lint` `verify-traceability` |
| hook-push (~2 min) | `build` `test` `verify-version-bumped` `verify-changelog` |

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Rename `zig-fmt` → `fmt-check`, `shell-lint` → `lint-shell` | SH-042 forbids step renames; wrappers must adapt to native names. |
| Move `verify-traceability` to push stage | It's fast (<1 s) and belongs with the per-commit docs gate. |
| Add install-hook wiring in the same PR | Out of scope; this is shape-only. Follow-up story owns the `pre-commit` config. |

## Breaking changes

- [ ] Yes
- [x] No — strictly additive.

## Rollout

- [ ] README updated (if public contract moved) — n/a, Makefile-only.
- [ ] `memory/project.md` invariants updated — n/a.
- [ ] `memory/zig-pitfalls.md` entry added — n/a.
- [ ] Downstream notice sent — n/a.

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (from story §8) | Test pointer | Status |
|---|---|---|
| hook-commit + hook-push are declared .PHONY | `test/acceptance/test_HC_011_hook_tiers.sh:22` | ✅ |
| hook-commit dry-run invokes the commit steps | `test/acceptance/test_HC_011_hook_tiers.sh:33` | ✅ |
| hook-push dry-run invokes the push steps | `test/acceptance/test_HC_011_hook_tiers.sh:38` | ✅ |
| existing step-level targets unchanged | `git diff --stat Makefile` on step recipes | ✅ |

### Lens 2 — Behaviour symmetry

| CAP delivered | ≥1 test? | Exit-code paths tested (0/1/2)? | Status |
|---|---|---|---|
| `shepherd.hook-commit` | yes | dry-run + grep (rc 0); failure path covered by the depended-on step targets | ✅ |
| `shepherd.hook-push` | yes | dry-run + grep (rc 0); failure path covered by the depended-on step targets | ✅ |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys its own §7 (out-of-scope) — no scope creep | ✅ |
| New CAPs listed in §9 all appear in `docs/CAPABILITIES.md` | ✅ |
| If `TLS=0` path touched: n/a | n/a |
| If cross-target path touched: n/a | n/a |
| `make verify-traceability` green | ✅ |
| Size budget within ±5% of README table | n/a |

## Post-merge notes

<Filled after merge.>
