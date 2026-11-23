---
id: HC-012
slug: sh055-check-docs
status: ready
created: 2026-11-23
---

# HC-012 — Adopt shepherd check-docs fleet-tier wrapper

Umbrella is in shepherd: [SH-055 check-docs fleet-tier wrapper](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-055-check-docs.md) under the [SH-014 umbrella](https://github.com/bboortz/shepherd/pull/23).

Shepherd's SH-055 introduces a `check-docs` fleet-tier wrapper that every managed repo exposes. It delegates to each repo's existing docs-drift targets — purely additive, no new logic. Healthy maps `check-docs` to its three existing verify-* targets and wires it into the hook variables (`PUSH_STEPS`, `BRANCH_STEPS`).

## 9 canonical answers

1. **Who** — shepherd's fleet-wide hook contract (SH-055); healthy contributors wiring `pre-commit` / `pre-push` hooks and `ci-branch`.
2. **When** — once, as a Makefile append plus two variable-list extensions.
3. **What success looks like** — `make -n check-docs` resolves to the three existing docs-drift scripts (`verify-traceability`, `verify-version-bumped`, `verify-changelog`); `PUSH_STEPS` and `BRANCH_STEPS` both list `check-docs`; no step-level target is renamed or moved.
4. **Urgency** — correctness + fleet contract alignment (uniform docs-drift entry point across the fleet).
5. **Happy path** — merge PR → shepherd-side contract verifier recognises healthy as providing the `check-docs` entry point; a future scope-level-3 agent can propose docs-drift fixes without touching workflow YAML.
6. **Edge cases** — none; purely additive naming.
7. **Out of scope** — renaming any existing verify-* target; moving steps between stages; new docs-drift logic.
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended**:
   - `shepherd.check-docs` — healthy's Makefile exposes the `check-docs` fleet-tier wrapper that delegates to `verify-traceability`, `verify-version-bumped`, and `verify-changelog`. Added to `PUSH_STEPS` and `BRANCH_STEPS`.

## Gherkin acceptance

```gherkin
Scenario: check-docs declared .PHONY
  Given the healthy repo at HEAD
  Then  Makefile declares `check-docs` as .PHONY

Scenario: check-docs delegates to the three existing drift targets
  Given the healthy repo at HEAD
  Then  `check-docs:` names `verify-traceability` `verify-version-bumped` `verify-changelog` as prerequisites

Scenario: PUSH_STEPS and BRANCH_STEPS include check-docs
  Given the healthy repo at HEAD
  Then  `PUSH_STEPS` includes `check-docs`
  And   `BRANCH_STEPS` includes `check-docs`

Scenario: check-docs dry-run invokes the delegate chain
  Given the healthy repo at HEAD
  When  `make -n check-docs` runs
  Then  the dry-run output references `scripts/verify-traceability.sh`
  And   the dry-run output references `scripts/verify-version-bumped.sh`
  And   the dry-run output references `scripts/verify-changelog.sh`

Scenario: existing step-level targets unchanged
  Given the healthy repo at HEAD
  Then  verify-traceability / verify-version-bumped / verify-changelog recipes byte-identical to pre-PR
```
