#!/usr/bin/env bash
# Runs the plugin's test suite: every tests/test-*.sh, or the ones named on the command line.
# Needs bash, git, jq and perl (what the hooks themselves need). No .NET SDK required.
#
# Usage: tests/run.sh [test-file ...]
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

for tool in git jq perl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "tests/run.sh: $tool is required" >&2; exit 1; }
done

if [ $# -gt 0 ]; then files="$*"; else files="$(ls test-*.sh)"; fi
failed=0
for f in $files; do
  bash "$(basename "$f")" || failed=$((failed + 1))
done
if [ "$failed" -eq 0 ]; then echo "All test files passed."; else echo "$failed test file(s) failed."; fi
[ "$failed" -eq 0 ]
