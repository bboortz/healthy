---
id: HC-007
slug: build-from-source
status: shipped
created: 2026-11-08
shipped: 2026-11-20
owner: @benni
---

# HC-007 — Build `hc` from source inside the Docker image (beaconry pattern)

## 1. Who is the consumer?

**Two distinct audiences, same mechanism**:

1. **The CI / release pipeline.** Today, `release.yml`'s `publish-image` job
   pre-builds `hc` for each arch on the runner (`pipx install ziglang`,
   `scripts/build.sh`), then runs `docker build` which COPYs the pre-built
   binary via `ARG HC_BIN`. Two steps, two pieces of state. The runner cares
   about Zig; the Dockerfile cares about a filename. HC-007 collapses both
   into a single `docker buildx build --push` — the Dockerfile IS the build.
2. **Forge, as a trust-chain consumer.** Forge's model (per the
   `beaconry-hub` and `python-scratch-trixie` Dockerfiles) is *"images built
   from sources inside a multi-stage Dockerfile, scanned, signed."* Right
   now `hc`'s image doesn't fit that pattern — the Dockerfile packages a
   binary built outside the image. After HC-007, `hc`'s image follows the
   same shape as every other forge-tracked image: Stage 1 builder with a
   known-good toolchain + the source tree; Stage 2 `FROM scratch` + COPYed
   artefact.

## 2. When does the story fire?

Every image publish (today: every `release.yml` dispatch). The step that
builds + pushes the per-arch image changes from a three-command dance
(`pipx install ziglang`, `scripts/build.sh`, `docker build`) to a single
`docker buildx build --push`.

Local `make check` and `make build` are **unchanged** — they still use
`scripts/build.sh` directly for speed and for the five cross-targets that
the image publishes don't cover (riscv64, arm/v7, 386).

## 3. What does success look like?

Observable:

- A fresh `git clone` + `docker build -t hc:local .` produces a working
  scratch image containing `/hc`. The only network dependency is pulling
  `ghcr.io/bboortz/forge-builder-zig-trixie:latest` for the builder
  stage — no apt, no pipx, no PyPI inside healthy's Dockerfile.
- `docker run --rm hc:local https://benni.tech/ -k` exits 0. The binary
  inside the image **is the output of Zig 0.17.1 compiling `hc.zig`**, not
  a file carried in via build-arg.
- The Dockerfile's builder stage **`FROM
  ghcr.io/bboortz/forge-builder-zig-trixie:latest`** — forge's dedicated
  Zig-capable builder image (published 2026-11-08). Zig 0.17.1 pinned
  inside that base; the healthy repo no longer owns the toolchain
  install. Matches the pattern `beaconry-hub` uses with
  `forge-builder-python-trixie`.
- The published image size is **unchanged** (~405 KB — the binary is
  what it is; the builder stage contributes zero bytes to the final image
  because `FROM scratch` + `COPY --from=builder /hc /hc` discards everything
  else).
- `release.yml`'s `publish-image` job drops its `Install Zig 0.17.1 via
  pipx` and `Build amd64 + arm64 binaries via scripts/build.sh` steps,
  replaced by a single `docker buildx build --push` per arch. Net job
  time: roughly unchanged (shifted from runner → builder container, saves
  pipx-install cold-start time, loses layer cache for apt/pipx steps;
  wash).
- The `ARG HC_BIN` input from HC-005 is **removed** — the Dockerfile no
  longer accepts a pre-built binary. The acceptance test for HC-005 is
  updated in the same PR (grep `ARG HC_BIN` → grep `ARG ZIG_TARGET`).

## 4. How urgent?

**Correctness + quality-of-life.** Not a bug; the current pipeline ships.
But every security audit of a forge-consumed image eventually asks *"show
me the Dockerfile that produced this binary from source"* — right now the
answer for `hc` is awkward (`Dockerfile says COPY from build-arg; the
build-arg points at a file `scripts/build.sh` produced; `scripts/build.sh`
is reproducible`). After HC-007, the Dockerfile answers that question
directly: *"stage 1 builds `hc.zig` with Zig 0.17.1, stage 2 is scratch +
the binary."* One file, self-evident.

## 5. Happy path

```sh
# Local one-shot build from source:
$ git clone https://github.com/bboortz/healthy && cd healthy
$ docker build -t hc:local .
$ docker run --rm hc:local https://example.com -k    # exit 0

# CI publish job (release.yml excerpt, post-HC-007):
- name: Build + push amd64 from source
  run: |
    docker buildx build \
      --platform linux/amd64 \
      --build-arg ZIG_TARGET=x86_64-linux \
      --tag "$IMAGE:${{ steps.tags.outputs.version }}-amd64" \
      --push \
      .

- name: Build + push arm64 from source
  run: |
    docker buildx build \
      --platform linux/arm64 \
      --build-arg ZIG_TARGET=aarch64-linux \
      --tag "$IMAGE:${{ steps.tags.outputs.version }}-arm64" \
      --push \
      .
```

No `pipx install ziglang` on the runner. No `scripts/build.sh` invocation.
No `ARG HC_BIN`.

## 6. Edge cases / failure modes that matter

- **Zig version drift.** Builder stage pins `ziglang==0.17.1` exactly.
  A future floating version would silently change ABI behaviour (see
  `memory/zig-pitfalls.md § API churn`). Pin, don't float.
- **Builder platform vs runtime platform.** Zig cross-compiles cleanly on
  an amd64 builder to any target. The Dockerfile pins the builder stage
  to `--platform=linux/amd64` so cross-arch image builds don't trigger
  QEMU-emulated apt + pipx (which would be minutes per arch). The runtime
  `FROM scratch` inherits the buildx `--platform` setting, which matches
  the compiled binary's arch.
- **Builder base pick.** `ghcr.io/bboortz/forge-builder-zig-trixie:latest`
  (forge-maintained, published 2026-11-08). Analogue of
  `forge-builder-python-trixie` used by `beaconry-hub`. Zero apt /
  pipx state in healthy's own Dockerfile — the forge base owns Zig
  0.17.1 + CA certs + any other toolchain prereqs. When forge bumps its
  Zig base to a newer minor, healthy picks it up on the next daily cron
  rebuild (same cadence as beaconry-hub's Python minor bumps).
- **Forge builder image visibility.**
  `ghcr.io/bboortz/forge-builder-zig-trixie` must be **public** on GHCR
  so healthy's CI can pull it without authentication. Currently private
  (`docker pull` returns `denied` — same situation `hc:0.1.0` was in
  pre-flip). One-time fix: flip visibility to public in the GHCR
  package settings. Documented here so the merge of HC-007 doesn't
  fail at `docker build`-pulls-forge-base time.
- **Builder stage cache.** `docker buildx` caches apt + pipx steps across
  builds via the GHA cache backend (same mechanism beaconry uses). Cold
  first build ~45 s; warm ~5 s. CI is fine either way.
- **`COPY hc.zig` + `COPY scripts/build.sh`**. The builder stage preserves
  the directory structure (`/src/hc.zig` + `/src/scripts/build.sh`) so
  that `build.sh`'s `here=$(…)/scripts; repo=$(…)/..; -Mroot="$repo/hc.zig"`
  resolves correctly. Flattening both into `/src/` would break
  `-Mroot`.
- **`.dockerignore`.** Needs to allow `hc.zig` and `scripts/build.sh`,
  block `bin/` (otherwise 400 KB of pre-built binaries get copied into the
  build context for no reason). One tight allowlist.
- **`ARG HC_BIN` removal** — HC-005's acceptance test asserts the
  Dockerfile declares `ARG HC_BIN`. The HC-005 test gets updated in
  HC-007's PR (grep for `ARG ZIG_TARGET` instead).
- **Published image layer digest changes.** Even if the binary is
  bit-identical, the manifest digest changes because the image now has
  no builder stage in its lineage. Downstream consumers pinning by
  manifest digest (vs by tag) must re-pin. We've already noted this in
  HC-005: pin by tag (`:0.1.0`) for stability, pin by digest only when
  reproducibility is critical.

## 7. Out of scope

- **SBOM generation** (syft in the builder stage). Natural follow-up
  (HC-008 candidate). Would require installing syft in the builder or
  switching to forge's `forge-builder-*-trixie` base. HC-007 is the
  precondition; doing both together bloats the PR.
- **Cosign keyless OIDC signing** of the published image. The PR I'd
  earlier earmarked as HC-007 (cosign) shifts to HC-009 — unchanged
  scope, new number.
- **Multi-arch in a single buildx step** via QEMU emulation of the
  builder. Current pattern (one build per arch, then manifest list)
  stays — zero QEMU, zero cross-compile-via-emulation overhead.
- **Switching to a forge-maintained builder base**
  (`forge-builder-zig-trixie`). Forge's call to publish that image; when
  it exists, HC-007-follow-up swaps one line.
- **Removing `scripts/build.sh`.** Local `make check` + `make cross`
  still use it directly for speed + 5-target coverage + `make size`
  budget check. The script stays as the authoritative local build;
  the Dockerfile wraps it.
- **Bumping Zig.** HC-007 pins to 0.17.1, exactly matching
  `memory/project.md`. A Zig bump is its own `chore/zig-<version>` PR.

## 8. Acceptance (Gherkin → shell assertions)

```gherkin
Scenario: Dockerfile is multi-stage (builder + scratch runtime)
  Then Dockerfile declares exactly two `FROM` instructions
  And  the first FROM targets ghcr.io/bboortz/forge-builder-zig-trixie AS builder
  And  the second FROM targets scratch
  And  the final stage does NOT declare `ARG HC_BIN`
  And  the final stage COPIes `/hc` from the builder stage

Scenario: Builder stage uses forge's Zig 0.17.1 base (no local pipx)
  Then the builder stage does NOT run `pipx install` or `apt-get install`
       (the toolchain comes from the forge base image)
  And  `zig version` inside the builder returns 0.17.1

Scenario: Local `docker build .` from a fresh checkout works
  Given docker is available
  And   a git checkout of the healthy repo
  When  I run `docker build -t hc-test:hc007 .`
  Then  the build succeeds without a pre-built binary in the context
  And   `docker run --rm hc-test:hc007 -k https://benni.tech/` exits 0
  And   `docker export` of a created container yields exactly one regular
        file at the root of the archive, named `hc`

Scenario: Published image size unchanged
  When  I inspect the resulting image
  Then  Size is between 395_000 and 415_000 bytes
        (unchanged within ±5% of HC-005's ~404 KB)

Scenario: release.yml's publish-image job dropped the pipx + build.sh steps
  Then .github/workflows/release.yml does NOT contain
       `Install Zig 0.17.1 via pipx` inside the publish-image job
  And  does NOT contain `TARGET=x86_64-linux  scripts/build.sh` inside the
       publish-image job
  And  the `docker buildx build` steps pass `--build-arg ZIG_TARGET=` not
       `--build-arg HC_BIN=`

Scenario: HC-005's test updated for the new build-arg surface
  Then test/acceptance/test_HC_005_publish-ghcr-image.sh asserts
       `ARG ZIG_TARGET` instead of `ARG HC_BIN`
```

## 9. Capabilities delivered or extended

- **`image.builds-from-source`** (new) — The published `hc` image is produced by a multi-stage Dockerfile whose builder stage compiles `hc.zig` with Zig 0.17.1 inside the image. `docker build .` from a fresh git checkout + a Dockerfile-only input context produces a functionally equivalent image to what CI publishes. No pre-built binary enters the build context; no `ARG HC_BIN` input. Matches forge's "image built from sources" trust contract.
- **Extends `workflow.publish-ghcr-image`** — the publish-image job's two build-prep steps (`Install Zig 0.17.1 via pipx` + `Build amd64 + arm64 binaries via scripts/build.sh`) are replaced by `docker buildx build`'s own builder-stage execution. Same output, fewer runner-side primitives.

## Relationship to other stories

- **Supersedes HC-005's `ARG HC_BIN` contract.** HC-005's test is updated in the HC-007 PR; the "ARG HC_BIN exists" assertion becomes "ARG ZIG_TARGET exists." HC-005's `image.scratch-single-file` CAP is unchanged — the output image shape is identical, only the *mechanism* producing it changes.
- **Deferred to HC-008 (candidate)**: SBOM generation in the builder stage (`syft dir:/src -o syft-json=/sbom.json`), runtime `COPY --from=builder /sbom.json /sbom.json`. Matches `beaconry-hub` BC-096.
- **Deferred to HC-009 (renumbered from prior HC-007 placeholder)**: cosign keyless OIDC signing of the published image. Unblocked once the image genuinely builds from source (HC-007) so a signature attests to the build inputs + Dockerfile, not an opaque pre-built binary.
- **Enables / aligns with forge FG-031**. Forge's `healthy-scratch-trixie:3` will `COPY --from=ghcr.io/bboortz/hc` an image that genuinely *was* built from source. Forge's audit answer stops being "trust `scripts/build.sh`" and starts being "trust the published Dockerfile."

## Open questions — all resolved 2026-11-20

1. **Builder base** — ✅ `ghcr.io/bboortz/forge-builder-zig-trixie:latest` (forge FG-072, public, Zig 0.17.1 verified).
2. **Zig version mismatch** — ✅ forge bumped `zig-slim-trixie` to Zig 0.17.1 (Path A from the earlier analysis). Pre-flight smoke confirmed both amd64 and aarch64 cross-compile produce correct binaries inside this story's planned Dockerfile shape.
3. **Remove `ARG HC_BIN`** — ✅ clean break. HC-005's `ARG HC_BIN` deleted; HC-007 introduces `ARG ZIG_TARGET` with a default of `x86_64-linux`. HC-005's acceptance test updated in the same PR.
4. **`.dockerignore` shape** — ✅ allowlist. `*` then `!hc.zig`, `!scripts/build.sh`. Build-context minimalism; forces a reviewer to see any new file that joins the build context.
