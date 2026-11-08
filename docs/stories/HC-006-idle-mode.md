---
id: HC-006
slug: idle-mode
status: shipped
created: 2026-11-08
shipped: 2026-11-08
owner: @benni
---

# HC-006 — `hc idle`: keepalive mode for sidecar container PID 1

## 1. Who is the consumer?

**Forge consumer embedding `hc`.** Specifically Forge's `healthy-scratch-trixie`
image (FG-030 → FG-031), which uses `hc` as the healthcheck binary but currently
also carries `/usr/bin/sleep` + `libc.so.6` + `ld-linux` (~2.3 MB of overhead) just
to keep the sidecar container's PID 1 alive between docker healthcheck
invocations.

Downstream of Forge: 4 homelab stacks (`nextcloud/web-hc`, `sni-router/*-hc`,
`website/*-hc` × 2) that run the sidecar.

## 2. When does the story fire?

A scratch sidecar container boots. Docker requires PID 1 to stay alive for the
container to be "running" and for `HEALTHCHECK` exec probes to fire. The sidecar
has no shell, no `sleep`, and (post-HC-006) no libc. Something must block
forever on the sigset {TERM, INT}.

## 3. What does success look like?

Observable:

- `hc idle` blocks until `SIGTERM` or `SIGINT`, then exits 0.
- Zero CPU use while blocked (process is in `TASK_INTERRUPTIBLE` via signalfd
  read).
- Clean exit on `docker stop` within the default 10 s grace window.
- No new runtime deps: `hc idle` reuses the existing static single-file binary.
  No growth of the ~400 KB image.
- `hc idle <anything>` exits 2 (usage error) — the subcommand takes no args.
- The existing one-shot probe mode (URL form) is **unchanged**. All 28 cases
  of `test/run.sh` and all prior HC-NNN acceptance tests still pass.

Result for Forge: `healthy-scratch-trixie:3` collapses to pure `FROM scratch`
+ `COPY --from=ghcr.io/bboortz/hc /hc /hc` + `CMD ["/hc", "idle"]`. Image size:
~500 KB (currently 3.5 MB post-FG-030, 24 MB pre-FG-030). **Smaller than
BusyBox by ~8×** instead of the current 1.2×.

## 4. How urgent?

**Size + quality-of-life + security surface.** Not a bug. Enables FG-031 in
Forge which:
- shrinks the signed sidecar from 3.5 MB → ~500 KB (~7× further reduction),
- eliminates the entire `libc` attack surface from the image closure,
- removes the "why does this sidecar ship `sleep`" conversation from
  every security review.

## 5. Happy path

```sh
# Local foreground:
$ hc idle &
$ pid=$!
# — waits indefinitely, 0 CPU
$ kill -TERM $pid
$ wait $pid                              # exit 0

# In a sidecar Dockerfile:
FROM scratch
COPY --from=ghcr.io/bboortz/hc:0.1.1 /hc /hc
USER 65532:65532
CMD ["/hc", "idle"]

# docker stop <container> → container exits 0 within its 10s grace.
```

## 6. Edge cases / failure modes that matter

- **PID 1 signal semantics.** The Linux kernel skips *default* actions for
  signals delivered to PID 1. `sigprocmask(BLOCK) + signalfd + read` counts as
  explicit handling, so TERM/INT are delivered to the fd and `read()` returns.
  A naïve `pause()` loop without a handler ignores TERM when PID 1 — hangs
  until the runtime hard-kills after the grace window.
- **Signals other than TERM/INT** (e.g. HUP, USR1, CHLD, …). Not in our
  subscribed set, so the kernel takes the default action, which for most of
  them (except KILL/STOP) is to terminate the process. That's fine — they're
  not expected to arrive in the sidecar use case.
- **Already-pending signal when `hc idle` starts.** `sigprocmask` before
  `signalfd` + `read` ensures the fd picks up anything queued since the
  thread started. No race with a parent that sent TERM before `read` was
  called.
- **Pre-existing `SIGALRM` watchdog.** The probe-path arms SIGALRM via
  `armDeadline`. The idle dispatch happens **before** `armDeadline` runs,
  so no timer fires in idle mode.
- **`hc idle` with extra args** → exit 2 with the standard usage line.
- **`signalfd(2)` failure** (unexpected on Linux ≥ 2.6.22; shouldn't happen
  on any supported runner) → print `hc: signalfd failed` on stderr and
  exit 1. Consumers can distinguish from the normal "unhealthy" exit via the
  stderr line.

## 7. Out of scope

- **A tickless periodic-probe mode** (`hc watch http://... --interval 30s`).
  Different story. Docker's `HEALTHCHECK` feature already owns intervals.
- **Config file loading** or environment-driven dispatch. No `HC_MODE=idle`
  smell.
- **Metrics / status output** in the idle path. Silence is golden — the
  operator wants nothing in logs between actual healthcheck invocations.
- **A `CMD [./hc", "idle"]`-less image** (i.e. hc as a one-shot container
  that exits immediately after the probe). Already the default behavior
  for every URL-form invocation; idle is the one exception, not the norm.
- **Zombie / orphan reaping** (PID 1 of a container is traditionally
  responsible for reaping orphans). The sidecar spawns no children — `hc`
  is single-threaded and single-purpose. No `waitpid` loop needed.

## 8. Acceptance (Gherkin → shell assertions)

```gherkin
Scenario: hc idle blocks until SIGTERM
  Given a built hc binary
  When  `hc idle &` is started
  Then  it does NOT exit on its own within 2 s
  When  `kill -TERM <pid>` is sent
  Then  the process exits 0 within 1 s

Scenario: hc idle exits 0 on SIGINT
  Given hc idle running in background
  When  `kill -INT <pid>` is sent
  Then  the process exits 0 within 1 s

Scenario: hc idle rejects additional arguments
  When  `hc idle https://example.com/` is called
  Then  hc exits 2 (usage error) and prints the usage line on stderr

Scenario: hc idle is PID 1 safe inside a scratch container
  Given the published scratch image hc:local-test (HC-005's Dockerfile)
  When  I run `docker run -d --rm --name hc-idle hc:local-test idle`
  And   then `docker stop -t 10 hc-idle` within 15 s
  Then  the container exits 0 and the stop completes within the grace window

Scenario: hc idle regression-safe for all prior modes
  Then  make check is green — every URL-form probe (tcp/tls/http/https) + all
        prior acceptance tests still pass without modification

Scenario: Memory invariant updated
  Then  memory/project.md names `hc idle` as the only long-running variant
        (closing the door on daemon-mode scope creep)
```

## 9. Capabilities delivered or extended

- `hc.idle-mode` — `hc idle` blocks on `{SIGTERM, SIGINT}` via `sigprocmask + signalfd + read`, exits 0 on either signal, exits 2 if any additional argument is passed. Makes `hc` usable as the PID 1 of a scratch sidecar container without an external `sleep` / `pause` binary.
