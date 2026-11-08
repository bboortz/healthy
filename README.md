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
scripts/build.sh                            # x86_64-linux, TLS, trusts the CA given via --ca
CA=ca.pem scripts/build.sh                  # embed your private CA: no --ca needed at runtime
TLS=0 scripts/build.sh                      # tcp/http only, about a quarter of the size
TARGET=aarch64-linux scripts/build.sh       # also riscv64-linux, arm-linux-musleabihf, ...
ZIG="python3 -m ziglang" scripts/build.sh   # Zig from the `ziglang` PyPI package
```

Outputs land under `bin/` (e.g. `bin/hc-x86_64-linux`). `make build` wraps this;
`make check` runs the full local gate (lint + build ± TLS + cross + tests + traceability).

Sizes (stripped, static, `ReleaseSmall`, baseline CPU features):

| Target | With TLS | `TLS=0` |
|---|---|---|
| x86_64 | 404 KB | 115 KB |
| aarch64 | 347 KB | 108 KB |
| riscv64 | 585 KB | 101 KB |
| arm32 (musleabihf) | 563 KB | not built |

The x86_64 binary is covered by the test suite. The aarch64, riscv64 and arm32 binaries are
cross-compiled but have **not been run** yet: try `./bin/hc-riscv64-linux tcp://127.0.0.1:22` on the
target before relying on them.

## Usage patterns

`hc` runs via the orchestrator's **exec** form (`CMD`, `command:`, `exec:`) — never
`CMD-SHELL` / `shell:` / `httpGet:`. That's what lets it sit in a `FROM scratch` image
with nothing else: no `/bin/sh`, no `curl`, no `python`.

Two timings cover the common cases:

- **`-t 1`** for **startup** probes — polling "is it up yet?" The deadline bounds each
  attempt tightly so convergence to healthy happens in ~1 s on real services (measured
  p99 ≤ 5 ms on loopback for four `homelab/hetzner-staging` services on 2026-11-08).
- **`-t 5`** (the default) for **steady-state** — tolerates the occasional 2 s GC
  pause, cold cache, or upstream wobble without flapping.

### Docker

**Dockerfile `HEALTHCHECK`** — scratch-safe, single exec form:

```dockerfile
# Steady-state only (simplest):
HEALTHCHECK --interval=60s --timeout=10s --retries=3 --start-period=30s \
  CMD ["/hc", "http://127.0.0.1:8080/healthz"]
```

**`docker-compose.yml`** — matching the homelab convention (`start_interval` for fast
startup polling, then relaxed cadence):

```yaml
services:
  app:
    healthcheck:
      # Tight during start_period, relaxed after (Docker 25+):
      test: ["CMD", "/hc", "-t", "5", "http://127.0.0.1:8080/healthz"]
      interval: 60s          # steady-state cadence
      start_interval: 2s     # rapid poll during start_period (uses -t 1 is fine)
      timeout: 10s           # must be ≥ hc's -t
      retries: 3             # consecutive fails before unhealthy
      start_period: 30s      # grace window where failures don't count
```

For a dedicated startup-tight check, split the two phases by putting a shorter
`-t 1` in a **separate healthcheck container** or rely on `start_interval: 2s`
which makes Docker poll fast during start_period regardless of the test's own
timeout. Running one check with `-t 5` plus `start_interval: 2s` gets you the
best of both without a separate container.

Other common shapes:

```yaml
# Accept redirects as healthy:
test: ["CMD", "/hc", "-s", "200-399", "http://127.0.0.1:8080/"]

# TLS with private CA baked in at build time (CA=ca.pem scripts/build.sh):
test: ["CMD", "/hc", "https://app.internal/ping.txt"]

# TLS with host-header override (useful for loopback HTTPS behind SNI-strict proxy):
test: ["CMD", "/hc", "-k", "-H", "example.org", "-m", "ok", "https://127.0.0.1/ping.txt"]

# TCP-only reachability probe (port listening?):
test: ["CMD", "/hc", "tcp://localhost:4532"]
```

### Kubernetes

Three-probe pattern — tight `startupProbe` gates the other two until the service is
up, then `readinessProbe` and `livenessProbe` take over at relaxed cadence:

```yaml
spec:
  containers:
    - name: app
      image: my/app:latest
      startupProbe:
        exec:
          command: ["/hc", "-t", "1", "http://127.0.0.1:8080/healthz"]
        periodSeconds: 1          # poll every 1s during startup
        failureThreshold: 30      # 30s total startup runway
        timeoutSeconds: 2         # must be ≥ hc's -t
      readinessProbe:
        exec:
          command: ["/hc", "http://127.0.0.1:8080/healthz"]  # default -t 5
        periodSeconds: 10
        failureThreshold: 3
        timeoutSeconds: 6         # must be ≥ hc's -t 5
      livenessProbe:
        exec:
          command: ["/hc", "http://127.0.0.1:8080/healthz"]
        periodSeconds: 30
        failureThreshold: 3
        timeoutSeconds: 6
```

`startupProbe` runs first and gates the others — until it passes once, Kubernetes
won't invoke `readinessProbe` or `livenessProbe`. That's the native pattern for
"fast startup, slow steady-state."

### Ansible

Smoke-test task for a post-deploy probe, mirroring `homelab/ansible/tasks/
smoke-http.yml`'s retry loop but with `hc` instead of `curl`:

```yaml
- name: "Smoke: wait for HTTP 200 on {{ smoke_url }}"
  command: /opt/hc/bin/hc -t 5 -s 200-299 {{ smoke_url }}
  register: _smoke
  retries: 12                      # ~2 minutes total (12 × 10s delay)
  delay: 10
  until: _smoke.rc == 0
  changed_when: false
```

Use `command:` (not `shell:`) so there's no `/bin/sh` in the loop, matching the
no-shell story of the binary. Pre-provision `hc` in a known path via a one-shot
`copy:` or `get_url:` task earlier in the role.

For TLS smoke tests against a private CA, embed the CA at build time
(`CA=ca.pem scripts/build.sh`) or pass `--ca /path/to/ca.pem` in the task.

### Migrating from common legacy patterns

Drop-in replacements for every pattern currently in use across `bboortz/homelab`:

| Legacy pattern | `hc` equivalent |
|---|---|
| `python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:PORT/health')"` | `/hc http://localhost:PORT/health` |
| `curl -sf URL` | `/hc URL` (or `/hc -s 200-299 URL` to be explicit) |
| `curl -sf --max-time 10 URL` | `/hc -t 10 URL` |
| `wget -qO- URL` | `/hc URL` |
| `wget -qO /dev/null http://localhost:9290/metrics` | `/hc http://localhost:9290/metrics` |
| `nc -z HOST PORT` | `/hc tcp://HOST:PORT` |
| `curl -sf -k https://localhost:8443/path \|\| exit 1` | `/hc -k https://localhost:8443/path` |

In each case: smaller container image (no Python / curl / wget / nc needed), static
binary (works in `FROM scratch`), explicit timeout via `-t`, grep-able error on stderr.
Exit codes stay the same (0 healthy / 1 unhealthy / 2 usage error).

## Test

```sh
scripts/build.sh && HC=./bin/hc-x86_64-linux ./test/run.sh
# or simply:
make test
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
  silently ignored and you get a native Debug build (31 MB). `scripts/build.sh` gets this right.
