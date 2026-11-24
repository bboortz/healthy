---
id: HC-013
slug: sh056-verify-index-status
status: in-progress
created: 2026-11-24
owner: @benni
---

# HC-013 — Adopt shepherd verify-index-status script + check-docs wiring

Umbrella is in shepherd: [SH-056 verify-index-status](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-056-verify-index-status.md) under the [SH-055 check-docs wrapper](https://github.com/bboortz/shepherd/blob/main/docs/stories/SH-055-check-docs.md) story.

Shepherd's SH-056 ships `scripts/verify-index-status.sh`, a doc-staleness check that compares `docs/stories/INDEX.md` row status against each story's frontmatter status. SH-055 named this drift class in its example but did not wire it up. Healthy copies the script byte-identical from shepherd (future SH-NNN may sha256-check it) and wires it into the `check-docs` wrapper.

## 9 canonical answers

1. **Who** — shepherd's fleet-wide hook contract (SH-055 wrapper, SH-056 verifier); healthy contributors wiring `pre-commit` / `pre-push` hooks and `ci-branch`.
2. **When** — once, as a script copy + Makefile append.
3. **What success looks like** — `scripts/verify-index-status.sh` is byte-identical to shepherd's; `make -n verify-index-status` dry-runs the script; `check-docs:` depends on `verify-index-status` (so every `make check-docs` run exercises it); existing drift targets (`verify-traceability`, `verify-version-bumped`, `verify-changelog`) unchanged.
4. **Urgency** — correctness + fleet contract alignment (future SH-NNN may enforce script-identity via sha256).
5. **Happy path** — merge PR → next `check-docs` run catches any INDEX ↔ frontmatter drift locally before push.
6. **Edge cases** — INDEX absent → script exits 0 with a message (no-op guard); frontmatter missing `status:` → fail with story id; INDEX row missing for any story → fail with id.
7. **Out of scope** — renaming any existing verify-* target; changing INDEX column shape beyond this story's `| ID | Status | Slug | Title |` alignment with shepherd; new drift-class logic.
8. **How we know it's done** — see Gherkin below.
9. **Capabilities delivered or extended**:
   - `shepherd.verify-index-status` — healthy's Makefile exposes `verify-index-status` (delegates to `scripts/verify-index-status.sh`) and `check-docs` depends on it.

## Gherkin acceptance

```gherkin
Scenario: script exists and is executable
  Given the healthy repo at HEAD
  Then  scripts/verify-index-status.sh exists and is executable

Scenario: script is byte-identical to shepherd's reference
  Given the healthy repo at HEAD
  And   shepherd's reference script at scripts/verify-index-status.sh
  Then  sha256sum of both files matches

Scenario: healthy passes the verifier (dogfood)
  Given the healthy repo at HEAD
  When  scripts/verify-index-status.sh runs
  Then  exit code is 0
  And   stdout contains "ok (INDEX.md matches frontmatter for all stories)"

Scenario: Makefile declares verify-index-status and wires it into check-docs
  Given the healthy repo at HEAD
  Then  Makefile declares `verify-index-status` as .PHONY
  And   Makefile defines a `verify-index-status:` target
  And   `check-docs:` names `verify-index-status` as a prerequisite

Scenario: make -n verify-index-status resolves to the script
  Given the healthy repo at HEAD
  When  `make -n verify-index-status` runs
  Then  the dry-run output references `scripts/verify-index-status.sh`

Scenario: verifier catches INDEX row status ≠ frontmatter status
  Given the healthy repo at HEAD
  When  INDEX.md row for one story is edited to flip status to `draft`
  Then  scripts/verify-index-status.sh exits 1
  And   stdout mentions "INDEX row status='draft' but frontmatter says"

Scenario: verifier catches missing INDEX row
  Given the healthy repo at HEAD
  When  one story's INDEX.md row is deleted
  Then  scripts/verify-index-status.sh exits 1
  And   stdout mentions "missing INDEX.md row"

Scenario: no-op guard when INDEX absent
  Given a fresh fixture directory with scripts/verify-index-status.sh but no docs/stories/INDEX.md
  When  the script runs
  Then  exit code is 0
```
