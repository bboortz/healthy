# `test/acceptance/`

Per-story acceptance tests for the DD-TGD workflow. Each new HC-NNN story that touches
observable behaviour lands a file here:

```
test/acceptance/test_HC_NNN_<slug>.sh
```

## Required header

```
#!/bin/sh
# test_HC_NNN_<slug>.sh — one-line summary
# Story:  docs/stories/HC-NNN-<slug>.md
# Plan:   docs/plan/HC-NNN-<slug>-plan.md
# CAPs:   cap.id.one, cap.id.two
```

`make verify-traceability` reads the `# CAPs:` line and asserts every id named there
exists in `docs/CAPABILITIES.md`.

## Structure

Acceptance scripts expect the same environment as `test/run.sh`:
- `HC` env var pointing at the built binary (default: `./hc-x86_64-linux`)
- `openssl` and `python3` in PATH if the test needs TLS material or an HTTP server

The simplest form is the same `t <rc> "$HC" <args…>` helper used in `test/run.sh`:

```sh
pass=0; fail=0
t() { want=$1; shift; "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then pass=$((pass + 1));
  else fail=$((fail + 1)); echo "FAIL want=$want got=$rc: $*"; fi; }

t 0 "$HC" <...>
t 1 "$HC" <...>

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
```

If the scenario needs its own test server, copy the pattern from `test/srv.py` — do not
share port numbers with `test/run.sh` (that suite uses 8080/8443/8097).

## Why the seed CAPs point at `test/run.sh` instead

The pre-existing functional suite in `test/run.sh` already covers every current
capability. Splitting it into 16 per-CAP scripts would be churn for no value. New
capabilities get their own HC-NNN acceptance script; old ones keep pointing at
`test/run.sh` until a story explicitly updates them.
