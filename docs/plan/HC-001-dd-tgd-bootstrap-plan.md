---
id: HC-001
slug: dd-tgd-bootstrap
story: docs/stories/HC-001-dd-tgd-bootstrap.md
branch: feat/HC-001-dd-tgd-bootstrap
status: shipped
shipped: 2026-11-07
---

# HC-001 plan — DD-TGD bootstrap: process + layout

**Story:** [HC-001](../stories/HC-001-dd-tgd-bootstrap.md)

## Design delta

Two kinds of changes, delivered together because they are both foundational:

**A. Process scaffolding** (docs-only, no binary impact)
- `docs/stories/` — `_template.md`, `_9-questions.md`, `INDEX.md`, HC-001 itself
- `docs/plan/` — `_template.md`, `IDEAS.md`, HC-001 plan (this file)
- `docs/CAPABILITIES.md` — seed (17 pre-DD-TGD CAPs pointing at `test/run.sh`) + new workflow/layout CAPs for HC-001
- `scripts/verify-traceability.sh` — bidirectional link enforcement
- `.githooks/commit-msg` + `.githooks/README.md`
- `.pre-commit-config.yaml` — shellcheck, zig-fmt, verify-traceability, memory-size, pre-push `make check`
- `memory/MEMORY.md` + five topic files (`project`, `code-quality`, `workflow`, `testing`, `zig-pitfalls`)
- `CLAUDE.md` — `@`-includes memory + names invariants
- `Makefile` — the "flowflow": help, tools, build, cross, test, test-acceptance, lint, zig-fmt, shell-lint, verify-traceability, size, check, install-hooks, clean, distclean
- `test/acceptance/` + its `README.md` — new DD-TGD acceptance-test home (red for HC-001 → green at merge)

**B. Layout move** (one behaviour delta — observable at `make build` + `make clean`)
- Build outputs move from the repo root to `bin/`. `Makefile`'s `OUT ?= bin/hc-$(TARGET)`; `HC ?= ./bin/hc-$(TARGET)`; `clean` removes `bin/`.
- Build driver moves from `./build.sh` to `scripts/build.sh`. Its internal `here=$(…)/scripts` resolves back to the repo root via `repo="$(cd "$here/.." && pwd)"`, so `-Mroot="$repo/hc.zig"` still points at the source regardless of CWD.
- `.gitignore` swaps `hc-*` / `hc_*` for `bin/`.
- `README.md` + `memory/{project,testing,zig-pitfalls,code-quality}.md` + `CLAUDE.md` updated at every mention of `./build.sh` → `scripts/build.sh` and `./hc-x86_64-linux` → `./bin/hc-x86_64-linux`.

Everything in `hc.zig` is untouched. No CLI flag, exit code, or URL scheme moves.

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Ship DD-TGD and `bin/` in separate PRs | `bin/` touches the same `Makefile` and `README.md` that DD-TGD scaffolding touches. Split = two conflicting PRs on the same files. Bundling is cheaper. |
| Keep `build.sh` at repo root and only move binaries | The repo root was already cluttered with a shell script, its test script, and 5 stale cross-built binaries. `scripts/` + `bin/` is a single pass of hygiene; doing half is odd. |
| Use `out/` instead of `bin/` | `bin/` is the universal convention for executable artefacts; `out/` reads as a general staging dir. Downstream Dockerfiles that `COPY --from=…` will reference `bin/hc-…` which is self-explanatory. |
| Promote seed CAPs (17 of them) to per-CAP `test_HC_SEED_<cap>.sh` scripts | 17 scripts of churn for zero test-coverage gain. The existing `test/run.sh` already covers them. New capabilities get their own HC-NNN scripts; seeds keep pointing at `test/run.sh`. See `test/acceptance/README.md`. |
| Put `verify-traceability` inside the `Makefile` recipe (no external script) | Multi-line make recipes with awk inside are a pain to shellcheck and debug. A dedicated `.sh` under `scripts/` is grep-able, shell-checked, and callable from pre-commit directly. |

## Breaking changes

- [ ] Yes — behaviour deltas visible to anyone who built this repo before HC-001:
  - `./build.sh` no longer exists → use `scripts/build.sh` (or `make build`).
  - `./hc-x86_64-linux` no longer produced → outputs now under `bin/`.
  - `./test/run.sh` default `HC` env var was `./hc-x86_64-linux` → now `./bin/hc-x86_64-linux`.

README is updated in this same change so the public-contract paths match.

## Rollout

- [x] README updated (build + test invocation examples)
- [x] `memory/project.md` invariants unchanged (layout isn't an invariant — single-file still holds)
- [x] `memory/zig-pitfalls.md` updated at every `build.sh` reference
- [x] `memory/testing.md` updated at the `HC=` example
- [x] `memory/code-quality.md` updated at the shellcheck target list
- [x] `CLAUDE.md` repo-layout section updated
- [ ] Downstream notice — none required; no published tags exist yet.

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (story §8) | Test pointer | Status |
|---|---|---|
| Scaffold files exist | `test/acceptance/test_HC_001_dd-tgd-bootstrap.sh` (Scenario 1 block) | ✅ |
| Traceability gate green | same file, Scenario 2 block | ✅ |
| Build outputs land under `bin/` | same file, Scenario 3 block | ✅ |
| Build driver lives under `scripts/` | same file, Scenario 4 block | ✅ |
| Size caps enforced | same file, Scenario 5 block | ✅ |
| Flowflow targets exist | same file, Scenario 6 block | ✅ |
| Conventional-commit gate | same file, Scenario 7 block | ✅ |

### Lens 2 — Behaviour symmetry

| CAP delivered | ≥ 1 test? | Exit-code paths (0 / 1 / 2) | Status |
|---|---|---|---|
| `workflow.local-gate-check` | ✅ (Scenario 6 asserts `make -n check`) | 0 only — `make check` is a gate | ✅ |
| `workflow.tools-bootstrap` | ✅ (Scenario 6 asserts `make -n tools`) | 0 only — side-effect free in `-n` | ✅ |
| `workflow.traceability-gate` | ✅ (Scenario 2) | 0 asserted; 1 path proven ad-hoc (any new CAP w/o `Covered by:` fails the script) | ✅ |
| `workflow.commit-msg-gate` | ✅ (Scenario 7 tests both 0 and 1) | 0 + 1 both covered | ✅ |
| `build.out-dir-bin` | ✅ (Scenario 3) | 0 path covered; "root has no hc-*" is the negative assertion | ✅ |
| `build.scripts-dir` | ✅ (Scenario 4) | 0 path covered | ✅ |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys its own §7 (out-of-scope) — no CI, no `hc.zig` changes | ✅ |
| New CAPs listed in §9 all appear in `docs/CAPABILITIES.md` | ✅ |
| If `TLS=0` path touched: `TLS=0 make build && make test` green | ✅ (runs as part of `make check`) |
| If cross-target path touched: `make cross` green | ✅ (runs as part of `make check`) |
| `make verify-traceability` green | ✅ |
| Size budget within ±5% of README table (or justified above) | ✅ — layout change does not touch the compile step |

## Post-merge notes

First DD-TGD story — bundled the process scaffolding with the first observable
behaviour delta (repo layout: `bin/` for outputs, `scripts/` for the build driver).
This establishes the pattern for every subsequent HC-NNN: story + plan + red
acceptance test + CAP entries + implementation, all in the same PR.

The Shipping evidence table did its job — no surprises during the impl pass. The
one place worth remembering: when writing the first acceptance test, `set -u`
was deliberate so an unset counter is noisy, not silent. Reuse the `assert_rc` /
`assert_exists` / `assert_absent` / `assert_exec` / `assert_line_cap` helpers in
future acceptance scripts — they're the lingua franca of this project's test
harness, mirroring the `t <want>` helper in `test/run.sh`.

Open follow-ups (own stories):
- CI parity with `make check` (GitHub Actions)
- `make check` performance (stable `cfg.zig` cache path + dedupe `build` prereqs)
