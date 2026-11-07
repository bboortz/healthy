---
id: HC-NNN
slug: short-kebab
story: docs/stories/HC-NNN-<slug>.md
branch: feat/HC-NNN-<slug>
status: in-progress    # in-progress → shipped
---

# HC-NNN plan — <one-line title>

**Story:** [HC-NNN](../stories/HC-NNN-<slug>.md)

## Design delta

<What changes in the codebase. Which file(s), which function(s), which flag(s). Keep this
concrete — a reader should be able to predict the diff shape from reading this section.>

## Alternatives rejected

| Alternative | Why not |
|---|---|
| <option A> | <reason — size, scope, fragility, supply chain> |
| <option B> | <reason> |

## Breaking changes

- [ ] Yes — <describe>: CLI flag removed/renamed, exit code semantics changed, URL scheme
      dropped, embedded-CA behaviour changed, size regression > 5%, …
- [ ] No — strictly additive or internal.

If yes, README must be updated in the same PR and the PR body must call out the break.

## Rollout

- [ ] README updated (if public contract moved)
- [ ] `memory/project.md` invariants updated (if an invariant shifted)
- [ ] `memory/zig-pitfalls.md` entry added (if a new Zig gotcha surfaced)
- [ ] Downstream notice sent to consumers (only if tags / digests they depend on moved)

## Shipping evidence (fill at step 6a)

Three lenses. Any ⚠️/❌ row blocks shipping — cycle back to step 4.

### Lens 1 — Gherkin coverage

| Scenario (from story §8) | Test pointer | Status |
|---|---|---|
| <Scenario name> | `test/acceptance/test_HC_NNN_<slug>.sh:LN` | ✅ / ⚠️ / ❌ |

### Lens 2 — Behaviour symmetry

| CAP delivered | ≥1 test? | Exit-code paths tested (0/1/2)? | Status |
|---|---|---|---|
| `cap.id.name` | | | ✅ / ⚠️ / ❌ |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys its own §7 (out-of-scope) — no scope creep | ✅ / ⚠️ / ❌ |
| New CAPs listed in §9 all appear in `docs/CAPABILITIES.md` | ✅ / ⚠️ / ❌ |
| If `TLS=0` path touched: `TLS=0 make build && make test` green | ✅ / ⚠️ / ❌ / n/a |
| If cross-target path touched: `make cross` green | ✅ / ⚠️ / ❌ / n/a |
| `make verify-traceability` green | ✅ / ⚠️ / ❌ |
| Size budget within ±5% of README table (or justified above) | ✅ / ⚠️ / ❌ |

## Post-merge notes

<Filled after the PR merges. One paragraph: what we learned, what bit us, what to carry
into the next story.>
