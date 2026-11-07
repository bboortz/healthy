# healthy — Claude Instructions

`hc` is a tiny container healthcheck binary: one Zig source file, no libc, no heap. It does TCP, verified TLS 1.3, and HTTP(S) checks against a **private** CA (system roots are never trusted).

Public contract: `README.md`. Internals and rationale live under `memory/`.

@memory/project.md
@memory/code-quality.md
@memory/workflow.md
@memory/testing.md
@memory/zig-pitfalls.md
@/home/benni/.claude/RTK.md

---

## Repository layout

```
hc.zig                      — the entire implementation (do not split)
Makefile                    — flowflow wrapping scripts/build.sh + tests + gates
bin/                        — gitignored; all build outputs land here (hc-<target>)
scripts/
  build.sh                  — cross-compile driver; CA=…, TLS=0, TARGET=… env knobs
  verify-traceability.sh    — enforce story ↔ plan ↔ test ↔ CAP links
test/
  run.sh                    — 28-case functional regression suite
  srv.py                    — plain HTTP + TLS 1.3 test servers
  acceptance/
    test_HC_NNN_<slug>.sh   — one script per HC-NNN story (red → green)
docs/
  stories/
    INDEX.md                — status board
    _template.md            — canonical story template (9 questions + Gherkin + §9 CAPs)
    _9-questions.md         — canonical clarification set
    HC-NNN-<slug>.md        — one file per story
  plan/
    _template.md            — plan template w/ Shipping evidence table
    IDEAS.md                — backlog of ideas not yet promoted to stories
    HC-NNN-<slug>-plan.md   — one plan per in-progress / shipped story
  CAPABILITIES.md           — capability matrix; bidirectional links to tests
.githooks/                  — commit-msg; activate via make install-hooks
.pre-commit-config.yaml     — shellcheck + zig fmt + verify-traceability
memory/                     — persistent context for Claude sessions
README.md                   — public contract: flags, URL schemes, exit codes, size table
```

---

## Development process (DD-TGD)

Design-Driven, Test-Guarded Development. Every observable change traces back to a story, a plan, and a red acceptance test. Per feature:

0. **Consult `docs/plan/IDEAS.md`** — backlog of ideas we've already discussed. New ideas go in here immediately.
1. User-facing story → `docs/stories/HC-NNN-<slug>.md` (9 canonical questions, Gherkin acceptance). Question 9 names the capabilities the story delivers.
2. Branch `feat/HC-NNN-<slug>` + plan doc `docs/plan/HC-NNN-<slug>-plan.md`.
3. Red acceptance test under `test/acceptance/test_HC_NNN_<slug>.sh` (top-of-file `# CAPs:` block names the ids it covers).
4. Implementation to turn the test green — smallest viable diff in `hc.zig` / `build.sh`.
5. **Register capabilities** — add or extend entries in `docs/CAPABILITIES.md`; ensure bidirectional links. `make verify-traceability` must pass.
6. `make check` passes locally (lint, build with/without TLS, cross, tests, traceability).
6a. **Pre-ship audit** — fill the Shipping evidence table in the plan. Three lenses: **Gherkin coverage**, **behaviour symmetry** (every CAP → ≥1 test; every exit-code path tested), **self-consistency** (story applies its own §7 out-of-scope line). Any ⚠️/❌ blocks shipping.
7. README updated only if the public contract changed (flag set, URL schemes, exit codes, size table, cross-targets, Zig version).
8. PR → `main` → merge commit (not squash).

**Exceptions (no story required):** `fix/<slug>` (with repro), `refactor/<slug>` (tests prove invariance), `chore/<slug>` (Zig bump, GHA tweak), `docs/<slug>`, `test/<slug>` (new test against an existing CAP), `ci/<slug>`.

Full gate matrix: `memory/workflow.md`. Story process & 9 questions: `docs/stories/_9-questions.md`.

---

## Git workflow

- Work branches off `main`. No `dev` branch (project is small — revisit if cadence grows).
- Every change goes through a PR — no direct pushes to `main`.
- Commit format: `<type>[(<scope>)]: <description>` — enforced by `.githooks/commit-msg`.
- Merge commits (not squash) preserve the PR boundary.
- PR title under 70 chars, same format as commits, no trailing period.

---

## Key commands

```sh
make help                # list all targets
make tools               # install Zig 0.17.1 (pipx) + verify system deps; SUDO=1 to pacman -S
make build               # x86_64-linux with TLS (default)
make test                # build + ./test/run.sh (functional regression)
make test-acceptance     # run every test/acceptance/test_HC_*.sh
make lint                # shellcheck on *.sh + zig fmt --check hc.zig
make cross               # cross-compile aarch64, riscv64, arm32, x86 (build only)
make size                # print stripped sizes against README budget
make verify-traceability # story ↔ plan ↔ test ↔ CAP enforcement
make check               # lint + build + build (TLS=0) + cross + test + test-acceptance + verify-traceability
make install-hooks       # activate .githooks (commit-msg) + pre-commit
make clean               # rm bin/ *.o .zig-cache/ zig-out/

# Variable overrides (same knobs as build.sh):
make build CA=ca.pem               # embed a private CA
make build TLS=0                   # tcp/http only (~1/4 the size)
make build TARGET=aarch64-linux    # cross-compile a specific target
```

---

## Design invariants (do not violate casually)

1. **One source file.** `hc.zig` stays single-file.
2. **No libc, no heap.** Static builds, stack arenas, no `page_allocator` smuggled through helpers.
3. **System roots are never trusted** — CA via `--ca` or embedded via `CA=…` at build time. `-k` is the explicit escape.
4. **TLS can be compiled out** — `TLS=0` must still build and `tcp://` + `http://` tests must still pass.
5. **The deadline is a watchdog** — `SIGALRM` around the whole run (Zig 0.17.1 has no POSIX connect timeout).
6. **Size budget lives in README** — breaching it by >5% needs justification in the PR body.

Full rationale: `memory/project.md`.

---

## What NOT to do

- Don't add HTTP/2, chunked transfer, redirect following, or cookies — out of scope (`memory/project.md`).
- Don't call `std.heap.page_allocator` anywhere — stack arenas only.
- Don't trust system CAs. Ever.
- Don't float the Zig version — pinned to 0.17.1. Bumping is its own `chore/zig-<version>` PR.
- Don't execute cross-compiled binaries in tests — the suite only runs x86_64. Claim cross-target success only after running on real hardware.
- Don't ship an observable change without an HC-NNN story + plan + red acceptance test + CAP entry.
- Don't put `# shellcheck disable=…` without a one-line reason next to it.
