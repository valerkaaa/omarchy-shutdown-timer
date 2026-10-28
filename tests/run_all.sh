#!/usr/bin/env bash
# run_all.sh — run every test in tests/ and report a single verdict.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
for t in "$DIR"/test_*.sh; do
  name=$(basename "$t")
  printf '\n===== %s =====\n' "$name"
  if timeout 180 bash "$t"; then
    :
  else
    echo ">>> $name FAILED"
    fail=1
  fi
done
printf '\n'
if (( fail )); then echo "SUITE: FAILURES"; exit 1; else echo "SUITE: ALL GREEN"; fi
