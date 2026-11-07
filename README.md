# healthy

`hc` is a tiny container health checker written in Zig: one source file, no libc, no heap.
It does TCP, TLS 1.3 and HTTP(S) checks with DNS, and verifies certificates against **your own
private CA** (system roots are never trusted).

```
hc [-t secs] [-s lo-hi] [-m str] [-H name] [-k | --ca file] <url>

  tcp://host:port             TCP connect
  tls://host:port             TCP connect + verified TLS handshake
  http://host[:port]/path     GET, status must be in range
  https://host[:port]/path    same over verified TLS

  -t secs    overall deadline for DNS + connect + handshake + read (default 5)
  -s lo-hi   accepted status range (default 200-299)
  -m str     response body must contain str (first 1 KiB is searched)
  -H name    Host header and TLS SNI / verification name
  -k         skip TLS verification (like curl -k)
  --ca file  PEM file with the CA(s) to trust (overrides an embedded CA)
```

Exit codes: `0` healthy, `1` unhealthy (reason on stderr), `2` usage error.
IPv6 literals work in brackets: `http://[::1]:8080/`.

## Build

Needs [Zig](https://ziglang.org/) **0.17.1**. The std TLS and `Io` APIs change between releases, so pin the version.

```sh
./build.sh                          # x86_64-linux, TLS, trusts the CA given via --ca
CA=ca.pem ./build.sh                # embed your private CA: no --ca needed at runtime
TLS=0 ./build.sh                    # tcp/http only, about a quarter of the size
TARGET=aarch64-linux ./build.sh     # also riscv64-linux, arm-linux-musleabihf, ...
ZIG="python3 -m ziglang" ./build.sh # Zig from the `ziglang` PyPI package
```

Sizes (stripped, static, `ReleaseSmall`, baseline CPU features):

| Target | With TLS | `TLS=0` |
|---|---|---|
| x86_64 | 404 KB | 115 KB |
| aarch64 | 347 KB | 108 KB |
| riscv64 | 585 KB | 101 KB |
| arm32 (musleabihf) | 563 KB | not built |

The x86_64 binary is covered by the test suite. The aarch64, riscv64 and arm32 binaries are
cross-compiled but have **not been run** yet: try `./hc-riscv64-linux tcp://127.0.0.1:22` on the
target before relying on them.

## Docker Compose

```yaml
healthcheck:
  test: ["CMD", "/hc", "http://127.0.0.1:8890/"]                                      # plain HTTP
  # test: ["CMD", "/hc", "-s", "200-399", "http://127.0.0.1:8080/"]                    # accept redirects
  # test: ["CMD", "/hc", "-m", "ok", "https://app.internal/ping.txt"]                  # TLS + body, embedded CA
  # test: ["CMD", "/hc", "-k", "-H", "example.org", "-m", "ok", "https://127.0.0.1/ping.txt"]
  # test: ["CMD", "/hc", "tcp://localhost:4532"]                                       # port only
```

Works in a `FROM scratch` image: copy the single binary in, no shell or libc needed.

## Test

```sh
./build.sh && HC=./hc-x86_64-linux ./test/run.sh
```

Needs `openssl` and `python3`. It creates a throwaway CA, starts a plain HTTP server, a TLS 1.3
server and a server that never answers, then checks 28 cases, including the failure paths
(wrong CA, wrong hostname, no CA, closed port, bad status, hung server).

## Notes and limitations

- **Deadline:** std 0.17.1 does not implement connect timeouts on POSIX (it panics), so `-t` is a
  `SIGALRM` watchdog around the whole run. On expiry it prints `hc: timeout` and exits 1.
- **Verified TLS needs a hostname** (or `-H name`). Certificates with IP-address SANs are untested.
- **TLS 1.3 / 1.2:** the std client negotiates either; the tests only exercise TLS 1.3.
- **Request:** `GET` over HTTP/1.0 with `Connection: close`; redirects are not followed.
- **Zig CLI flag order:** per-module flags (`-target`, `-O`, ...) must come before `-M`. After it they are
  silently ignored and you get a native Debug build (31 MB). `build.sh` gets this right.
