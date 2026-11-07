*The nine canonical clarification questions asked for every new story in `healthy`. Copy these into `docs/stories/HC-NNN-<slug>.md` before promoting to `ready`.*

1. **Who** is the consumer in this moment?
   Container image author / healthcheck operator / downstream Dockerfile author / Forge
   consumer embedding `hc`. Pick one. If more than one, split the story.

2. **When** does the story fire?
   Docker runtime invokes `hc` as HEALTHCHECK / CI builds a minimal image / operator debugs
   a failing probe / maintainer bumps Zig / …

3. **What** does success look like?
   Observable outcome. Exit code, stderr line, size on disk, specific URL scheme accepted.
   Must be mechanically checkable — a human judgement call doesn't belong here.

4. **How urgent?** Impact tier:
   - security-critical (CVE, auth bypass, cert-check regression)
   - correctness (wrong exit code for a given input)
   - quality-of-life (new flag, better error message)
   - size (binary budget, cross-target support)

5. **Happy path** — exact sequence of flags + URL + expected exit code?

6. **Edge cases / failure modes** that matter?
   Hung server (watchdog), wrong CA, wrong hostname, bad status, IPv6 literal, network
   unreachable, oversized response body, …

7. **Out of scope** — what could creep in but shouldn't?
   Default-out: HTTP/2, chunked transfer, redirect following, cookies, retries, DNS
   caching, config files, metrics output. If this story relaxes one of those defaults,
   say so explicitly.

8. **How do we know it's done?** Acceptance = Gherkin.
   Every Scenario encodes as one or more `t <rc> "$HC" …` lines in
   `test/acceptance/test_HC_NNN_<slug>.sh`.

9. **What capabilities does this story deliver or extend?**
   Name new CAP ids; link to existing ones. The capability matrix
   (`docs/CAPABILITIES.md`) is the source of truth — update it in the same PR.
