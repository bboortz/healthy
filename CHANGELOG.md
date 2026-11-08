# Changelog

All notable changes to `healthy` are recorded here. The format is based on
[Keep a Changelog](https://keepachangelog.com/) and this project follows
[Semantic Versioning](https://semver.org/).

## [v0.1.0] — 2026-11-07

Initial tagged version. Bundles the repository bootstrap (HC-001) and the
CI + release workflow (HC-002).

### Added (HC-001)

- **DD-TGD workflow scaffold**: `docs/stories/` with `_template.md`,
  `_9-questions.md`, `INDEX.md`; `docs/plan/` with `_template.md` and
  `IDEAS.md`; `docs/CAPABILITIES.md` seeding 17 capabilities for existing
  `hc` behaviour.
- **Traceability gate**: `scripts/verify-traceability.sh` enforces
  bidirectional story ↔ plan ↔ test ↔ CAP links; `make verify-traceability`.
- **Memory scaffold**: `memory/MEMORY.md` + topic files (`project`,
  `code-quality`, `workflow`, `testing`, `zig-pitfalls`), each ≤ 150 lines.
- **Flowflow `Makefile`**: `tools`, `build`, `cross`, `test`,
  `test-acceptance`, `lint`, `verify-traceability`, `size`, `check`,
  `install-hooks`, `clean`, `distclean`.
- **One-shot bootstrap**: `make tools` installs Zig 0.17.1 via pipx
  (symlinks `python-zig` to `~/.local/bin/zig`), verifies Arch system
  packages; `SUDO=1` opts into `sudo pacman -S --needed`.
- **Pre-commit framework config** (`.pre-commit-config.yaml`): shellcheck,
  `zig fmt`, memory-size cap, `verify-traceability`.
- **Conventional-commit gate**: `.githooks/commit-msg` (later moved in
  HC-002).
- **Repo layout**: build outputs land under `bin/`; shell build driver
  lives at `scripts/build.sh` with `repo="$(cd "$here/.." && pwd)"`
  internal path resolution.
- **Acceptance harness**: `test/acceptance/test_HC_001_dd-tgd-bootstrap.sh`
  (50 assertions across 7 Gherkin scenarios).

### Added (HC-002)

- **CI pipeline** (`.github/workflows/ci.yml`): stratified by branch —
  `fast-check` on feature branches, `full-check` on `dev` + PRs to `dev`,
  `release-check` on `main`. Docs-only diffs short-circuit the heavy tier.
  Optional Telegram failure ping.
- **Release workflow** (`.github/workflows/release.yml`): manual
  `workflow_dispatch` fast-forwards `main` from `dev`, asserts CI green,
  tags `v<VERSION>`.
- **VERSION / CHANGELOG discipline**: `VERSION` file at the repo root;
  `scripts/verify-version-bumped.sh` enforces monotonic bump vs
  `origin/main`; `scripts/verify-changelog.sh` enforces a `## [v<VERSION>]`
  heading in this file. `make verify-version-bumped` + `make
  verify-changelog`.
- **Pre-push as the primary gate**: `.pre-commit-config.yaml` pre-push
  stage runs `make check` + `verify-version-bumped` + `verify-changelog`.
- **Hook install fix**: `make install-hooks` now defensively unsets
  `core.hooksPath` and installs commit-msg / pre-commit / pre-push via the
  `pre-commit` framework. Resolves the HC-001 conflict reported by the
  operator on 2026-11-07.
- **Branch model**: `main` is CI-promoted-only; `dev` is the integration
  branch. Documented in `memory/workflow.md` and `CLAUDE.md`.

### Moved

- `.githooks/commit-msg` → `scripts/check-commit-msg.sh`
  (consumed by pre-commit's `commit-msg` stage).

### Removed

- `.githooks/` directory (replaced by pre-commit framework managing
  `.git/hooks/` directly).

### Fixed (HC-002)

- **CI — Zig install on cold runners**: resolve `python-zig`'s install path
  via `pipx environment --value PIPX_BIN_DIR` and `mkdir -p ~/.local/bin`
  before the symlink. Previous recipe hard-coded `~/.local/bin/python-zig`
  which doesn't exist until pipx creates it on a specific runner.
- **`release.yml` — `checks: read` permission**: the "Assert CI is green"
  step calls `gh api repos/.../check-runs`, which the default
  `GITHUB_TOKEN` cannot access without an explicit `checks: read` scope.
  The workflow previously declared only `contents: write` and failed with
  `403 "Resource not accessible by integration"` on the first attempt to
  promote `dev`. Now declares both. `v0.1.0`'s git tag stays on the
  bootstrap merge SHA (`ac9c2af`); this fix is a post-tag main-branch
  carry that folds into the next bumped VERSION.
- **Acceptance test `test_HC_002_…` — fork bomb**: the Scenario-4
  "force-fail" block contained a leftover `"$0"` placeholder that
  recursively re-executed the script. Dormant before HC-002 merged
  (origin/main had no `VERSION` to trigger the guard); once HC-002
  merged, the guard passed and both local pre-push and CI full-check
  hung forever. Line removed; the real assertion two lines below was
  the only intended check.

### Added (HC-003)

- **`workflow.release-check-filter`** — `release.yml`'s "Assert CI is
  green" step now picks the latest **non-skipped** `Full check (make
  check)` check-run via `scripts/latest-ci-status.jq`. Correctly resolves
  the mixed-topology case where the same SHA carries both a dev-push
  success and a later main-push skip. Previous inline jq grabbed the
  latest overall (the skip), masking the real success.
- **`workflow.release-check-testable`** — jq filter extracted to
  `scripts/latest-ci-status.jq` (single source of truth consumed by both
  `release.yml` and the acceptance test). Four fixture JSON payloads
  under `test/acceptance/fixtures/hc-003/` cover success-after-skip,
  failure-after-success, only-skipped, and empty topologies.

### Fixed (HC-003)

- **`test_HC_002` Scenario-4 on `main`** — the force-fail assertion
  assumed `verify-version-bumped` would fail when VERSION matches
  `origin/main`'s. True off-main; on-main the script correctly
  short-circuits with exit 0, making the assertion unsatisfiable. Guard
  added — on `main` the test only asserts the short-circuit itself.
  Surfaced during the HC-002 → `main` manual bootstrap promotion push.

### Added (HC-006)

- **`hc.idle-mode`** — new subcommand `hc idle` blocks on `{SIGTERM,
  SIGINT}` via `sigprocmask(BLOCK) + signalfd + read`, then exits 0 on
  either signal. Zero CPU while blocked (process is in `TASK_INTERRUPTIBLE`;
  verified with `ps` showing `STAT=SN %CPU=0.0`). PID-1 safe: the
  signalfd pattern counts as explicit signal handling from the kernel's
  POV, so a scratch container with `CMD ["/hc", "idle"]` responds to
  `docker stop` within the grace window (measured <2s on a local
  round-trip test). `hc idle <anything>` exits 2 (usage error). Enables
  forge's FG-031 to collapse `healthy-scratch-trixie` to pure
  `FROM scratch + COPY /hc + CMD ["/hc", "idle"]` — no `sleep`, no libc,
  no OS packages. Binary cost: +216 bytes.
- **Invariant update** — `memory/project.md` now names `hc idle` as the
  **only** long-running shape and explicitly closes the door on a `hc
  watch` / `hc serve` / `--daemon` scope creep via a new "No daemon mode
  with side effects" line in the "What is NOT in scope" list.

### Added (HC-005)

- **`image.scratch-single-file`** — a new top-level `Dockerfile` packages
  the `hc` binary in a `FROM scratch` image. Build-arg `HC_BIN` selects
  which cross-compiled binary to COPY in; the resulting layer contains
  exactly one regular file (`/hc`) with `ENTRYPOINT ["/hc"]`. No shell,
  no `/etc/passwd`, no CA bundle, no implicit metadata. Locally verified
  with `docker export | tar -t` filtered for Docker's runtime overlay.
- **`workflow.publish-ghcr-image`** — `release.yml` grows a
  `publish-image` job that runs after the existing `promote` step. The job
  builds `hc` for `linux/amd64` + `linux/arm64` via the existing
  `scripts/build.sh` cross-targets, logs into `ghcr.io` with the default
  `GITHUB_TOKEN` (`packages: write`), pushes per-arch single-platform
  images, and creates a multi-arch manifest list under `:<version>`,
  `:<major>.<minor>`, `:<major>`, and `:latest`. Unblocks downstream
  consumers (e.g. `bboortz/forge`'s FG-030) to `COPY --from=ghcr.io/
  bboortz/hc:<ver> /hc /hc` in their own scratch Dockerfiles — no closure,
  no shell, 404 KB instead of GnuTLS's ~24 MB.

### Added (HC-004)

- **`docs.integration-patterns`** — `README.md` now carries a dedicated
  "Usage patterns" section with concrete, copy-paste-ready blocks for
  Docker (Dockerfile `HEALTHCHECK` + `docker-compose.yml`), Kubernetes
  (`startupProbe` + `readinessProbe` + `livenessProbe`, exec-form), and
  Ansible (`command`-module smoke task mirroring homelab's retry
  convention). Each environment covers the startup-tight (`-t 1`) and
  steady-state (`-t 5`) variants. A migration table maps the four common
  legacy patterns (`urllib.request.urlopen`, `curl -sf`, `wget -qO-`,
  `nc -z`) to their `hc` equivalents, drawn from the `bboortz/homelab`
  survey conducted 2026-11-08. Grep-based acceptance assertions prevent
  silent rot.
