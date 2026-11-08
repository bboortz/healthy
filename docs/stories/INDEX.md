# Story Index — healthy

One line per story. Keep sorted by HC id. Status: `draft → ready → in-progress → shipped`.

| ID      | Slug                | Title                                | Status       | Opened     | Shipped |
|---------|---------------------|--------------------------------------|--------------|------------|---------|
| HC-001  | dd-tgd-bootstrap    | DD-TGD bootstrap: process + layout   | shipped      | 2026-11-07 | 2026-11-07 |
| HC-002  | ci-dev-main-promotion | CI pipeline + dev/main promotion   | shipped      | 2026-11-07 | 2026-11-07 |
| HC-003  | robust-release-pipeline | Robust release pipeline (jq filter + fixture tests) | shipped      | 2026-11-08 | 2026-11-08 |
| HC-004  | usage-patterns-docs | Usage-patterns docs (Docker/K8s/Ansible) | shipped      | 2026-11-08 | 2026-11-08 |
| HC-005  | publish-ghcr-image | Publish hc as multi-arch GHCR image | shipped      | 2026-11-08 | 2026-11-08 |
| HC-006  | idle-mode | `hc idle` sigwait sentinel for PID 1 | shipped      | 2026-11-08 | 2026-11-08 |

Templates: [`_template.md`](_template.md), [`_9-questions.md`](_9-questions.md).

Promotion rule: a row only moves to `ready` once the 9 questions have real answers and
at least one CAP id is named in question 9. Only `ready+` stories get a plan doc and a
branch.
