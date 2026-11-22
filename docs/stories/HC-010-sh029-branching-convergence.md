---
id: HC-010
slug: sh029-branching-convergence
status: ready
created: 2026-11-22
---

# HC-010 — Adopt feat/* → dev → main convergence (default branch = dev)

Umbrella is in shepherd: [SH-029 fleet branching convergence](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-029-fleet-branching-convergence.md) under the [SH-014 umbrella](https://github.com/bboortz/shepherd/pull/23).

## 9 canonical answers

1. **Who** — shepherd's `--verify-contract` (SH-017); healthy contributors who expect `gh pr create` to target `dev`.
2. **When** — once, as a Makefile + workflow PR followed by a repo-settings flip.
3. **What success looks like** — `.github/workflows/ci-release.yml` dispatches on `dev`; `make ci-release` calls `ci-release-promote`; post-merge default branch flipped.
4. **Urgency** — correctness + onboarding (uniform fleet contract shape).
5. **Happy path** — merge PR → operator flips default → smoke-dispatch ci-release.yml.
6. **Edge cases** — existing release workflow + CD pipeline untouched; co-exist with new ci-release path.
7. **Out of scope** — retiring existing release workflow; any build.sh / cross.sh changes.
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended**:
   - `shepherd.branching-convergence` — healthy adopts the fleet-wide `feat/* → dev → main` with `default=dev` (shepherd-side CAP `dev-cycle.fleet.branching-convergence`).

## Gherkin acceptance

```gherkin
Scenario: ci-release-promote mutates git only on dev
  Given the healthy repo at HEAD
  When  `make ci-release-promote` runs on a feat/* branch
  Then  exit code is 1

Scenario: ci-release.yml checks out dev on dispatch
  Given the healthy repo at HEAD
  Then  .github/workflows/ci-release.yml has `ref: dev` on the checkout step

Scenario: existing recipes unchanged
  Given the healthy repo at HEAD
  Then  build / test / cross / lint / check recipes byte-identical to pre-PR
```
