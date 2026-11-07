---
id: HC-001
slug: dd-tgd-bootstrap
status: shipped
created: 2026-11-07
shipped: 2026-11-07
owner: @benni
---

# HC-001 — DD-TGD bootstrap: process + layout

## 1. Who is the consumer?

**The maintainer.** Everyone else interacts with `hc` as a built binary; this story is
the thing the maintainer needs in place before any further story can land.

## 2. When does the story fire?

Once, at repo initialization. Each later story cuts a branch from the state this one
leaves behind: a shippable local gate, a story template, a traceability check, and a
clean layout for build artefacts.

## 3. What does success look like?

A fresh clone reaches a green local gate with three commands:

```
make tools            # installs Zig 0.17.1 (pipx) + verifies system deps
make install-hooks    # activates .githooks/commit-msg + pre-commit
make check            # lint + build + build (TLS=0) + cross + test + test-acceptance + verify-traceability
```

Observable at merge time:
- `make check` exits 0 on `main`.
- `make build` produces `bin/hc-x86_64-linux`, not `./hc-x86_64-linux`.
- Build driver lives at `scripts/build.sh`, not `./build.sh`.
- `make verify-traceability` finds every CAP in `docs/CAPABILITIES.md` linked to
  at least one test file and every acceptance test's `# CAPs:` header linked back.
- A commit with a non-conventional subject is rejected by `.githooks/commit-msg`.

## 4. How urgent?

**Correctness** — the whole point of DD-TGD is that nothing else ships until the
process gate exists. Not security-critical, but foundationally blocking.

## 5. Happy path

```sh
git clone <this-repo> healthy
cd healthy
make tools                                   # one-shot bootstrap
make install-hooks
make check                                   # exits 0
ls bin/                                      # hc-x86_64-linux lives here, not at repo root
ls scripts/                                  # build.sh lives here, not at repo root
```

## 6. Edge cases / failure modes that matter

- `make tools` is idempotent: re-running it when `ziglang` and `pre-commit` are already
  installed must not uninstall / reinstall / hang.
- `make tools SUDO=1` installs missing Arch packages via `sudo pacman -S --needed`; the
  bare `make tools` form must never invoke sudo.
- `make check` must detect a missing `# CAPs:` header in a new acceptance test and
  fail — not pass silently.
- A `ready+` story missing a §9 CAP bullet must fail `make verify-traceability`.
- `make clean` must remove `bin/` (not leave stale binaries behind).
- Running `scripts/build.sh` from an unrelated CWD still finds `hc.zig` at the repo
  root (its `here=$(…)/scripts` resolves back to the repo root internally).

## 7. Out of scope

- CI (GitHub Actions). Local-gate parity with CI is a later story.
- Any change to `hc.zig` behaviour. Flag set, URL schemes, exit codes, size table — all
  frozen at seed values.
- Release automation (tags, SBOM, cosign signing, GHCR push).
- A `dev` branch. Single-trunk `main` is deliberate; see `memory/workflow.md`.
- Migrating pre-DD-TGD seed CAPs away from `test/run.sh` into per-CAP acceptance
  scripts — that's deliberate churn avoided, see `test/acceptance/README.md`.

## 8. Acceptance (Gherkin → shell assertions)

```gherkin
Scenario: Scaffold files exist
  Given a fresh clone
  Then docs/stories/_template.md, _9-questions.md, INDEX.md all exist
  And  docs/plan/_template.md, IDEAS.md exist
  And  docs/CAPABILITIES.md exists
  And  scripts/verify-traceability.sh is executable
  And  .githooks/commit-msg is executable
  And  .pre-commit-config.yaml exists
  And  memory/MEMORY.md and CLAUDE.md exist

Scenario: Traceability gate green
  When I run `bash scripts/verify-traceability.sh`
  Then it exits 0

Scenario: Build outputs land under bin/
  When I run `make build`
  Then `bin/hc-x86_64-linux` exists
  And  no `hc-*` binary exists at the repo root

Scenario: Build driver lives under scripts/
  Then `scripts/build.sh` exists and is executable
  And  no `build.sh` exists at the repo root

Scenario: Size caps enforced
  Then every memory/*.md (except MEMORY.md) has ≤ 150 lines
  And  CLAUDE.md has ≤ 150 lines

Scenario: Flowflow targets exist
  Then `make -n <target>` succeeds for each of:
       tools build cross test test-acceptance lint
       verify-traceability size check install-hooks clean

Scenario: Conventional-commit gate rejects garbage, accepts well-formed
  When I pipe "garbage message" through .githooks/commit-msg
  Then it exits 1
  And  when I pipe "feat(hc): valid" through it
  Then it exits 0
```

## 9. Capabilities delivered or extended

- `workflow.local-gate-check` — `make check` runs every blocking gate (lint + build ± TLS + cross + test + test-acceptance + verify-traceability) in one invocation.
- `workflow.tools-bootstrap` — `make tools` installs Zig 0.17.1 via pipx and verifies system deps; idempotent; `SUDO=1` opt-in for `pacman -S`.
- `workflow.traceability-gate` — `scripts/verify-traceability.sh` enforces bidirectional story ↔ plan ↔ test ↔ CAP links; invoked by `make verify-traceability` and the pre-commit hook.
- `workflow.commit-msg-gate` — `.githooks/commit-msg` enforces conventional commit format on every `git commit`.
- `build.out-dir-bin` — every `make build` / `make cross` output lands in `bin/`; `make clean` removes the directory.
- `build.scripts-dir` — the shell build driver lives at `scripts/build.sh`; no `build.sh` at the repo root.
