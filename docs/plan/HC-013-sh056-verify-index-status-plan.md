---
id: HC-013
slug: sh056-verify-index-status
story: docs/stories/HC-013-sh056-verify-index-status.md
branch: feat/SH-056-verify-index-status
status: in-progress
---

# HC-013 plan — Adopt shepherd verify-index-status script + check-docs wiring

**Story:** [HC-013](../stories/HC-013-sh056-verify-index-status.md)

## Design delta

1. Copy `scripts/verify-index-status.sh` from shepherd BYTE-IDENTICAL (same
   executable bit, same content, same sha256). Future SH-NNN may sha256-check it.
2. Align `docs/stories/INDEX.md` to shepherd's column shape
   (`| ID | Status | Slug | Title |`) so the script's `awk -F'|'` field-3 status
   extractor finds the right column.
3. Sync stale frontmatter: HC-009..HC-012 marked `status: shipped` to match
   their already-shipped commits (c9e413e, 990375f, 9241731, 08e8922).
4. Add `verify-index-status` to the top `.PHONY` list near the other verify-*
   targets.
5. Add target definition after the existing verify-* targets:

   ```make
   verify-index-status:
   	@scripts/verify-index-status.sh
   ```

6. Add `verify-index-status` to `check-docs`'s prerequisite list near the front:

   ```make
   check-docs: verify-index-status verify-traceability verify-version-bumped verify-changelog
   ```

- No step-level target is renamed or moved.
- Script content is NOT adapted — it's byte-identical to shepherd's.
- Pattern mirrors shepherd PR #59 (SH-056).

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Fork the script with healthy-specific logic | Breaks fleet consistency; future SH-NNN may enforce script identity via sha256. |
| Skip the INDEX reshape (6-column with Slug col 2) | Breaks the script's `awk -F'|'` field-3 status assumption. Fleet INDEX shape must match. |
| Append `verify-index-status` at the end of `check-docs` | Front position matches shepherd's reference impl + fails fast on the cheapest check. |
| Leave HC-009..HC-012 frontmatter as `ready` | They are shipped (merged commits exist); the frontmatter was the stale side, not INDEX. |

## Breaking changes

- [ ] Yes
- [x] No — strictly additive on the Makefile + script side. INDEX reshape is
      cosmetic for humans; grep patterns of form `^| HC-NNN |` still match.

## Rollout

- [ ] README updated (if public contract moved) — n/a, dev-cycle only.
- [ ] `memory/project.md` invariants updated — n/a.
- [ ] `memory/zig-pitfalls.md` entry added — n/a.
- [ ] Downstream notice sent — n/a.

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (from story §8) | Test pointer | Status |
|---|---|---|
| script exists and is executable | `test/acceptance/test_HC_013_verify_index_status.sh` scenario 1 | ✅ |
| script byte-identical to shepherd's | `sha256sum` match checked out-of-band (both scripts tracked) | ✅ |
| healthy passes the verifier | `test/acceptance/test_HC_013_verify_index_status.sh` scenario 2 | ✅ |
| Makefile declares verify-index-status + wires into check-docs | `test/acceptance/test_HC_013_verify_index_status.sh` scenarios 5+6 | ✅ |
| `make -n` resolves to the script | `test/acceptance/test_HC_013_verify_index_status.sh` scenario 7 | ✅ |
| drift catch (row status flipped) | `test/acceptance/test_HC_013_verify_index_status.sh` scenario 3 | ✅ |
| missing INDEX row | `test/acceptance/test_HC_013_verify_index_status.sh` scenario 4 | ✅ |
| no-op guard when INDEX absent | `test/acceptance/test_HC_013_verify_index_status.sh` scenario 8 | ✅ |

### Lens 2 — Behaviour symmetry

| CAP delivered | ≥1 test? | Exit-code paths tested (0/1/2)? | Status |
|---|---|---|---|
| `dev-cycle.verify-index-status` | yes | 0 (ok, no-op) + 1 (row-flip, missing-row) | ✅ |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys its own §7 (out-of-scope) — no scope creep | ✅ |
| New CAPs listed in §9 all appear in `docs/CAPABILITIES.md` | ✅ |
| Script byte-identical to shepherd (sha256 match) | ✅ |
| `make verify-traceability` green | ✅ |
| `make verify-index-status` green | ✅ |

## Post-merge notes

<Filled after merge.>
