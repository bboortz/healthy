---
id: HC-012
slug: sh055-check-docs
story: docs/stories/HC-012-sh055-check-docs.md
branch: feat/SH-055-check-docs
status: in-progress
---

# HC-012 plan — Adopt shepherd check-docs fleet-tier wrapper

**Story:** [HC-012](../stories/HC-012-sh055-check-docs.md)

## Design delta

1. Add `check-docs` to the top `.PHONY` list.
2. Add target definition after the existing verify-* targets:

   ```make
   # SH-055 — fleet-wide check-docs wrapper (shepherd ref: PR #58).
   # Delegates to healthy's existing docs-drift targets; no new logic.
   check-docs: verify-traceability verify-version-bumped verify-changelog
   ```

3. Extend `PUSH_STEPS` (add `check-docs` at the front) and add a new `BRANCH_STEPS` variable:

   ```make
   PUSH_STEPS   ?= check-docs build test verify-version-bumped verify-changelog
   BRANCH_STEPS ?= lint check-docs test cross
   ```

- No existing target is renamed, moved, or recipe-mutated.
- Pattern mirrors shepherd's `/home/benni/git/shepherd/Makefile` (PR #58, SH-055).

Mapping (per v3 Layer 3, `shepherd/docs/plan/IDEAS-dev-workflow-contract-v3.md`):

| Delegate | Purpose |
|---|---|
| `verify-traceability` | story ↔ plan ↔ test ↔ CAP bidirectional links |
| `verify-version-bumped` | VERSION diffs from `origin/main:VERSION` |
| `verify-changelog` | CHANGELOG.md carries `## [v<VERSION>]` heading |

## Alternatives rejected

| Alternative | Why not |
|---|---|
| New docs-drift script inside `check-docs:` recipe | SH-055 is purely a wrapper — no new logic. |
| Keep BRANCH_STEPS absent | Fleet contract requires both `PUSH_STEPS` and `BRANCH_STEPS` to list `check-docs`. |
| Put check-docs at end of PUSH_STEPS | Front position matches shepherd's reference impl (near front, after lint-ish targets). |

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
| check-docs declared .PHONY | `test/acceptance/test_HC_012_check_docs.sh:23` | ✅ |
| check-docs delegates to the three existing drift targets | `test/acceptance/test_HC_012_check_docs.sh:30` | ✅ |
| PUSH_STEPS and BRANCH_STEPS include check-docs | `test/acceptance/test_HC_012_check_docs.sh:44` | ✅ |
| check-docs dry-run invokes the delegate chain | `test/acceptance/test_HC_012_check_docs.sh:53` | ✅ |
| existing step-level targets unchanged | `git diff --stat Makefile` on verify-* recipes | ✅ |

### Lens 2 — Behaviour symmetry

| CAP delivered | ≥1 test? | Exit-code paths tested (0/1/2)? | Status |
|---|---|---|---|
| `shepherd.check-docs` | yes | dry-run + grep (rc 0); failure path covered by the depended-on verify-* targets | ✅ |

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
