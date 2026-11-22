---
id: HC-009
slug: sh019-contract-adoption
status: ready
created: 2026-11-22
---

# HC-009 — Adopt shepherd dev-cycle contract (become the reference implementation)

Umbrella is in shepherd: [SH-019 (fleet contract rollout)](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-019-fleet-contract-rollout.md) + [SH-025 (healthy ci-* rename / reference impl)](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-025-healthy-ci-rename.md) under the [SH-014 umbrella](https://github.com/bboortz/shepherd/pull/23).

Healthy already fits all three budgets (dev-cycle doc measurement 2026-11-22: 3.0 / 3.7 / 1.5 min). This PR adopts the shared target names so new repos onboard by copying healthy's Makefile shape. No speed work; no behaviour change.

## 9 canonical answers

1. **Who** — future repo owners onboarding to shepherd; they copy healthy as the reference.
2. **When** — once, as a Makefile append.
3. **What success looks like** — `make -n <each-contract-target>` resolves to real healthy work; existing `build` / `test` / `cross` / `lint` / `check` unchanged; `shepherd-bump --verify-contract` (SH-017) will pass.
4. **Urgency** — correctness + onboarding (becomes the quickstart's reference).
5. **Happy path** — merge PR → next shepherd-bump run passes verify-contract on healthy.
6. **Edge cases** — none; purely additive.
7. **Out of scope** — any speed work; `ci-release` body (handled by existing release workflow); any `.shepherd.yml` change (contract targets inherit from native aliases).
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended**:
   - `build.shepherd-contract` — healthy's Makefile exposes the shepherd dev-cycle contract (eight canonical targets); reference implementation of the shared shape.

## Gherkin acceptance

```gherkin
Scenario: healthy exposes all eight contract targets
  Given the healthy repo at HEAD
  Then  `make -n build` resolves to real work
  And   `make -n test` resolves to real work
  And   `make -n test-affected` resolves to real work
  And   `make -n smoke` resolves to real work
  And   `make -n release-artifacts` resolves to real work
  And   `make -n ci-branch` resolves to real work
  And   `make -n ci-patch` resolves to real work
  And   `make -n ci-release` resolves (echo)
  And   `make -n ci-nightly` resolves to real work

Scenario: existing healthy targets unchanged
  Given the healthy repo at HEAD
  Then  build / test / cross / lint / check recipes byte-identical to pre-PR
```
