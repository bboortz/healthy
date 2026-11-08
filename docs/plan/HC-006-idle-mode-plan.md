---
id: HC-006
slug: idle-mode
story: docs/stories/HC-006-idle-mode.md
branch: feat/HC-006-idle-mode
status: shipped
shipped: 2026-11-08
---

# HC-006 plan — `hc idle` sigwait sentinel

**Story:** [HC-006](../stories/HC-006-idle-mode.md)

## Design delta

Four files touched; one is Zig, one is memory (invariant update), the others
are docs + test:

### A. `hc.zig` — new dispatch + `idle()` function (~35 lines)

Peek-pattern: detect `argv[1] == "idle"` **before** the flag loop and before
`armDeadline` fires. If detected, reject any further args, then enter the
idle routine.

```zig
// Added at the top of main(), right after the `_ = it.next();` (skip argv[0]):
{
    var peek = init.args.iterate();
    _ = peek.next();  // program name
    if (peek.next()) |first| {
        if (std.mem.eql(u8, first, "idle")) {
            if (peek.next() != null) return usage();  // "hc idle foo" → usage err
            idle();                                   // noreturn
        }
    }
}
```

The idle function itself:

```zig
fn idle() noreturn {
    const posix = std.posix;

    // Signals we want delivered via signalfd (not via default action).
    var set = posix.sigemptyset();
    posix.sigaddset(&set, posix.SIG.INT);
    posix.sigaddset(&set, posix.SIG.TERM);

    // Block TERM/INT in this thread's mask so the kernel queues them to our
    // signalfd. For PID 1 this is also what counts as "explicit handling" —
    // without it, SIGTERM to a PID 1 that installed no handler is dropped.
    posix.sigprocmask(posix.SIG.BLOCK, &set, null);

    const fd = posix.signalfd(-1, &set, 0) catch {
        say("hc: signalfd failed\n");
        std.process.exit(1);
    };

    // Block on read until a signal arrives. We don't inspect which — any of
    // the subscribed signals means "exit cleanly."
    var buf: [128]u8 = undefined;
    _ = posix.read(fd, &buf) catch {
        say("hc: signalfd read failed\n");
        std.process.exit(1);
    };

    std.process.exit(0);
}
```

Plus a one-line addition to `usage()` naming the subcommand:

```
usage: hc [flags] <url>
       hc idle                                      block on SIGTERM/SIGINT (PID 1 safe)
```

**Why signalfd + read instead of `sigaction` + `pause`:**

- Zig 0.17.1's `std.posix` does **not** expose `sigwaitinfo` / `rt_sigtimedwait`
  / `pause`. It does expose `signalfd`, `sigprocmask`, `sigemptyset`,
  `sigaddset`, `read`.
- `signalfd` requires one syscall to create the fd, then one `read` to block.
  No signal handler to install, no race between unblocking and pause, no
  state that lives outside this stack frame.
- `read` returning a signalfd_siginfo *is* an explicit handler from the
  kernel's PID-1-semantics perspective — the kernel sees the signal is
  blocked + a reader is pending, delivers via fd, dequeues from the pending
  mask.

### B. `memory/project.md` invariant update

Pre-authorizes `hc idle` and still closes the door on daemon-mode creep. One
bullet in the "What is NOT in scope" list, and one line in the "What hc is"
section:

> **What `hc` is:** a one-shot probe **or** a sigwait sentinel (`hc idle`).
> Every other invocation of `hc` performs one probe and exits.
>
> **What is NOT in scope:**
> - No daemon mode with side effects (no HTTP server, no metrics, no scheduled
>   probes, no state). `hc idle` is the only long-running shape, and it
>   performs no I/O between start and signal.

### C. `test/acceptance/test_HC_006_idle-mode.sh`

Six scenarios mapping 1:1 to §8 of the story:

1. Foreground SIGTERM → exit 0 within 1 s
2. Foreground SIGINT → exit 0 within 1 s
3. Extra args → exit 2
4. **Docker PID-1** — `docker build` HC-005's Dockerfile with the latest `hc`,
   run with `["idle"]` as the command, `docker stop -t 10`, assert exit 0 +
   within grace. Docker-gated; developer without docker gets a skipped line
   plus the five other assertions.
5. Regression — assert the existing `test/run.sh` still exits 0 under this
   binary. Implicit via `make check`, redundantly asserted here.
6. Memory invariant assertion — `memory/project.md` mentions `hc idle` in the
   "What hc is" paragraph.

### D. `CHANGELOG.md` + `docs/CAPABILITIES.md` + `docs/stories/INDEX.md`

One new CAP (`hc.idle-mode`); one row in INDEX; one `### Added (HC-006)`
entry in the current CHANGELOG `v0.1.0` block.

## Alternatives rejected

| Alternative | Why not |
|---|---|
| `hc --idle` flag instead of `hc idle` subcommand | Weaker convention for "modes" (git / docker / kubectl all use subcommands for mode selection). Subcommand also future-proofs the "one-shot vs idle" distinction so the usage line stays grep-able. Collision risk is zero — `hc` only accepts URL positionals matching `(tcp\|tls\|http\|https)://`. |
| `sigaction(SIGTERM, handler) + pause()` | `pause()` isn't exposed in `std.posix` for Zig 0.17.1; would require a direct syscall. `signalfd` is both cleaner and already exposed. |
| `rt_sigtimedwait` syscall directly | Zig's `std.posix` has no wrapper; we'd be writing raw `linux.syscall4`. `signalfd` is a documented public API with the same semantics. |
| Separate binary `hc-idle` / `pause` | Deviates from the "one source file" invariant. Would require a second `-Mroot` + extra CI publishing. 30 lines in `hc.zig` is cheaper. |
| Zombie-reaping loop (`waitpid` in a child-handling thread) | `hc` is single-threaded, single-purpose, and spawns no children. No zombies to reap. The sidecar's PID 1 role is "stay alive", not "init". |
| Block **all** signals (not just TERM/INT) | Would survive `kill -QUIT` / `kill -HUP` from a confused operator or orchestrator. `docker stop` sends TERM; if the operator sends QUIT or KILL, we want default action (dump core or die). |
| No signal mask at all; let SIGTERM take default action | Works for non-PID-1 scenarios but hangs forever as PID 1 (kernel skips default actions). The sidecar use case is explicitly the PID-1 one. |

## Breaking changes

- [ ] No. The subcommand shape (`hc idle`) is additive. The existing URL-form
  invocation is unchanged; every current argument combination still works.
  Usage text grows by one line.
- [ ] No binary-size regression expected. signalfd + read syscalls add ~200
  bytes of code; LLVM may dead-code the idle path when `TLS=0` builds skip
  TLS features but the idle path is independent. Verified by `make check`'s
  `make size` step (budget 450 KB x86_64 TLS=1; we're at ~400 KB today).

## Rollout

- [x] `hc.zig` — `idle()` + dispatch + usage() line
- [x] `memory/project.md` — invariant rewrite to pre-authorize idle
- [x] `test/acceptance/test_HC_006_idle-mode.sh` — six Gherkin scenarios
- [x] `docs/CAPABILITIES.md` — new `hc.idle-mode` CAP
- [x] `docs/stories/INDEX.md` — HC-006 row
- [x] `CHANGELOG.md` — `### Added (HC-006)` entry
- [ ] **Post-merge**: dispatch `release.yml` to publish `hc:0.1.1` (or
  overwrite `:0.1.0` — same end result, downstream forge pins whichever)
- [ ] **Downstream**: forge opens FG-031 — Dockerfile delta is `-sleep -libc
  +CMD ["/hc", "idle"]`. ~500 KB final image.

## Shipping evidence (fill at step 6a)

### Lens 1 — Gherkin coverage

| Scenario (story §8) | Test pointer | Status |
|---|---|---|
| Foreground SIGTERM → exit 0 | `test/acceptance/test_HC_006_idle-mode.sh` (Scenario 1) | ✅ |
| Foreground SIGINT → exit 0 | same file, Scenario 2 | ✅ |
| Extra args → exit 2 | same file, Scenario 3 | ✅ |
| Docker PID 1 safe | same file, Scenario 4 (docker-gated) | ✅ |
| Prior modes regression-safe | implicit via `make check` + explicit `test/run.sh` re-run in Scenario 5 | ✅ |
| Memory invariant updated | Scenario 6 greps `memory/project.md` | ✅ |

### Lens 2 — Behaviour symmetry

| CAP | ≥ 1 test? | Both exit paths (0/2)? | Status |
|---|---|---|---|
| `hc.idle-mode` | ✅ | ✅ (0 on TERM/INT; 2 on extra args) | ✅ |

### Lens 3 — Self-consistency

| Check | Status |
|---|---|
| Story obeys §7 — no watch mode, no config, no metrics, no reaping | ✅ |
| New CAP in §9 is in `docs/CAPABILITIES.md` | ✅ |
| `make check` green on this branch | ✅ |
| `make verify-traceability` green (34 CAPs) | ✅ |
| Size budget unchanged (±5%) — `make size` passes | ✅ |
| Memory invariant pre-authorizes the scope shift | ✅ |

## Post-merge notes

First HC story to add runtime behaviour to `hc.zig` since the project
started (HC-001..005 were all workflow / docs / packaging). Confirms that
the DD-TGD motion handles code deltas as cleanly as it does docs deltas —
the story + plan + red-first acceptance test + implementation rolled out
in one pass with a single bug (smoke-test `| tail -3` ate the exit code;
not a code bug, my test-authoring bug).

Signal-handling worth remembering for next time:
- Zig 0.17.1's `std.posix` does **not** expose `sigwaitinfo` /
  `rt_sigtimedwait` / `pause`. If you need any of those, go via
  `std.os.linux.syscallN` directly or use `signalfd` + `read` which IS
  exposed.
- `linux.sigemptyset()` is a value constructor (returns `sigset_t`),
  not an in-place mutator — unlike POSIX C's `sigemptyset(&set)`.
- `linux.signalfd(-1, &set, 0)` returns a `usize` holding either an fd
  (if ≤ i32::MAX) or `-errno` wrapped in usize (if > i32::MAX). The
  `rc_fd > std.math.maxInt(i32)` check is the idiomatic way to
  distinguish without pulling in `std.os.linux.E.init`.

The 216-byte binary growth is almost entirely the additional `signalfd`
+ `read` syscall paths. The idle function itself compiles to ~40
instructions; the rest is sigset construction + error-formatting lookup
tables.

Open follow-ups (own stories):
- **FG-031** (forge-side): rewrite `healthy-scratch-trixie` Dockerfile
  to drop `sleep` + its libc closure and use `CMD ["/hc", "idle"]`.
  Blocked on HC-006 being published to GHCR (next `release.yml` dispatch).
- **HC-007**: cosign keyless OIDC signing of the GHCR image (still
  pending; now covers both the probe and sentinel modes in one signed
  artifact).
