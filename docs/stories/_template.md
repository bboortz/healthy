---
id: HC-NNN
slug: short-kebab
status: draft        # draft → ready → in-progress → shipped
created: YYYY-MM-DD
owner: @benni
---

# HC-NNN — <one-line title>

## 1. Who is the consumer?

<Container image author / healthcheck operator / downstream Dockerfile author / Forge
consumer embedding `hc`. Pick one. If more than one, split the story.>

## 2. When does the story fire?

<Docker runtime invokes `hc` as HEALTHCHECK / CI builds a minimal image / operator debugs
a failing probe / maintainer bumps Zig / …>

## 3. What does success look like?

<Observable outcome. Exit code, stderr line, size on disk, specific URL scheme accepted.
Must be mechanically checkable — a human judgement call doesn't belong here.>

## 4. How urgent?

- [ ] Security-critical (CVE, auth bypass, cert-check regression)
- [ ] Correctness (wrong exit code for a given input)
- [ ] Quality-of-life (new flag, better error message)
- [ ] Size (binary budget, cross-target support)

## 5. Happy path

```
<Exact command the consumer runs. Include the flags and the URL. Include the expected
exit code and whether anything is printed to stderr.>
```

## 6. Edge cases / failure modes that matter

- <Hung server (the `-t` watchdog must fire in bounded time)>
- <Wrong CA (exit 1, stderr mentions verification)>
- <Wrong hostname SAN (exit 1)>
- <Bad status outside `-s` range (exit 1)>
- <IPv6 literal in URL authority>
- <…>

## 7. Out of scope

<What someone reading this story might assume is included but isn't. Default-out items:
HTTP/2, chunked transfer, redirect following, cookies, retries, DNS caching, config
files, metrics output. If this story relaxes one of those defaults, say so explicitly.>

## 8. Acceptance (Gherkin → shell assertions)

```gherkin
Scenario: <name>
  Given <precondition — server state, build flavour>
  When  <invocation of hc with specific flags>
  Then  <observable: exit code, stderr contents, elapsed time>

Scenario: <second>
  …
```

The acceptance test lives at `test/acceptance/test_HC_NNN_<slug>.sh` and encodes each
Scenario as one or more `t <rc> "$HC" …` lines (same helper as `test/run.sh`).

## 9. Capabilities delivered or extended

- `cap.id.name` — <one-line description; new or extended>
- …

New CAP ids go into `docs/CAPABILITIES.md` in the same PR. Every CAP needs a bidirectional
link to its acceptance test (`make verify-traceability` enforces this).

---

## Plan doc

Lives at `docs/plan/HC-NNN-<slug>-plan.md`. Created when the branch is cut (status
`ready → in-progress`). Captures the design delta, alternatives rejected, breaking
changes, rollout, and — at step 6a — the Shipping evidence table.
