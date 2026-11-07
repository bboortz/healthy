# `.githooks/`

Git hooks for this repository. Activated via:

```sh
make install-hooks
```

This runs `git config core.hooksPath .githooks`, pointing Git at this directory instead
of the default `.git/hooks/`. It also enables the `pre-commit` framework hooks if
`pre-commit` is installed (`pipx install pre-commit`).

## Hooks

### `commit-msg` — commit message format

Runs on every `git commit`. Enforces conventional commit format:

```
<type>[(<scope>)]: <description>
```

Types: `feat` `fix` `docs` `refactor` `chore` `ci` `test` `style` `perf`
Scopes: `hc`, `build`, `test`, `ci`, `docs` — see `memory/code-quality.md`.

### pre-commit / pre-push (via `.pre-commit-config.yaml`)

`pre-commit` runs on `git commit` (fast path, staged files):
- `shellcheck` on staged `*.sh`
- `zig fmt --check hc.zig` when `hc.zig` is staged
- `verify-traceability` when a story / plan / test / CAP path is staged

`pre-push` runs the full local gate: `make check` (lint + build + cross + test + test-acceptance + verify-traceability).

## Skipping (emergencies only)

```sh
git commit --no-verify
git push --no-verify
```

Put a note in the PR body if you bypass. Hooks exist because we got bitten before — see
`memory/zig-pitfalls.md` for one such lesson.
