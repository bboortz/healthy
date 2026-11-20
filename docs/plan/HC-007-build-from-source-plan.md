---
id: HC-007
slug: build-from-source
story: docs/stories/HC-007-build-from-source.md
branch: feat/HC-007-build-from-source
status: shipped
shipped: 2026-11-20
---

# HC-007 plan — Build `hc` from source inside the Docker image

**Story:** [HC-007](../stories/HC-007-build-from-source.md)

## Dependencies — resolve before cutting the branch

All dependencies **resolved as of 2026-11-20**:

| Item | Who owns it | Final state | Blocked HC-007? |
|---|---|---|---|
| `ghcr.io/bboortz/forge-builder-zig-trixie` published + public + Zig 0.17.1 | forge (FG-072 + follow-up bump) | ✅ verified via `docker pull` + `zig version` on 2026-11-20 | resolved |
| Pre-flight: amd64 + aarch64 cross-compile inside the image produces correct ELFs | @benni / Claude | ✅ smoke-tested — amd64 404 KB ran clean against `benni.tech`; aarch64 346 KB confirmed `ELF 64-bit LSB executable, ARM aarch64` via `file(1)` | resolved |
| Open Questions §3 + §4 | @benni / Claude | ✅ story's "Open questions" section — all four resolved | resolved |

## Design delta

### Dockerfile (replaces HC-005's version wholesale)

```dockerfile
# syntax=docker/dockerfile:1.7
# HC-007: multi-stage build-from-source. Stage 1 compiles hc.zig inside
# forge's shared Zig builder; Stage 2 is scratch + /hc.

ARG FORGE_BUILDER_ZIG_REF=ghcr.io/bboortz/forge-builder-zig-trixie:latest

# ── Stage 1: builder (forge-maintained, Zig toolchain pre-baked) ─────────────
# Pre-provides per images/forge-builder-zig-trixie/PROMISES.yaml (FG-072):
#   - /usr/local/bin/zig   (Zig 0.17.1; forge pins via zig-slim-trixie base)
#   - /usr/local/bin/syft  (SBOM tool; reserved for HC-008 follow-up)
#   - /etc/ssl/certs/ca-certificates.crt
#   - apt-upgraded trixie userland (no apt-list cache)
#   - git, curl, jq (for future FG-013-style upstream-tag resolution)
# hadolint ignore=DL3029
FROM --platform=linux/amd64 ${FORGE_BUILDER_ZIG_REF} AS builder

ARG ZIG_TARGET=x86_64-linux
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

WORKDIR /src
# Directory-preserving COPY so scripts/build.sh's `repo=$(cd "$here/.." && pwd)`
# resolves to /src and finds /src/hc.zig via -Mroot. Flattening would break
# the module-path resolution noted in memory/zig-pitfalls.md.
COPY hc.zig            /src/hc.zig
COPY scripts/build.sh  /src/scripts/build.sh

# Explicit TARGET=${ZIG_TARGET} because ARG values are substituted into RUN
# commands, but the forked /bin/sh that runs build.sh doesn't inherit ARG as
# an env var. Without the explicit prefix, build.sh sees an empty $TARGET
# and silently defaults to its own fallback (x86_64-linux), producing the
# wrong arch for arm64 builds.
RUN TARGET=${ZIG_TARGET} sh /src/scripts/build.sh && \
    mv "bin/hc-${ZIG_TARGET}" /hc && \
    ls -lh /hc

# ── Stage 2: runtime ─────────────────────────────────────────────────────────
FROM scratch

LABEL org.opencontainers.image.source="https://github.com/bboortz/healthy"
LABEL org.opencontainers.image.description="Tiny static TCP / TLS 1.3 / HTTP(S) health check probe. Scratch-safe. No libc, no heap."
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

COPY --from=builder /hc /hc
ENTRYPOINT ["/hc"]
```

**Pre-flight verified** (2026-11-20 against `ghcr.io/bboortz/forge-builder-zig-trixie:latest`):
- `--build-arg ZIG_TARGET=x86_64-linux`  → 404 608 B image; `hc -k https://benni.tech/` exits 0.
- `--build-arg ZIG_TARGET=aarch64-linux` → 346 752 B image; `file(1)` confirms `ELF 64-bit LSB executable, ARM aarch64, statically linked, stripped`.

Key decisions baked into that shape:

- **`FROM --platform=linux/amd64`** on the builder stage. Zig
  cross-compiles cleanly on amd64 to any target (`TARGET=aarch64-linux`
  inside `build.sh` produces an arm64 binary via `zig build-exe -target
  aarch64-linux`). Pinning the builder platform avoids QEMU-emulated apt
  on arm64 runners (which would push the per-arch CI build time from ~30 s
  to several minutes).
- **`ARG ZIG_TARGET=x86_64-linux`** replaces HC-005's `ARG HC_BIN`.
  Default produces an amd64 binary; CI overrides for `aarch64-linux`
  during the arm64 publish. `scripts/build.sh` reads `TARGET` from env;
  same knob, now sourced from a build-arg.
- **`COPY hc.zig /src/hc.zig` + `COPY scripts/build.sh /src/scripts/build.sh`**.
  Explicit destination paths preserve the directory structure
  `scripts/build.sh` expects for `-Mroot` resolution.
- **Reuse `scripts/build.sh`**. One source of truth for build flags (TLS
  on/off, cross-target naming, the `-M` flag order the whole project
  learned the hard way — see `memory/zig-pitfalls.md § -M flag order`).
  Alternative — inline the `zig build-exe …` command in the Dockerfile —
  would drift against the script.
- **Smoke-exec `/hc 2>&1 | head -1`**. Catches "build.sh exited 0 but
  produced no binary" or "built but segfaults on startup" before the
  layer gets cached. Cheap safety check.
- **Three OCI labels mirrored from HC-005** (source, description, licenses)
  plus two new ones populated by `--build-arg` (revision, created). Match
  the forge-builder's own labelling shape so downstream `docker image
  inspect` reports who built when.

### `.dockerignore` (new)

Allowlist (per Open Question §4 recommendation):

```
# Block everything, then selectively allow what the Dockerfile COPYs.
*
!hc.zig
!scripts/build.sh
# Don't allow scripts/build.sh's siblings; they're not in the build context.
```

Rationale: the current repo has ~100 files across memory, docs, tests, bin.
A cold `docker build` without `.dockerignore` sends the whole tree to the
daemon — slower builds, larger build-cache invalidation surface, exact
`bin/` binaries end up in the context (and would be ignored anyway, but
the context digest changes for each build). Allowlist is the tightest
shape and fails loudly if a future file genuinely needs to join the
build context (just add a `!path` line — forcing a reviewer to see what
grew).

### `.github/workflows/release.yml` — `publish-image` job slimmed

Steps removed from the current job (HC-005 shape):

1. **`Install Zig 0.17.1 via pipx`** (~10 s) — forge's base owns Zig now.
2. **`Build amd64 + arm64 binaries via scripts/build.sh`** (~30 s) — happens
   inside `docker buildx build` now, one stage per arch.

Steps that change:

- `Build + push amd64`: `--build-arg HC_BIN=bin/hc-x86_64-linux` →
  `--build-arg ZIG_TARGET=x86_64-linux`
- `Build + push arm64`: `--build-arg HC_BIN=bin/hc-aarch64-linux` →
  `--build-arg ZIG_TARGET=aarch64-linux`

Everything else (GHCR login, manifest list creation for 4 tags, summary
step) stays identical.

Net CI job time: roughly unchanged. Cold runs lose ~10 s (no pipx
install) + gain ~15 s (docker pull of the forge builder image). Warm
runs — where buildx cache hits the builder stage — are faster.

### `test/acceptance/test_HC_005_publish-ghcr-image.sh` (modified)

HC-005 asserts `ARG HC_BIN` in the Dockerfile; HC-007 removes that arg.
The HC-005 test's one `assert_grep '^ARG HC_BIN' Dockerfile` line moves
to `assert_grep '^ARG ZIG_TARGET' Dockerfile`. HC-005's other 27
assertions (image shape, entrypoint, `/hc`-only content, size ceiling,
release.yml wiring for the fixed-up tags, etc.) are unchanged.

### `test/acceptance/test_HC_007_build-from-source.sh` (new)

Six Gherkin scenarios from the story's §8:

1. Multi-stage Dockerfile — exactly two `FROM`, builder from forge image, runtime `scratch`, no `ARG HC_BIN`.
2. Builder base uses forge's Zig via `FROM ...forge-builder-zig-trixie`; no `pipx install`, no `apt-get install` in healthy's own Dockerfile.
3. End-to-end: `docker build` from a fresh checkout; `docker run -k https://benni.tech/` exits 0.
4. Image size within ±5% of HC-005's 405 KB.
5. `release.yml`'s `publish-image` job dropped the two removed steps and uses `ZIG_TARGET` build-arg.
6. HC-005's acceptance test updated for the new build-arg name.

Docker-gated same way HC-005's online scenarios are — developer without docker gets a skip note; CI runners always have docker.

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Keep `debian:trixie-slim` + `pipx install ziglang` inside healthy's Dockerfile | Reintroduces exactly the toolchain-install complexity HC-007 is trying to delete. Also drifts from forge's "every forge-tracked image builds from a forge builder" pattern. |
| Zig-via-`pipx` on top of the forge base (hybrid) | Owns two sources of Zig in one image build. If the forge base's Zig ever disagrees with healthy's pinned Zig at build time, the hybrid obscures the mismatch instead of failing loudly. |
| Multi-stage build inside `scripts/build.sh` directly (no Dockerfile) | Confuses the roles. `scripts/build.sh` is for local dev; the Dockerfile is for the image. Keeping them separate but reused via `COPY scripts/build.sh` is the right shape. |
| Delete `scripts/build.sh` entirely once the Dockerfile builds in-image | Local `make check` / `make cross` depend on it for speed + 5-target coverage + `make size` budget check. The script stays; the Dockerfile wraps it. |
| QEMU-emulate the builder stage for arm64 builds | Measured on comparable projects: 5–10× slower than cross-compiling inside an amd64 builder. Zig's built-in cross-compile handles the arch dimension cleanly. |
| Delete `scripts/build.sh`-inside-image, inline `zig build-exe …` in the Dockerfile RUN | Drifts against the script — any future flag change would need to land in two places. The `-M` flag order lesson in `memory/zig-pitfalls.md` is exactly the class of bug that lives here. |

## Breaking changes

- **Public contract**: no change. Binary shape, entrypoint, exit codes, size
  table, flag surface, URL schemes — all identical.
- **Downstream consumers** (forge FG-030/031, homelab): still
  `COPY --from=ghcr.io/bboortz/hc:<ver> /hc /hc`. New image digest
  (because the layer provenance changed), same tag. Consumers pinning
  by tag get the HC-007 image on the next `release.yml` dispatch
  without changes; consumers pinning by digest must re-pin.
- **`ARG HC_BIN` deleted** — only `test_HC_005_publish-ghcr-image.sh`
  depends on it, updated in the same PR. No external caller: HC-005's
  Dockerfile is the only place the arg was declared, and it's internal.
- **`.dockerignore` added** — purely subtractive; fails safe if a new
  file ever legitimately joins the build context (the developer gets
  "file not found" during `docker build`, fixes with one `!path` line).

## Rollout

- [ ] Forge publishes `zig-slim-trixie` with Zig 0.17.1 (Open Question §2 blocker)
- [ ] `ghcr.io/bboortz/forge-builder-zig-trixie` visibility flipped to **public**
- [ ] `Dockerfile` rewritten per §Design delta above
- [ ] `.dockerignore` added (allowlist shape)
- [ ] `.github/workflows/release.yml` — `publish-image` job slimmed (2 steps removed; 2 build-args renamed)
- [ ] `test/acceptance/test_HC_005_publish-ghcr-image.sh` — `ARG HC_BIN` → `ARG ZIG_TARGET`
- [ ] `test/acceptance/test_HC_007_build-from-source.sh` — 6 Gherkin scenarios
- [ ] `docs/CAPABILITIES.md` — new `image.builds-from-source` CAP
- [ ] `docs/stories/INDEX.md` — HC-007 row, status `shipped`
- [ ] `CHANGELOG.md` — `### Added (HC-007)` entry under current VERSION
- [ ] **Post-merge**: `release.yml` dispatch republishes `hc:0.1.0` (same tag,
      new digest; manifest list updates). Downstream consumers pinning by
      tag get HC-007-built binary on next pull.

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (story §8) | Test pointer | Status |
|---|---|---|
| Multi-stage Dockerfile (builder + scratch runtime) | `test/acceptance/test_HC_007_build-from-source.sh` (S1) | pending |
| Builder stage uses forge's Zig | same file (S2) | pending |
| Local docker build from fresh checkout works | same file (S3, docker-gated) | pending |
| Published image size unchanged | same file (S4) | pending |
| release.yml publish-image job slimmed | same file (S5) | pending |
| HC-005's test updated | same file (S6) | pending |

### Lens 2 — Behaviour symmetry

| CAP | ≥ 1 test? | Status |
|---|---|---|
| `image.builds-from-source` | ✅ (S1 + S2 + S3) | pending |
| `workflow.publish-ghcr-image` (extended) | ✅ (S5) | pending |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys §7 — no SBOM, no cosign, no multi-arch-via-QEMU, no scripts/build.sh removal | pending |
| New CAP in §9 is in `docs/CAPABILITIES.md` | pending |
| `make check` green on this branch | pending |
| `make verify-traceability` green | pending |
| Size budget untouched (±5%) | pending |
| Zig version pin in Dockerfile matches `memory/project.md` | pending (blocked on Open Question §2) |

## Post-merge notes

First HC story to depend on a sibling-project artifact (forge FG-072's
`forge-builder-zig-trixie`). Cross-repo coordination worked — forge
published the base image pre-flight, the Zig bump followed, and healthy
picked it up without code change beyond the Dockerfile shape. The
pattern (forge publishes builder bases per language, healthy's
Dockerfile `FROM` them) is directly reusable for any future
healthy-adjacent tool that needs a forge-signed build toolchain.

Three gotchas worth remembering next time:
1. **ARG → RUN env propagation.** Zig ARG values are substituted into
   RUN commands as `${VAR}` expansions, but the forked `/bin/sh` that
   actually runs the command doesn't inherit the ARG as an env var.
   Pre-flight caught this: `build.sh` silently used its default
   `TARGET=x86_64-linux` instead of the aarch64 we wanted. Fix is
   explicit `TARGET=${ZIG_TARGET}` prefix on the RUN command.
2. **Comment text in `release.yml` triggered an absence assertion.**
   My explanatory comment inside the publish-image job mentioned the
   removed step names ("Install Zig 0.17.1 via pipx", etc.) for
   historical context; HC-007's acceptance test's `assert_absent_in_
   publish` matched them. Two fixes together: scope the assertion to
   `- name:` lines (step headers, not comments) *and* rephrase the
   comment to not include the removed step names.
3. **Runtime-stage invariants had to be rescoped.** HC-005's test used
   bare `assert_absent_in_file '^RUN '` because the single-stage
   Dockerfile had no legitimate `RUN`. HC-007 adds a builder stage
   that legitimately uses `RUN`/`WORKDIR`. HC-005's invariants
   (no shell/RUN/USER/WORKDIR in runtime) still hold — they just need
   an awk range (`/^FROM scratch/,0`) to scope to the runtime slice.

Open follow-ups (own stories):
- **HC-008 candidate**: SBOM emission. The forge builder already ships
  `/usr/local/bin/syft`; one RUN step would catalog the source +
  builder stage into `/sbom.json`, runtime-COPY it in. Matches
  beaconry-hub's BC-096 pattern.
- **HC-009 candidate**: cosign keyless OIDC signing. Now that the
  image provably builds from source, a cosign signature attests to
  the full build chain (Dockerfile + hc.zig + forge base), not just
  "some binary we received."
- riscv64 / arm/v7 / 386 image variants when a consumer asks.
