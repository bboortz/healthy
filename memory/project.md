*What `hc` is, the design invariants that make it worth keeping small, and the budget it lives inside.*

## What it is

`hc` is a container healthcheck binary written in a single Zig source file (`hc.zig`). It does exactly four things:

| URL scheme | Behaviour |
|---|---|
| `tcp://host:port` | TCP connect |
| `tls://host:port` | TCP connect + verified TLS 1.3 handshake |
| `http://host[:port]/path` | GET; status in `-s` range (default 200–299); optional body match `-m` |
| `https://host[:port]/path` | Same, verified against configured CA |

CLI surface and exit codes are frozen in `README.md` — changes there are breaking changes for `HEALTHCHECK` lines in downstream Dockerfiles.

## Design invariants (do not violate casually)

1. **One source file.** `hc.zig` stays single-file. No module directories, no helper crates. When tempted to split, write a comment explaining the invariant you believe is loose, then don't split.
2. **No libc, no heap.** `ReleaseSmall`, `-fsingle-threaded`, `-fno-unwind-tables`, `-fstrip`, musl-style static. Any new allocation goes through a stack arena of a fixed size — never `std.heap.page_allocator`-into-a-helper.
3. **System roots are never trusted.** Verification only accepts a CA that was either embedded at build time (`CA=ca.pem scripts/build.sh`) or passed at runtime (`--ca`). `-k` is the explicit escape hatch.
4. **TLS can be compiled out.** `TLS=0 scripts/build.sh` must still build and the `tcp://` + `http://` tests must still pass — the `tls`/`https` cases get skipped. The `scripts/build.sh` `with_tls` flag feeds `cfg.zig`.
5. **The deadline is a watchdog.** Zig std 0.17.1 does not implement connect timeouts on POSIX (it panics), so `-t` is a `SIGALRM` around the whole run. If you ever remove the alarm, add real per-syscall deadlines first.
6. **Hostname verification is required for TLS unless `-k`.** Certificates with IP-SANs are untested — if a user needs them, add a test case first.

## Size budget (`ReleaseSmall`, stripped, baseline CPU)

| Target | With TLS | `TLS=0` |
|---|---|---|
| x86_64 | 404 KB | 115 KB |
| aarch64 | 347 KB | 108 KB |
| riscv64 | 585 KB | 101 KB |
| arm32 (musleabihf) | 563 KB | — |

Readme publishes these numbers. If a change pushes the x86_64 TLS build past ~450 KB, treat it as a regression and justify it in the PR body.

## Zig version pin

Tested with **Zig 0.17.1**. `std.Io` and `std.crypto.tls` APIs change between releases. Do not float the version; bumping is its own PR with the test suite re-run on each cross-target.

## What is NOT in scope

- No HTTP/2, no chunked transfer, no redirects, no cookies.
- No DNS caching, no retries, no backoff. Container runtimes already retry the healthcheck.
- No metrics output. Exit code is the signal.
- No config file. Flags only.
- No `log` package. `std.debug.print` to stderr on failure, nothing on success.
