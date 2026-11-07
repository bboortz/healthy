*Zig 0.17.1-specific gotchas that bit us and are easy to re-introduce. All documented at the call site, duplicated here so grep finds them.*

## `-M` flag order (scripts/build.sh)

```
zig build-exe -target X -O Y -fsingle-threaded ... -Mroot=... -Membedded_ca=...
```

Per-module flags (`-target`, `-O`, `-fsingle-threaded`, `-fno-unwind-tables`, `-fstrip`) **must precede the `-M` they apply to**. Placed after `-M`, Zig silently ignores them and you get a native Debug build — the output balloons to ~31 MB with no warning.

Symptom: `ls -l bin/hc-*` shows a 30-megabyte artifact instead of ~400 KB. Fix: move the flags above the `-M` lines.

The one-line NB in `scripts/build.sh:30-31` documents this.

## No connect timeout on POSIX (std 0.17.1)

`std.posix.connect` has no timeout parameter and will **panic** (not return an error) if you try to wrap it with `std.posix.setsockopt(SO_RCVTIMEO)`. The workaround is the `SIGALRM` watchdog in `hc.zig` — a single `alarm(t)` call that covers the whole run (DNS + connect + handshake + read).

Do not remove the alarm thinking you'll add per-syscall deadlines "soon." Add the per-syscall deadlines first, verify they work end-to-end, then drop the alarm in the same PR.

## `std.Io` and `std.crypto.tls` API churn

Between 0.16 → 0.17 → upcoming 0.18, the `Io`, `std.net`, and `std.crypto.tls.Client` APIs change shape (readers/writers, buffered client, context types). This is why we pin to 0.17.1.

When bumping Zig: scan `hc.zig` for every `std.Io.*`, `std.net.*`, and `std.crypto.tls.*` call and cross-check against the new std source. Treat the bump as its own PR (see `memory/workflow.md § Zig version bump`).

## `@embedFile` paths are module-relative

In `scripts/build.sh` we generate `cfg.zig` in a temp dir and declare it as its own module (`-Membedded_ca=...`). `@embedFile("ca.pem")` inside that file resolves relative to the temp dir — which is why `ca.pem` is copied next to `cfg.zig`. Moving it or inlining the module back into `hc.zig` breaks the import path.

## `ReleaseSmall` + `-fsingle-threaded` interaction

Without `-fsingle-threaded`, `ReleaseSmall` still pulls in thread-local storage init code and the binary gains ~40 KB. We don't need threads — keep `-fsingle-threaded` set.

## Cross-target naming

`-target` strings we use: `x86_64-linux`, `aarch64-linux`, `riscv64-linux`, `arm-linux-musleabihf`, `x86-linux` (32-bit). The musl `-musleabihf` suffix matters for arm32 — without it you get a soft-float ABI that mismatches most Debian/Alpine arm32 images.

## `-fstrip` strips debug info, not symbols

If you need symbols for a gdb session, rebuild without `-fstrip`. Don't commit the un-stripped build settings — they're a ~2× size hit.
