#!/bin/sh
# test_HC_004_usage-patterns-docs.sh — README has copy-paste-ready Docker,
# Kubernetes, and Ansible integration patterns, plus a legacy-pattern
# migration table.
# Story: docs/stories/HC-004-usage-patterns-docs.md
# Plan:  docs/plan/HC-004-usage-patterns-docs-plan.md
# CAPs:  docs.integration-patterns

set -u
pass=0; fail=0

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1

assert_grep() { pat=$1; file=$2
  if grep -Eq "$pat" "$file" 2>/dev/null; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL grep '$pat' in $file"; fi; }

assert_grep_fixed() { pat=$1; file=$2
  if grep -Fq "$pat" "$file" 2>/dev/null; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL grep -F '$pat' in $file"; fi; }

# A helper that greps a slice of README between two heading anchors. Lets us
# scope assertions to the right subsection so we don't accept a hit from
# elsewhere in the file.
grep_section() {
  pat=$1; start=$2; stop=$3
  awk -v s="$start" -v e="$stop" '
    $0 ~ s { inside=1; next }
    inside && $0 ~ e { exit }
    inside { print }
  ' README.md | grep -Eq "$pat"
}

assert_in_section() { pat=$1; start=$2; stop=$3; label=$4
  if grep_section "$pat" "$start" "$stop"; then pass=$((pass + 1))
  else fail=$((fail + 1)); echo "FAIL (in $label) grep '$pat'"; fi; }

# ----- Scenario 1 — top-level section + three subsections ------------------
assert_grep '^## Usage patterns\s*$'  README.md
assert_grep '^### Docker\s*$'         README.md
assert_grep '^### Kubernetes\s*$'     README.md
assert_grep '^### Ansible\s*$'        README.md
assert_grep '^### Migrating'          README.md

# Each subsection has at least one fenced block.
assert_in_section '^```'  '^### Docker'     '^### Kubernetes' "Docker"
assert_in_section '^```'  '^### Kubernetes' '^### Ansible'    "Kubernetes"
assert_in_section '^```'  '^### Ansible'    '^### Migrating'  "Ansible"

# ----- Scenario 2 — Docker covers HEALTHCHECK + compose + both timings ----
assert_in_section 'HEALTHCHECK'     '^### Docker' '^### Kubernetes' "Docker/HEALTHCHECK"
assert_in_section 'healthcheck:'    '^### Docker' '^### Kubernetes' "Docker/compose"
assert_in_section 'start_period'    '^### Docker' '^### Kubernetes' "Docker/start_period"
assert_in_section 'start_interval'  '^### Docker' '^### Kubernetes' "Docker/start_interval"
assert_in_section 'interval:'       '^### Docker' '^### Kubernetes' "Docker/interval"
assert_in_section 'timeout:'        '^### Docker' '^### Kubernetes' "Docker/timeout"
assert_in_section 'retries:'        '^### Docker' '^### Kubernetes' "Docker/retries"
# Startup-tight and steady-state deadline knobs referenced somewhere nearby.
assert_grep '\-t[ ]*1'  README.md
assert_grep '\-t[ ]*5'  README.md

# ----- Scenario 3 — Kubernetes three-probe pattern (exec, not httpGet) ----
assert_in_section 'startupProbe:'     '^### Kubernetes' '^### Ansible' "K8s/startupProbe"
assert_in_section 'readinessProbe:'   '^### Kubernetes' '^### Ansible' "K8s/readinessProbe"
assert_in_section 'livenessProbe:'    '^### Kubernetes' '^### Ansible' "K8s/livenessProbe"
assert_in_section 'exec:'             '^### Kubernetes' '^### Ansible' "K8s/exec"
# No httpGet — would bypass hc entirely.
if grep_section 'httpGet:' '^### Kubernetes' '^### Ansible'; then
  fail=$((fail + 1)); echo "FAIL Kubernetes section should not use httpGet (bypasses hc)"
else
  pass=$((pass + 1))
fi
# startupProbe uses -t 1; the readiness/liveness blocks don't (they inherit default).
assert_in_section '"-t", "1"'  '^### Kubernetes' '^### Ansible' "K8s/startup -t 1"

# ----- Scenario 4 — Ansible uses command (not shell), has retry pattern ---
assert_in_section 'command:' '^### Ansible' '^### Migrating' "Ansible/command"
assert_in_section 'retries:' '^### Ansible' '^### Migrating' "Ansible/retries"
assert_in_section 'delay:'   '^### Ansible' '^### Migrating' "Ansible/delay"
assert_in_section 'until:'   '^### Ansible' '^### Migrating' "Ansible/until"
# Must NOT use `shell:` as a YAML key (prose mention is fine — we WANT to call
# out that shell: is wrong). Anchor on leading whitespace + key form.
if grep_section '^[[:space:]]+shell:[[:space:]]' '^### Ansible' '^### Migrating'; then
  fail=$((fail + 1)); echo "FAIL Ansible section uses 'shell:' (YAML key) which drops /bin/sh back in"
else
  pass=$((pass + 1))
fi

# ----- Scenario 5 — Migration table covers all four legacy patterns -------
# (grep -F because the patterns contain shell metachars)
assert_grep_fixed 'urllib.request.urlopen'       README.md
assert_grep_fixed 'curl -sf'                     README.md
assert_grep_fixed 'wget -qO-'                    README.md
assert_grep_fixed 'nc -z'                        README.md
# And the hc replacements are referenced in the same table.
assert_in_section 'tcp://HOST:PORT' '^### Migrating' '^## '  "Migration/tcp"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
