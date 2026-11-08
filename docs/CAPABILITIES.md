# Capabilities matrix — healthy

The source of truth for what `hc` can do. Every entry has bidirectional links to the
acceptance test(s) that exercise it; `make verify-traceability` enforces both directions.

Format per entry:

```
### <cap.id>

One-line description.

- **Delivered by**: HC-NNN
- **Covered by**: `test/acceptance/test_HC_NNN_<slug>.sh` OR `test/run.sh` (seed coverage)
```

CAP id convention: `<domain>.<verb-or-shape>`. Domains in use:
`scheme` `tls` `http` `deadline` `build` `binary` `workflow`.

Seed entries below cover behaviours that pre-date the DD-TGD workflow. They point at
cases in `test/run.sh`. New capabilities get their own HC-NNN story and a dedicated
acceptance script under `test/acceptance/`.

---

## scheme.*

### scheme.tcp

Plain TCP connect to a given `host:port`. Exit 0 on connect, 1 on refused/closed,
2 on malformed URL.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### scheme.tls

TCP connect + verified TLS 1.3 handshake. Verification uses the embedded or
`--ca`-supplied CA — system roots are never trusted.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### scheme.http

HTTP/1.0 GET with `Connection: close`. Status must fall in `-s` range (default
200–299). No redirect following.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### scheme.https

HTTP/1.0 GET over a verified TLS 1.3 connection. Combines `scheme.https` + the TLS
verification path.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

## tls.*

### tls.verify-private-ca

Only CAs provided at runtime (`--ca`) or embedded at build time (`CA=ca.pem
./build.sh`) are trusted. System trust store is ignored.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### tls.verify-hostname

Certificate must list the URL host (or `-H` override) in its SAN set. Hostname
mismatch → exit 1.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### tls.skip-with-k-flag

`-k` suppresses verification entirely (name + chain), mirroring `curl -k`. Only
intended for diagnosis.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### tls.embedded-ca

A CA PEM supplied via `CA=ca.pem ./build.sh` is embedded into the binary so
`--ca` is not needed at runtime.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

## http.*

### http.status-range

`-s lo-hi` sets the accepted status range. Response status outside the range → exit 1.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### http.body-match

`-m str` requires the response body (first 1 KiB) to contain `str`. Missing → exit 1.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### http.host-header

`-H name` overrides the `Host:` header and the TLS SNI/verification name. Useful for
hitting a loopback address with a logical hostname.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

## deadline.*

### deadline.sigalrm-watchdog

`-t secs` sets an overall deadline for DNS + connect + handshake + read. Implemented
as a `SIGALRM` watchdog around the whole run (Zig 0.17.1 has no POSIX connect
timeout). Expired → stderr `hc: timeout`, exit 1.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

## build.*

### build.cross-targets

`TARGET=…` in `build.sh` produces static binaries for `x86_64-linux`,
`aarch64-linux`, `riscv64-linux`, `arm-linux-musleabihf`, `x86-linux`. Only the
x86_64 binary is executed by the test suite — others are built-only.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### build.tls-off

`TLS=0 ./build.sh` compiles out all TLS code. Resulting binary supports only
`tcp://` and `http://` and is roughly 1/4 the size.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

## binary.*

### binary.no-libc

The produced binary links no libc and makes no heap allocations. Static,
single-file, runnable in `FROM scratch`.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### binary.single-file

The entire implementation lives in `hc.zig` — one file, no module split.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

### binary.size-budget

Stripped `ReleaseSmall` build with baseline CPU features stays within the README
§ Build size table (±5%). Regressions require justification in the PR body.

- **Delivered by**: seed (pre-DD-TGD)
- **Covered by**: `test/run.sh`

## workflow.*

### workflow.local-gate-check

`make check` runs every blocking gate in one invocation — lint, build with TLS,
build with `TLS=0`, cross-compile every supported target, functional suite,
acceptance suite, and `verify-traceability`. Exit 0 ⇒ branch is PR-ready.

- **Delivered by**: HC-001
- **Covered by**: `test/acceptance/test_HC_001_dd-tgd-bootstrap.sh`

### workflow.tools-bootstrap

`make tools` installs Zig 0.17.1 via pipx (symlinking `python-zig` as `zig`) and
verifies the required Arch packages. Idempotent. `SUDO=1` is the opt-in that
lets it run `sudo pacman -S --needed <missing>`; bare `make tools` never invokes
sudo.

- **Delivered by**: HC-001
- **Covered by**: `test/acceptance/test_HC_001_dd-tgd-bootstrap.sh`

### workflow.traceability-gate

`scripts/verify-traceability.sh` enforces bidirectional links: every CAP in
`docs/CAPABILITIES.md` has a `Covered by:` pointer; every
`test/acceptance/test_HC_*.sh` has a `# CAPs:` header naming only known CAPs;
every `ready`/`in-progress`/`shipped` story has at least one CAP bullet in §9.
Invoked by `make verify-traceability` and the pre-commit hook.

- **Delivered by**: HC-001
- **Covered by**: `test/acceptance/test_HC_001_dd-tgd-bootstrap.sh`

### workflow.commit-msg-gate

`.githooks/commit-msg` rejects commit messages that don't match
`<type>[(<scope>)]: <description>` (types: feat / fix / docs / refactor / chore
/ ci / test / style / perf). Git-generated messages (Merge / Revert / fixup! /
squash!) are allowed through.

- **Delivered by**: HC-001
- **Covered by**: `test/acceptance/test_HC_001_dd-tgd-bootstrap.sh`

### build.out-dir-bin

Every `make build` and `make cross` output lands under `bin/`. `OUT ?=
bin/hc-$(TARGET)` and `HC ?= ./bin/hc-$(TARGET)` are the Makefile defaults.
`make clean` removes `bin/` entirely.

- **Delivered by**: HC-001
- **Covered by**: `test/acceptance/test_HC_001_dd-tgd-bootstrap.sh`

### build.scripts-dir

The shell build driver lives at `scripts/build.sh` — not at the repo root.
Internally it resolves the repo root via `repo="$(cd "$here/.." && pwd)"` so
`-Mroot="$repo/hc.zig"` works regardless of CWD.

- **Delivered by**: HC-001
- **Covered by**: `test/acceptance/test_HC_001_dd-tgd-bootstrap.sh`

### workflow.ci-stratified

GitHub Actions pipeline (`.github/workflows/ci.yml`) stratifies by branch:
feature pushes get `fast-check` (lint + traceability, ~30s), `dev` pushes and
PRs to `dev` get `full-check` (`make check`, ~2–3min), `main` pushes get
`release-check` (CHANGELOG + VERSION sync + tag presence, ~15s). Docs-only
diffs short-circuit the heavy tier. `concurrency: cancel-in-progress` kills
stale runs.

- **Delivered by**: HC-002
- **Covered by**: `test/acceptance/test_HC_002_ci-dev-main-promotion.sh`

### workflow.release-promotion

Manual `workflow_dispatch` release workflow (`.github/workflows/release.yml`)
fast-forwards `main` from `dev`, asserts the latest CI check-run on `dev` was
green (aborts loudly if red or not-yet-run), reads `VERSION`, tags
`v<VERSION>` iff absent, and pushes both.

- **Delivered by**: HC-002
- **Covered by**: `test/acceptance/test_HC_002_ci-dev-main-promotion.sh`

### workflow.version-sync-gate

`VERSION` + `CHANGELOG.md` live at the repo root. Every push to a non-`main`
branch must bump `VERSION` since `origin/main`, and `CHANGELOG.md` must carry
a `## [v<VERSION>]` heading. Enforced by `scripts/verify-version-bumped.sh` +
`scripts/verify-changelog.sh`; bypass via `HEALTHY_SKIP_VERSION_BUMP=1` /
`HEALTHY_SKIP_CHANGELOG=1` in emergencies.

- **Delivered by**: HC-002
- **Covered by**: `test/acceptance/test_HC_002_ci-dev-main-promotion.sh`

### workflow.pre-push-gate

The pre-push hook runs the full local gate — `make check` + `verify-version-
bumped` + `verify-changelog`. This is the primary gate; CI mirrors it in
`full-check`. A push that would fail CI fails pre-push first unless
`--no-verify` is used.

- **Delivered by**: HC-002
- **Covered by**: `test/acceptance/test_HC_002_ci-dev-main-promotion.sh`

### workflow.hooks-via-pre-commit

`make install-hooks` installs three hook types (commit-msg, pre-commit,
pre-push) via the `pre-commit` framework into `.git/hooks/`. It defensively
unsets any pre-existing `core.hooksPath` first, so upgrades from the HC-001
layout succeed without manual cleanup.

- **Delivered by**: HC-002
- **Covered by**: `test/acceptance/test_HC_002_ci-dev-main-promotion.sh`

### workflow.release-check-filter

`release.yml`'s "Assert CI is green" step picks the latest **non-skipped**
`Full check (make check)` check-run via `scripts/latest-ci-status.jq`. The
same SHA can carry multiple check-runs with that name (e.g. the dev-push
success plus a later main-push skip); the filter ignores skips so the gate
reflects the actual CI outcome, not the most-recently-started job. Reports
`"not-yet-run"` when no non-skipped runs exist.

- **Delivered by**: HC-003
- **Covered by**: `test/acceptance/test_HC_003_robust-release-pipeline.sh`

### workflow.release-check-testable

The release-gate selection logic lives in `scripts/latest-ci-status.jq`, a
single file consumed by both `release.yml` and the acceptance test. Four
fixture JSON payloads under `test/acceptance/fixtures/hc-003/` exercise the
four interesting topologies (success-after-skip, failure-after-success,
only-skipped, empty).

- **Delivered by**: HC-003
- **Covered by**: `test/acceptance/test_HC_003_robust-release-pipeline.sh`
