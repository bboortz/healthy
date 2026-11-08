#!/bin/sh
# test_HC_006_idle-mode.sh — `hc idle` sigwait sentinel for PID 1 use.
# Story: docs/stories/HC-006-idle-mode.md
# Plan:  docs/plan/HC-006-idle-mode-plan.md
# CAPs:  hc.idle-mode

set -u
pass=0; fail=0

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1

HC=${HC:-./bin/hc-x86_64-linux}
if [ ! -x "$HC" ]; then
  # Build if missing (e.g. after make clean). Matches HC-005's test's pattern.
  scripts/build.sh >/dev/null 2>&1
fi

# Portable timing + wait-with-timeout. Works on dash (CI) and bash (Arch).
# We avoid polling `kill -0` because on dash the shell doesn't reap
# backgrounded children eagerly — kill -0 returns 0 on zombies and the
# loop spins past its budget. Instead: block on `wait $pid` directly
# (which reaps) + a sibling killer that guarantees unblocking after the
# budget. elapsed_ms = time from signal send to reap.
now_ms() { date +%s%3N; }

check_idle_signal() {
  # check_idle_signal <sig> <scenario-label>
  sig=$1; label=$2

  "$HC" idle &
  pid=$!
  sleep 0.3

  start=$(now_ms)
  kill -"$sig" "$pid" 2>/dev/null

  # Backgrounded killer: SIGKILL the child if it hasn't exited by the budget.
  ( sleep 1; kill -KILL "$pid" 2>/dev/null ) &
  killer=$!

  # `wait $pid` blocks until the child is reaped (either signal-driven or killer-driven).
  wait "$pid"; rc=$?
  elapsed=$(( $(now_ms) - start ))

  # Clean up the killer (may still be sleeping on fast exit).
  kill "$killer" 2>/dev/null
  wait "$killer" 2>/dev/null || true

  if [ "$rc" = 0 ] && [ "$elapsed" -lt 1000 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL ($label) hc idle: rc=$rc elapsed=${elapsed}ms (want rc=0, elapsed<1000)"
  fi
}

# ----- Scenario 1 — foreground SIGTERM → exit 0 within 1s ------------------
check_idle_signal TERM S1

# ----- Scenario 2 — foreground SIGINT → exit 0 within 1s -------------------
check_idle_signal INT S2

# ----- Scenario 3 — extra args → exit 2 ------------------------------------
"$HC" idle somearg >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL (S3) hc idle with extra args: got $rc, want 2"; fi

"$HC" idle https://example.com/ >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL (S3) hc idle URL: got $rc, want 2"; fi

# ----- Scenario 4 — PID-1 safe inside a scratch container (docker-gated) ---
if command -v docker >/dev/null 2>&1; then
  tag=hc-test-hc006:local
  if docker build --quiet --build-arg HC_BIN=bin/hc-x86_64-linux -t "$tag" . >/dev/null 2>&1; then
    pass=$((pass + 1))
    # Start in daemon mode (idle).
    cname=hc-test-hc006-idle
    docker rm -f "$cname" >/dev/null 2>&1 || true
    if docker run -d --rm --name "$cname" "$tag" idle >/dev/null 2>&1; then
      sleep 0.5
      # Container should be up
      state=$(docker inspect "$cname" --format '{{.State.Status}}' 2>/dev/null)
      if [ "$state" = "running" ]; then pass=$((pass + 1))
      else fail=$((fail + 1)); echo "FAIL (S4) container state: got $state, want running"; fi

      # docker stop within grace → exit 0
      start=$(now_ms)
      docker stop -t 10 "$cname" >/dev/null 2>&1
      elapsed=$(( $(now_ms) - start ))
      # 10s grace; we want well under that (<2s indicates clean SIGTERM, not SIGKILL).
      if [ "$elapsed" -lt 2000 ]; then pass=$((pass + 1))
      else fail=$((fail + 1)); echo "FAIL (S4) docker stop took ${elapsed}ms — likely SIGKILL after grace (not PID-1 safe)"; fi

      # Container should have exited 0 (SIGTERM → clean exit via hc's signalfd).
      # Note: --rm means the container is gone; we must have inspected before.
      # Workaround: use --restart=no (default for `docker run`) and check logs
      # before docker-rm. Since --rm auto-removes on exit, we can't inspect.
      # Re-run without --rm for the exit-code check:
      docker rm -f "$cname" >/dev/null 2>&1 || true
      cname2=hc-test-hc006-idle2
      docker run -d --name "$cname2" "$tag" idle >/dev/null 2>&1
      sleep 0.3
      docker stop -t 10 "$cname2" >/dev/null 2>&1
      exit_code=$(docker inspect "$cname2" --format '{{.State.ExitCode}}' 2>/dev/null)
      docker rm -f "$cname2" >/dev/null 2>&1 || true
      if [ "$exit_code" = "0" ]; then pass=$((pass + 1))
      else fail=$((fail + 1)); echo "FAIL (S4) container exit code: got $exit_code, want 0"; fi
    else
      fail=$((fail + 1)); echo "FAIL (S4) docker run of $tag idle failed"
    fi
    docker image rm "$tag" >/dev/null 2>&1 || true
  else
    fail=$((fail + 1)); echo "FAIL (S4) docker build failed"
  fi
else
  echo "note: docker not available — skipping PID-1 Scenario 4"
fi

# ----- Scenario 5 — Prior modes still work (regression) --------------------
# The URL-form invocation path is untouched by HC-006. Sample a few cases
# that cover arg-parsing, usage errors, and the probe fast-path.
"$HC" >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL (S5) bare hc (no args): got $rc, want 2"; fi

"$HC" ftp://x:1 >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL (S5) bad scheme: got $rc, want 2"; fi

"$HC" tcp://127.0.0.1:1 >/dev/null 2>&1; rc=$?
if [ "$rc" = 1 ]; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL (S5) tcp refused: got $rc, want 1"; fi

# ----- Scenario 6 — Memory invariant updated -------------------------------
if grep -Fq "hc idle" memory/project.md; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL (S6) memory/project.md does not mention hc idle"; fi

if grep -Eq 'daemon mode|long-running' memory/project.md; then pass=$((pass + 1))
else fail=$((fail + 1)); echo "FAIL (S6) memory/project.md does not pre-authorize the scope shift"; fi

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
