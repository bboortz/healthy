*Commit, branch, style conventions. The commit-msg hook enforces the format; pre-commit runs shellcheck + zig fmt.*

## Commit message format

```
<type>[(<scope>)]: <description>
```

Types: `feat` `fix` `docs` `refactor` `chore` `ci` `test` `style` `perf`

Scopes (pick one, optional):
- `hc` — `hc.zig` itself
- `build` — `scripts/build.sh`, Makefile, cross-compile config
- `test` — `test/run.sh`, `test/srv.py`, test fixtures
- `ci` — GitHub Actions
- `docs` — README, memory/

Examples:
- `feat(hc): accept IPv6 literal in URL authority`
- `fix(build): pass -target before -M so flags aren't silently ignored`
- `test(hc): add watchdog case for hung TLS server`
- `chore(ci): pin Zig to 0.17.1`

## Branch naming

```
feat/<slug>        new capability (CLI flag, URL scheme, cross-target)
fix/<slug>         bug fix (include a repro in the PR body)
refactor/<slug>    no observable change — tests prove invariance
docs/<slug>        README or memory/ only
chore/<slug>       tooling, GHA, dependency/Zig-version bump
test/<slug>        test-only changes (new case, fixture)
ci/<slug>          GitHub Actions
```

All work branches off `main`. There is no `dev` branch yet — the project is small enough that `main` + PRs are the whole workflow. Revisit if two developers show up.

## PR title

Under 70 chars, same `<type>: <description>` format as commits, no trailing period.

## Shell style (`scripts/build.sh`, `test/run.sh`, `test/srv.py` harness)

- `#!/bin/sh` and `set -eu` for anything intended to run under BusyBox-ish shells (`scripts/build.sh`). `set -euo pipefail` only in `.githooks/*` where `/bin/bash` is explicit.
- `shellcheck` clean at `--severity=warning`. Fix at source — no inline `# shellcheck disable=...` without a one-line reason.
- Quote every variable expansion (`"$var"`), including `$@`.
- Prefer `$(…)` over backticks.

## Zig style (`hc.zig`)

- `zig fmt --check hc.zig` must pass.
- No `TODO:` / `FIXME:` without an issue or a dated note. `// NB:` is fine for one-line gotchas (see the `-M` flag-order comment in `scripts/build.sh`).
- When touching TLS code, include a reference to the Zig std file you cross-checked (version churn is real — document the source so the next bumper can diff).

## Memory file size limits

- `memory/*.md` ≤ 150 lines (except `MEMORY.md`, which is an index).
- `CLAUDE.md` ≤ 150 lines — `@memory/*.md` includes load separately.

The pre-commit hook enforces both.

## What NOT to commit

- Binaries: the whole `bin/` directory + any stray `hc-*`, `*.o` (already gitignored).
- Private CAs or keys. If you need a CA for a test, `test/run.sh` generates a throwaway one — do not check real material in.
- `.zig-cache/`, `zig-out/`, `zig-pkg/` (gitignored).
