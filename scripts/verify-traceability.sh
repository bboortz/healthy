#!/usr/bin/env bash
# Enforce bidirectional story ↔ plan ↔ test ↔ CAP links for healthy:
#   1. Every CAP in docs/CAPABILITIES.md has a 'Covered by:' pointer.
#   2. Every test/acceptance/test_HC_*.sh has a '# CAPs:' header and
#      the CAPs it names all exist in CAPABILITIES.md.
#   3. Every story with status ready / in-progress / shipped lists at
#      least one CAP id in the §9 bullet list.
set -euo pipefail

caps_file="docs/CAPABILITIES.md"
fail=0

if [[ ! -f "$caps_file" ]]; then
  echo "FAIL: $caps_file is missing." >&2
  exit 1
fi

# CAP ids look like `scheme.tcp`, `tls.verify-private-ca`, `binary.no-libc`.
mapfile -t known_caps < <(grep -E '^### [a-z]+\.[a-z-]+$' "$caps_file" | sed 's/^### //')

if [[ ${#known_caps[@]} -eq 0 ]]; then
  echo "FAIL: no CAP ids found in $caps_file (expected '### domain.verb' headings)." >&2
  exit 1
fi

# 1. Every known CAP must have a 'Covered by:' pointer in its section.
for cap in "${known_caps[@]}"; do
  if ! awk -v cap="### $cap" '
      $0 == cap { inside = 1; next }
      inside && /^### / { exit 1 }
      inside && /Covered by/ { found = 1; exit 0 }
      END { exit !found }
    ' "$caps_file"; then
    echo "FAIL: CAP $cap has no 'Covered by:' pointer in $caps_file" >&2
    fail=1
  fi
done

# 2. Every acceptance test must have a '# CAPs:' header; every CAP it names must be known.
shopt -s nullglob
for test in test/acceptance/test_HC_*.sh; do
  if ! grep -q -E '^# *CAPs:' "$test"; then
    echo "FAIL: $test is missing a '# CAPs:' header line" >&2
    fail=1
    continue
  fi
  caps_block=$(awk '/^# *CAPs:/{flag=1} flag && /^#?[[:space:]]*$/{exit} flag' "$test" \
    | sed 's/^#[[:space:]]*CAPs:[[:space:]]*//; s/^#//')
  for cap_in_test in $(echo "$caps_block" | tr ',' '\n' | tr -s '[:space:]' '\n' \
      | grep -E '^[a-z]+\.[a-z-]+$' || true); do
    found=0
    for k in "${known_caps[@]}"; do
      if [[ "$k" == "$cap_in_test" ]]; then found=1; break; fi
    done
    if [[ $found -eq 0 ]]; then
      echo "FAIL: $test references unknown CAP: $cap_in_test" >&2
      fail=1
    fi
  done
done

# 3. Every ready+ story must list ≥ 1 CAP id in its §9 bullet list.
for story in docs/stories/HC-*.md; do
  [[ -e "$story" ]] || continue
  status=$(awk '/^status:/{print $2; exit}' "$story")
  case "$status" in
    ready|in-progress|shipped) ;;
    *) continue ;;
  esac
  # §9 uses plain backtick-quoted CAP ids: - `cap.id.name` — description
  if ! grep -E -q '^[[:space:]]*-[[:space:]]+`[a-z]+\.[a-z-]+`' "$story"; then
    echo "FAIL: $story (status $status) lacks CAP ids in §9 (expected '- \`cap.id\`' bullets)" >&2
    fail=1
  fi
done

if [[ $fail -eq 0 ]]; then
  echo "verify-traceability: ok (${#known_caps[@]} CAP(s) tracked)."
fi
exit $fail
