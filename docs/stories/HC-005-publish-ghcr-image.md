---
id: HC-005
slug: publish-ghcr-image
status: shipped
created: 2026-11-08
shipped: 2026-11-08
owner: @benni
---

# HC-005 — Publish hc as a multi-arch GHCR image

## 1. Who is the consumer?

**Downstream container-image maintainers who `COPY --from=…` the `hc` binary
into their own scratch images.** Immediate first customer:
`bboortz/forge`'s FG-030 (`healthy-scratch-trixie` v2 — replacing wget +
GnuTLS with `hc` to collapse 24 MB → ~1.5 MB). Secondary: anyone building
`FROM scratch` images in homelab who wants a healthcheck probe without
dragging `python3`/`curl`/`wget`/`nc` into their closure.

## 2. When does the story fire?

Every time `release.yml` is dispatched with a version bump. The existing
promotion step already fast-forwards `main` and tags `v<VERSION>`; HC-005
adds a new step that builds `hc` for the targeted architectures, builds a
multi-arch container image, and publishes it to `ghcr.io/bboortz/hc`
under the versioned and moving tags.

For `:latest` to make sense, the tag matches "most-recent tagged release"
(not "latest main HEAD"). That's the industry convention and matches
beaconry's model.

## 3. What does success look like?

Observable at merge time + after the next `release.yml` dispatch:

- A file `Dockerfile` exists at the repo root, shaped: `FROM scratch` + one
  `ARG HC_BIN` + one `COPY` + one `ENTRYPOINT ["/hc"]`. No builder stage, no
  shell, no `CMD-SHELL`, no implicit metadata beyond OCI labels.
- `docker build --build-arg HC_BIN=bin/hc-x86_64-linux -t hc:test .`
  produces an image whose root filesystem contains exactly **one file:
  `/hc`**. `docker export` of the container yields a single entry in `tar
  -t`. Image uncompressed size matches the input binary within OCI-layer
  overhead (<4 KB).
- `.github/workflows/release.yml` grows a `publish-image` job that:
  - depends on the existing `promote` job
  - installs Zig 0.17.1 via pipx (same recipe as `ci.yml`)
  - runs `scripts/build.sh` for each supported arch (initially amd64 + arm64)
  - builds one single-platform image per arch, pushes it tagged
    `hc:<version>-<arch>`
  - creates a multi-arch manifest list under `hc:<version>`, `hc:<major>.
    <minor>`, `hc:<major>`, `hc:latest`
  - pushes all tags
- After one real dispatch, the image is pullable as
  `docker pull ghcr.io/bboortz/hc:0.1.1` (or whichever version comes next)
  and `COPY --from=ghcr.io/bboortz/hc:0.1.1 /hc /hc` works in a downstream
  scratch Dockerfile.
- The acceptance test for HC-005 can run its `docker build` + inspection
  checks entirely offline (no push). The actual GHCR push is CI-only and
  covered by the next real `release.yml` dispatch.

## 4. How urgent?

**Correctness + unblocker.** forge's FG-030 is blocked on this —
`COPY --from=ghcr.io/bboortz/hc` requires the image to exist. Not
security-critical; functionally blocking.

## 5. Happy path

```sh
# Maintainer side (after HC-005 merges and VERSION bumps to 0.1.1):
# Open GitHub Actions → Release → Run workflow with ref=dev
# → promote job FFs main from dev, tags v0.1.1
# → publish-image job builds amd64 + arm64, pushes to GHCR
# → ghcr.io/bboortz/hc:0.1.1 / :0.1 / :0 / :latest all point at the manifest

# Downstream (forge/FG-030):
FROM scratch
COPY --from=ghcr.io/bboortz/hc:0.1.1 /hc /hc
# … rest of consumer Dockerfile …
```

## 6. Edge cases / failure modes that matter

- **GHCR authentication**: the job uses the default `GITHUB_TOKEN` with
  `packages: write`. Must not fall back to an anonymous push (would 401).
- **Multi-arch manifest without a Docker-Hub buildx driver**: GitHub
  runners ship a working buildx; the job uses `docker/setup-buildx-action`
  and `docker/setup-qemu-action` only when actually needed for cross-build
  (not used here — we pre-build via Zig and docker only packages).
- **Zig cross-build fails on arm64**: already proven green in `make
  cross`. publish-image re-uses `scripts/build.sh` so the same code path is
  exercised.
- **Image size regression**: a build that produces an unexpectedly large
  image (e.g. accidentally including the repo as a layer) must fail.
  publish-image does a post-push `docker image inspect` and fails if the
  layer is >1 MB.
- **Tag collision**: if `v0.1.0` already exists on GHCR (it will — the
  bootstrap tag), the push must overwrite the manifest-list but preserve
  the underlying digests. GHCR permits this for tag re-pointing; verified
  by first-push failing and the operator re-dispatching cleanly.
- **Stale `:latest`**: if the promote job fails (e.g. CI-not-green), the
  publish-image job must not run. The existing `needs:` guard handles this.
- **Acceptance test needs docker**: the CI runner has docker; local
  developer may not. The acceptance test skips the docker portion
  gracefully if `docker` is not on PATH, running only the grep assertions
  against the Dockerfile + release.yml.

## 7. Out of scope

- **cosign signing** — deferred to HC-006 (opt-in). GHCR's native digest
  immutability is sufficient for v1; downstream can pin by digest if they
  want that guarantee today.
- **SBOM / grype scan** — `hc`'s scratch image contains one static ELF,
  zero OS packages. Grype would scan nothing; syft would produce an SBOM
  of one file. Both are no-ops for this image shape. Revisit if we add
  OS-package dependencies.
- **More than amd64 + arm64**. The 3 other cross-targets (riscv64, arm/v7,
  386) build locally today but have essentially no Docker-consumer base.
  Add on request.
- **Publishing on push to main** (vs only on tagged release). Matches
  beaconry/forge pattern: tags are explicit releases, not "latest commit."
- **README update for `COPY --from=…` pattern**. Can be folded into HC-004's
  Migrating section in a follow-up; HC-005 is strictly about the image
  existing.
- **Separate publish.yml workflow file**. Using release.yml's existing
  dispatch keeps "all release actions happen when the operator clicks Run
  workflow" as one atomic event.

## 8. Acceptance (Gherkin → shell assertions)

```gherkin
Scenario: Dockerfile is minimal, scratch-based, no shell/CMD-SHELL
  Then Dockerfile exists at the repo root
  And  Dockerfile's first instruction is "FROM scratch"
  And  Dockerfile sets ENTRYPOINT ["/hc"] (JSON exec form)
  And  Dockerfile does NOT contain CMD-SHELL / RUN / SHELL / USER / WORKDIR
  And  Dockerfile declares ARG HC_BIN
  And  Dockerfile has an OCI image-source label

Scenario: Local amd64 build produces a single-file scratch image
  Given docker is available
  And   bin/hc-x86_64-linux exists
  When  I run `docker build --build-arg HC_BIN=bin/hc-x86_64-linux -t hc-test:local .`
  Then  the build succeeds
  And   `docker export` of a created container yields exactly one regular file,
        named "hc", at the root of the archive
  And   `docker image inspect hc-test:local` reports Size <= 500000 bytes
  And   `docker inspect hc-test:local` reports Entrypoint = ["/hc"]

Scenario: release.yml's publish-image job is wired correctly
  Then .github/workflows/release.yml contains a `publish-image:` job
  And  the publish-image job has `needs: promote`
  And  the publish-image job declares `packages: write` permission
  And  the publish-image job logs into ghcr.io with the default GITHUB_TOKEN
  And  the publish-image job builds for linux/amd64 and linux/arm64
  And  the publish-image job creates and pushes a manifest list for
       `ghcr.io/${{ github.repository }}/hc:${VERSION}` and :latest aliases

Scenario: CAP matrix lists the new capabilities
  Then docs/CAPABILITIES.md contains `### image.scratch-single-file`
  And  docs/CAPABILITIES.md contains `### workflow.publish-ghcr-image`
  And  each has a `Covered by:` pointing at test_HC_005_publish-ghcr-image.sh
```

## 9. Capabilities delivered or extended

- `image.scratch-single-file` — `hc`'s published image is `FROM scratch` containing exactly one regular file (`/hc`) and nothing else. No CA bundle, no `/etc/passwd`, no empty dirs. Verified by `docker export | tar -t`.
- `workflow.publish-ghcr-image` — `release.yml` builds `hc` for amd64 + arm64, pushes a multi-arch manifest list to `ghcr.io/${{ github.repository }}/hc` under `:<version>`, `:<major>.<minor>`, `:<major>`, `:latest` after the `promote` job succeeds. Downstream consumers (`forge`, `homelab`) can `COPY --from=ghcr.io/bboortz/hc:<ver> /hc /hc` into their own scratch images.
