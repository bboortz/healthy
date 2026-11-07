#!/usr/bin/env bash
# Enforce the 150-line cap on memory/*.md and CLAUDE.md.
# MEMORY.md is the index and is explicitly exempt.
# Wired as pre-commit's memory-size hook; also callable standalone.
set -euo pipefail

cap=150
fail=0

for f in memory/*.md; do
  [[ -e "$f" ]] || continue
  [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
  n=$(wc -l < "$f")
  if (( n > cap )); then
    echo "FAIL: $f has $n lines (limit $cap)" >&2
    fail=1
  fi
done

if [[ -f CLAUDE.md ]]; then
  n=$(wc -l < CLAUDE.md)
  if (( n > cap )); then
    echo "FAIL: CLAUDE.md has $n lines (limit $cap)" >&2
    fail=1
  fi
fi

exit "$fail"
