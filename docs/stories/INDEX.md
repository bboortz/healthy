# Story Index — healthy

One line per story. Keep sorted by HC id. Status: `draft → ready → in-progress → shipped`.

| ID | Status | Slug | Title |
|---|---|---|---|
| HC-001 | shipped | [dd-tgd-bootstrap](HC-001-dd-tgd-bootstrap.md) | DD-TGD bootstrap: process + layout |
| HC-002 | shipped | [ci-dev-main-promotion](HC-002-ci-dev-main-promotion.md) | CI pipeline + dev/main promotion |
| HC-003 | shipped | [robust-release-pipeline](HC-003-robust-release-pipeline.md) | Robust release pipeline (jq filter + fixture tests) |
| HC-004 | shipped | [usage-patterns-docs](HC-004-usage-patterns-docs.md) | Usage-patterns docs (Docker/K8s/Ansible) |
| HC-005 | shipped | [publish-ghcr-image](HC-005-publish-ghcr-image.md) | Publish hc as multi-arch GHCR image |
| HC-006 | shipped | [idle-mode](HC-006-idle-mode.md) | `hc idle` sigwait sentinel for PID 1 |
| HC-007 | shipped | [build-from-source](HC-007-build-from-source.md) | Dockerfile builds `hc` from source via forge builder (FG-072) |
| HC-008 | in-progress | [shepherd-poc](HC-008-shepherd-poc.md) | Shepherd POC (Release 0) on `healthy` |
| HC-009 | shipped | [sh019-contract-adoption](HC-009-sh019-contract-adoption.md) | Adopt shepherd dev-cycle contract (reference impl) |
| HC-010 | shipped | [sh029-branching-convergence](HC-010-sh029-branching-convergence.md) | Adopt feat/* → dev → main convergence |
| HC-011 | shipped | [sh042-hook-tiers](HC-011-sh042-hook-tiers.md) | Adopt hook-commit + hook-push fleet tiers |
| HC-012 | shipped | [sh055-check-docs](HC-012-sh055-check-docs.md) | Adopt check-docs fleet-tier wrapper |
| HC-013 | in-progress | [sh056-verify-index-status](HC-013-sh056-verify-index-status.md) | Adopt shepherd verify-index-status script + check-docs wiring |

Templates: [`_template.md`](_template.md), [`_9-questions.md`](_9-questions.md).

Promotion rule: a row only moves to `ready` once the 9 questions have real answers and
at least one CAP id is named in question 9. Only `ready+` stories get a plan doc and a
branch.
