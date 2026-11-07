*Development workflow for `healthy`. Design-Driven, Test-Guarded (DD-TGD) — every observable change is traceable from a story, through a plan doc, to a red acceptance test, to the merged commit.*

## Quality bar

**Every public-contract change is traceable** back to the story that motivated it (`docs/stories/HC-NNN-<slug>.md`), the plan that scoped it (`docs/plan/HC-NNN-<slug>-plan.md`), and the red acceptance test that proves it (`test/acceptance/test_HC_NNN_<slug>.sh`). If any link is missing, the change is not shippable.

## Development process: DD-TGD

```
Per feature (HC-NNN):
0. Consult IDEAS backlog    docs/plan/IDEAS.md — not-yet-promoted ideas. New ideas
                            go in here immediately, even if we won't pick them up.
1. User-facing story        docs/stories/HC-NNN-<slug>.md
                            9 canonical questions → Gherkin acceptance + CAP list.
                            Status: draft → ready.
2. Branch + plan doc        feat/HC-NNN-<slug> from main
                            docs/plan/HC-NNN-<slug>-plan.md:
                              - Story link, design delta, alternatives rejected
                              - Breaking changes (CLI? exit codes? size budget?)
                              - Rollout (docs updates, downstream notice)
                              - Shipping evidence table (filled at 6a)
                            Story status → in-progress.
3. Red acceptance test      test/acceptance/test_HC_NNN_<slug>.sh
                            Gherkin as shell assertions against the built hc binary.
                            Top-of-file `Covers:` block names CAPs.
                            Must fail before implementation.
4. Implementation           Smallest change that turns the red test green.
5. Register capabilities    docs/CAPABILITIES.md — add or extend entries; bidirectional
                            links (CAP → test, test `Covers:` → CAP).
                            make verify-traceability must pass.
6. Gates                    make check — see matrix below.
6a. Pre-ship audit          Fill Shipping evidence table in the plan. Three lenses:
                              - Gherkin coverage (every Scenario → test pointer)
                              - Behaviour symmetry (every CAP → ≥1 test; every exit
                                code path → ≥1 test)
                              - Self-consistency (story obeys its own conventions)
                            Any ⚠️/❌ row blocks shipping — cycle back to step 4.
7. Update README            Only if the public contract changed.
8. PR → main → merge        Merge commit (not squash). Story → shipped on merge.
```

**Exceptions (no story required):**
- `fix/<slug>` with a clear repro — one-line fix, repro in commit body
- `refactor/<slug>` — acceptance tests prove behaviour invariance (run the full suite)
- `chore/<slug>` — Zig version bump, GHA tweak, dependency update, size-budget review
- `docs/<slug>` — README or `memory/` only
- `test/<slug>` — pure test addition against an existing CAP (add a pointer in `CAPABILITIES.md`)
- `ci/<slug>` — GitHub Actions only

**Definition of Done per HC-NNN:**
- [ ] Red acceptance test went green via implementation
- [ ] Capabilities registered + bidirectional links present
- [ ] `make check` green (lint + build ± TLS + test + cross + verify-traceability)
- [ ] Shipping evidence table has no ⚠️/❌ rows
- [ ] README updated if public contract changed
- [ ] Size budget still within ±5% (or justified in the PR body)

## Stories — layout, format, lifecycle

```
docs/stories/
  INDEX.md             — one-line status board (grep-friendly)
  _template.md         — canonical story template
  _9-questions.md      — the canonical clarification set
  HC-NNN-<slug>.md     — one file per story
```

Lifecycle: `draft → ready → in-progress → shipped` (frontmatter + INDEX).

**The 9 canonical clarification questions** (asked for every new story):

1. **Who** is the consumer? (container image author / healthcheck operator / downstream Dockerfile author / Forge consumer embedding `hc`)
2. **When** does the story fire? (docker runtime invokes healthcheck / CI builds image / operator debugs failing probe)
3. **What** does success look like? (observable: exit code, stderr line, size on disk, specific URL scheme accepted)
4. **How urgent?** (security-critical / correctness / quality-of-life / size)
5. **Happy path** — exact sequence of flags + URL + expected exit?
6. **Edge cases / failure modes** that matter? (hung server, wrong CA, wrong hostname, bad status, IPv6 literal)
7. **Out of scope** — what could creep in but shouldn't? (default: HTTP/2, redirects, cookies, retries — see `project.md`)
8. **How do we know it's done?** (acceptance = Gherkin → shell assertions in `test/acceptance/`)
9. **What capabilities does this story deliver or extend?** Name new CAP ids; link existing ones. Make the capability matrix explicit from story-time, not retroactively.

## Capability matrix

`docs/CAPABILITIES.md` is the source of truth for what `hc` can do, with bidirectional links to the acceptance tests. Example CAP ids:
`scheme.tcp`, `scheme.tls`, `scheme.http`, `scheme.https`,
`tls.verify-private-ca`, `tls.verify-hostname`, `tls.skip-with-k-flag`, `tls.embedded-ca`,
`http.status-range`, `http.body-match`, `http.host-header`,
`deadline.sigalrm-watchdog`, `build.cross-targets`, `build.tls-off`,
`binary.no-libc`, `binary.single-file`, `binary.size-budget`.

`make verify-traceability` enforces: every CAP has ≥1 test pointer; every acceptance test's `Covers:` block names only known CAPs; every `ready+` story has at least one CAP in question 9.

## Blocking gates (must pass to merge)

| Gate | Command | Where |
|---|---|---|
| Zig fmt | `zig fmt --check hc.zig` | pre-commit + CI (fast-check) |
| Shell lint | `shellcheck` on `scripts/*.sh`, `test/*.sh` | pre-commit + CI (fast-check) |
| Build (TLS on) | `make build` | pre-push + CI (full-check) |
| Build (TLS off) | `TLS=0 make build` | pre-push + CI (full-check) |
| Cross-targets | `make cross` | pre-push + CI (full-check) |
| Functional suite | `./test/run.sh` | pre-push + CI (full-check) |
| Acceptance | `make test-acceptance` | pre-push + CI (full-check) |
| Traceability | `make verify-traceability` | pre-commit + CI (fast-check) |
| Memory size | `memory/*.md` ≤ 150 lines; `CLAUDE.md` ≤ 150 lines | pre-commit |
| VERSION bump | `make verify-version-bumped` | pre-push |
| CHANGELOG entry | `make verify-changelog` | pre-push + CI (full + release) |
| Size budget | `make size` — within ±5% of README table | pre-push (advisory locally) |
| Commit format | `scripts/check-commit-msg.sh` (pre-commit's commit-msg stage) | local |

No advisory gates — if a check isn't worth blocking, it isn't worth running.

## Branch flow (HC-002)

- **`dev` is the integration branch.** All work branches off `dev`: `feat/HC-NNN-<slug>`, `fix/<slug>`, `refactor/<slug>`, `docs/<slug>`, `chore/<slug>`, `test/<slug>`, `ci/<slug>`.
- **`main` is CI-promoted-only.** Never push directly. Promotion happens via `.github/workflows/release.yml` on a manual `workflow_dispatch` — it asserts CI was green on `dev`, fast-forwards `main`, and tags `v<VERSION>`.
- PRs target `dev`. Merge commits (not squash) preserve the PR boundary.
- CI tiers mirror the branch roles: feature pushes → `fast-check`; `dev` pushes + PRs to `dev` → `full-check`; `main` pushes → `release-check`. See `.github/workflows/ci.yml`.

## Zig version bump

Its own `chore/zig-<version>` branch. See `memory/code-quality.md` and `memory/zig-pitfalls.md § API churn`. Treat the bump as a story only if it forces a public-contract change.
