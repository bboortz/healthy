*How `test/run.sh` is structured, the invariants it enforces, and how to add a case without breaking the others.*

## What it tests

`test/run.sh` is the single entry point. It needs `openssl` and `python3`. It builds throwaway material in a `mktemp -d` and tears it all down on exit:

- Private CA (ECDSA P-256) + server cert with SANs `DNS:localhost, DNS:app.test, IP:127.0.0.1`
- Second CA (`ca2.pem`) for "wrong CA" negatives
- Plain HTTP server on `:8080` via `python3 test/srv.py`
- TLS 1.3 server on `:8443` via the same script
- A hung server on `:8097` that accepts connections but never responds (used for the watchdog test)

The HTTP server serves `www/ping.txt`, `www/health`, plus special paths:
- `/teapot` — returns 418
- `/redir` — returns 302
- `/echo-host` — returns the `Host:` header verbatim (used by the `-H` test)

## Invocation

```sh
scripts/build.sh && HC=./bin/hc-x86_64-linux ./test/run.sh
```

`HC` must be a path; `test/run.sh` canonicalises it before `cd`ing to the temp dir. `make test` wraps both steps.

## The test table (28 cases + 2 watchdogs)

Each test is one line: `t <expected-rc> "$HC" <args...>`. The helper increments `pass` / `fail`, so adding a case is a one-line append. Exit codes: `0` healthy, `1` unhealthy, `2` usage error.

Categories covered:

| Area | Covers |
|---|---|
| TCP | success + closed-port failure |
| HTTP | success, 404, 418 + custom range, 302 + range, body match, `-H` host override |
| HTTPS | success, wrong body, bad path, host-SAN matching, wrong hostname, wrong CA, no CA |
| `-k` | insecure success, body + host override |
| Usage | no args, no scheme, unsupported scheme |
| Watchdog | plain + TLS to the hung server — must fail at `-t` seconds ±1 |

## Adding a case

1. Decide the expected rc (`0`, `1`, or `2`).
2. Append a `t <rc> "$HC" <flags> <url>` line in the relevant block.
3. If the case needs a new URL path, add it to `test/srv.py`.
4. If the case needs new TLS material (a second SAN, an IP cert, …), extend the `openssl` invocations at the top — do not create a second CA setup block.
5. Run `./test/run.sh` and confirm the line count in `pass=N fail=0` grew by one.

## Cross-target caveat

The suite only runs the x86_64 binary. aarch64 / riscv64 / arm32 cross-compilations are **built** by `make cross` but **not executed** — there's no QEMU-user wrapper here. Before claiming a cross-target works in production:

```sh
./bin/hc-<target>-linux tcp://127.0.0.1:22   # on the actual target
```

Document any new cross-target confirmation in README's "Notes and limitations" section.

## Flakes to watch

- The warmup loop (`while [ $i -lt 50 ]; do "$HC" tcp://127.0.0.1:8443 … done`) tolerates server startup latency up to ~5 s. If CI reports occasional "connection refused" on the first few cases, extend the loop — don't widen the per-case deadline.
- The watchdog test asserts `-t 2` fires in 2–3 s inclusive. On heavily loaded CI you may need 2–4 s; adjust the range, don't remove the upper bound (the whole point is "watchdog fires in bounded time").
- `python3 test/srv.py` uses the stdlib HTTP server — single-threaded, so don't add parallel cases that race for the same port.
