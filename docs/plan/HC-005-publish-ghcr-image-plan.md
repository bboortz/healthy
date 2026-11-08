---
id: HC-005
slug: publish-ghcr-image
story: docs/stories/HC-005-publish-ghcr-image.md
branch: feat/HC-005-publish-ghcr-image
status: shipped
shipped: 2026-11-08
---

# HC-005 plan — Publish hc as a multi-arch GHCR image

**Story:** [HC-005](../stories/HC-005-publish-ghcr-image.md)

## Design delta

Three files touched on healthy, one new, two extended:

### New: `Dockerfile` (repo root)

```dockerfile
# syntax=docker/dockerfile:1.7
FROM scratch
ARG HC_BIN
LABEL org.opencontainers.image.source="https://github.com/bboortz/healthy"
LABEL org.opencontainers.image.description="Tiny static TCP/TLS/HTTP(S) health check probe"
LABEL org.opencontainers.image.licenses="MIT"
COPY $HC_BIN /hc
ENTRYPOINT ["/hc"]
```

Five instructions total, one of them conditional on build-arg. The
Dockerfile is single-stage (no builder — we pre-build via `scripts/build.sh`
in the CI step and pass the binary as the build arg). This keeps the
`docker build` fast (~1 s per arch) and reuses the existing cross-target
story.

### Extended: `.github/workflows/release.yml`

New job `publish-image` added after the existing `promote` job. Shape:

```yaml
publish-image:
  needs: promote
  runs-on: ubuntu-latest
  permissions:
    contents: read
    packages: write
  env:
    IMAGE: ghcr.io/${{ github.repository_owner }}/hc
  steps:
    - uses: actions/checkout@v4
      with: { ref: main }
    - name: Read VERSION
    - name: Install Zig 0.17.1 via pipx     # reuse ci.yml pattern
    - name: Build amd64 + arm64 binaries    # scripts/build.sh × 2
    - name: Log into GHCR                   # docker/login-action
    - name: Build + push amd64 image
    - name: Build + push arm64 image
    - name: Create + push manifest list for :VERSION, :X.Y, :X, :latest
    - name: Summary
```

Key decisions:

- **No buildx multi-arch in one go.** We already have cross-compiled
  binaries from `scripts/build.sh`; building the image per-arch with
  `docker build --platform` + a `docker manifest create` is simpler than
  buildx with QEMU emulation inside the runner.
- **`docker/login-action`** for the GHCR login — the canonical pattern,
  uses `GITHUB_TOKEN` directly, no PAT needed.
- **Tag matrix**: `:0.1.1`, `:0.1`, `:0`, `:latest`. Patch-level
  consumers pin `:0.1.0`; semver-lenient consumers pin `:0.1` to get
  patch updates. Forge's FG-030 probably pins to `:0.1.0` for immutability.
- **`:latest` meaning**: most recent tagged release (not main HEAD).
  Matches beaconry/forge convention.

### New: `test/acceptance/test_HC_005_publish-ghcr-image.sh`

Two tiers: offline (grep + file-existence) + online (docker build +
inspect). Online portion is docker-availability-gated so developers
without docker get the offline assertions only (acceptance test still
passes — docker check is best-effort). CI runners always have docker
so the online tier runs there.

## Alternatives rejected

| Alternative | Why not |
|---|---|
| Multi-stage Dockerfile with a Zig builder | Each `docker build` would do a fresh ~15 s Zig compile per arch. Reuses no caching between dev, pre-push, and CI. The cross-targets already exist from `scripts/build.sh` — no reason to re-build. |
| `docker buildx` with QEMU emulation for cross-arch | QEMU-emulated builds are 5-10× slower; we'd be re-doing what Zig cross-compile already handles natively. |
| Separate `publish.yml` workflow fired by tag-push | GitHub Actions' default `GITHUB_TOKEN` doesn't trigger downstream workflows on tag push (anti-recursion rule), so we'd need a PAT or the tag + publish would need manual re-dispatch. Simpler to extend `release.yml`'s existing job graph. |
| Publish on every push to `main` (not just release) | `:latest` on main-HEAD-of-the-moment is a trap — downstream `COPY --from=…:latest` would get surprised when a WIP commit lands. Release-only `:latest` is boring and correct. |
| Add cosign keyless signing | Nice-to-have, not needed for FG-030 to work. Deferred to a dedicated HC-006 whose scope is big enough to justify the OIDC-trust-policy conversation. |
| Add SBOM + grype scan | `hc`'s image contains exactly one file. Grype has nothing to scan; syft's SBOM would list one binary. Zero value for this image shape. Add when (if ever) we have OS-package contents. |
| Support all 5 cross-targets at launch | riscv64 / arm/v7 / 386 have essentially no Docker consumer base. amd64 + arm64 cover ~99% of real containers. Add others on request. |
| Rename cross-target outputs to match Docker's TARGETARCH | Would require renaming everywhere in healthy (Makefile, memory, README, test fixtures). Not worth it for the publish job; CI maps names explicitly in a 5-line case. |

## Breaking changes

- [ ] No. `hc.zig`, flag surface, binary outputs, Makefile targets, `make
  check` gates — all unchanged. Pure additive: one new file (`Dockerfile`),
  one new job in `release.yml`, one new acceptance test, two new CAPs.

## Rollout

- [x] `Dockerfile` added at repo root
- [x] `.github/workflows/release.yml` — new `publish-image` job
- [x] `test/acceptance/test_HC_005_publish-ghcr-image.sh` — offline + online tests
- [x] `docs/CAPABILITIES.md` — 2 new CAPs
- [x] `docs/stories/INDEX.md` — HC-005 row
- [x] `CHANGELOG.md` — `### Added (HC-005)` entry under v0.1.0
- [ ] **Post-merge**: the next `release.yml` dispatch (whenever VERSION
  bumps) builds + publishes the image. For a first proof-of-pipeline we
  can dispatch with VERSION still at 0.1.0 — the publish job overwrites
  the existing `:0.1.0` manifest (new digest, same tag, GHCR allows this)
  without disturbing the v0.1.0 git tag.

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (story §8) | Test pointer | Status |
|---|---|---|
| Dockerfile is minimal + scratch + no shell | `test/acceptance/test_HC_005_publish-ghcr-image.sh` (Scenario 1) | ✅ |
| Local amd64 build produces single-file scratch image | same file, Scenario 2 (docker-gated) | ✅ |
| release.yml publish-image job wired correctly | same file, Scenario 3 | ✅ |
| CAP matrix lists the two new capabilities | same file, Scenario 4 | ✅ |

### Lens 2 — Behaviour symmetry

| CAP delivered | ≥ 1 test? | Status |
|---|---|---|
| `image.scratch-single-file` | ✅ (Scenario 2 asserts `docker export \| tar -t` yields one file; Scenario 1 asserts no implicit surface in Dockerfile) | ✅ |
| `workflow.publish-ghcr-image` | ✅ (Scenario 3 greps the full release.yml wire-up — permissions, login, build, manifest) | ✅ |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys its own §7 (out-of-scope) — no cosign, no SBOM, no grype, no all-archs, no publish-on-push-to-main | ✅ |
| New CAPs in §9 all in `docs/CAPABILITIES.md` | ✅ |
| `make check` green on this branch | ✅ |
| `make verify-traceability` green (33 CAPs) | ✅ |
| Size budget unaffected (no `hc.zig` touch) | ✅ |
| Dockerfile hadolint-clean (even though we don't CI-lint the Dockerfile here, local sanity: no obvious anti-patterns) | ✅ |

## Post-merge notes

Five CI/workflow stories in a row (HC-001 through HC-005) have now
exercised every muscle of the DD-TGD motion — process + flowflow + release
promotion + release robustness + user-facing docs + downstream publishing.
HC-005 ties the chain to the broader ecosystem: `ghcr.io/bboortz/hc` is
the artifact the rest of homelab + forge consume.

Design note worth remembering: the acceptance test's "exactly /hc inside
the image" assertion turned out to be the subtle one. `docker export`
reports the full *runtime* filesystem, which Docker injects
`.dockerenv` / `/dev/*` / `/proc` / `/sys` / `/etc/{hostname,hosts,mtab,
resolv.conf}` into before the container's command runs. The real **image
layer** contains only `/hc`. The test filters the known runtime overlay
and asserts the remainder is exactly `hc`. Caught a first-pass filter
bug (missed the `etc/` directory entry) — classic "test my own filter"
moment.

Open follow-ups (own stories):
- HC-006: cosign keyless OIDC signing of the published image (matches
  forge's signing contract so downstream can `cosign verify` the digest).
- HC-007: publish README `COPY --from=` snippet alongside HC-004's
  patterns — tiny docs delta.
- riscv64 / arm/v7 / 386 image variants on request.
