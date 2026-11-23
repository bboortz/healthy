---
id: HC-011
slug: sh042-hook-tiers
status: ready
created: 2026-11-23
---

# HC-011 — Adopt shepherd hook-commit + hook-push fleet tiers

Umbrella is in shepherd: [SH-042 hook-commit + hook-push fleet tiers](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-042-hook-tiers.md) under the [SH-014 umbrella](https://github.com/bboortz/shepherd/pull/23).

Shepherd's SH-042 introduces two canonical fleet-tier Makefile wrappers so every managed repo exposes the same hook entry points regardless of its native step names. Healthy keeps its NATIVE step targets inside `COMMIT_STEPS` / `PUSH_STEPS` variables; the wrappers are purely additive.

## 9 canonical answers

1. **Who** — shepherd's hook contract (future SH-043); healthy contributors wiring `pre-commit` / `pre-push` hooks.
2. **When** — once, as a Makefile append.
3. **What success looks like** — `make -n hook-commit` and `make -n hook-push` resolve to real work; the native step targets (`zig-fmt`, `shell-lint`, `verify-traceability`, `build`, `test`, `verify-version-bumped`, `verify-changelog`) are byte-identical to pre-PR.
4. **Urgency** — correctness + fleet contract alignment (uniform hook shape across the fleet).
5. **Happy path** — merge PR → future shepherd-side hook verifier recognises healthy as contract-conformant.
6. **Edge cases** — none; purely additive naming.
7. **Out of scope** — renaming any existing step-level target; moving any step between stages; installing new git hooks.
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended**:
   - `shepherd.hook-commit` — healthy's Makefile exposes the `hook-commit` fleet-tier wrapper that depends on repo-native `COMMIT_STEPS` (~15s commit-stage gate).
   - `shepherd.hook-push` — healthy's Makefile exposes the `hook-push` fleet-tier wrapper that depends on repo-native `PUSH_STEPS` (~2m push-stage gate).

## Gherkin acceptance

```gherkin
Scenario: hook-commit + hook-push are declared .PHONY
  Given the healthy repo at HEAD
  Then  Makefile declares `hook-commit` and `hook-push` as .PHONY

Scenario: hook-commit dry-run invokes the commit steps
  Given the healthy repo at HEAD
  When  `make -n hook-commit` runs
  Then  the dry-run output references `zig fmt --check`
  And   the dry-run output references `shellcheck`
  And   the dry-run output references `scripts/verify-traceability.sh`

Scenario: hook-push dry-run invokes the push steps
  Given the healthy repo at HEAD
  When  `make -n hook-push` runs
  Then  the dry-run output references `scripts/build.sh`
  And   the dry-run output references `./test/run.sh`
  And   the dry-run output references `scripts/verify-version-bumped.sh`
  And   the dry-run output references `scripts/verify-changelog.sh`

Scenario: existing step-level targets unchanged
  Given the healthy repo at HEAD
  Then  zig-fmt / shell-lint / verify-traceability / build / test /
        verify-version-bumped / verify-changelog recipes byte-identical to pre-PR
```
