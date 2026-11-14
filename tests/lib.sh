#!/usr/bin/env bash
# Assertions and helpers shared by tests/test-*.sh. Sourced, never run.
# Written for macOS /bin/bash 3.2, like the plugin's own scripts.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PLUGIN_DIR="$REPO_DIR/plugins/dotnet-vsa"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"

T_PASS=0
T_FAIL=0
T_TMP=""

# A scratch directory for this test file, in T_TMP, removed on exit. Discovery skips any
# project whose path contains "test", so the path must not.
t_tmp_init() {
  local base="${TMPDIR:-/tmp}"; base="${base%/}"
  case "$base" in *[Tt]est*) base="/tmp" ;; esac
  while :; do
    T_TMP="$(mktemp -d "$base/dvsa-suite.XXXXXX")"
    case "$T_TMP" in *[Tt]est*) rm -rf "$T_TMP" ;; *) break ;; esac
  done
  T_TMP="$(cd "$T_TMP" && pwd -P)"
  export CLAUDE_PLUGIN_DATA="$T_TMP/plugin-data"
  trap 'rm -rf "${T_TMP:?}"' EXIT
}
t_tmp_init

t_git() { git -c user.name=suite -c user.email=suite@example.invalid -c commit.gpgsign=false "$@"; }

# t_repo DIR: an empty git repository on main with one commit.
t_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" symbolic-ref HEAD refs/heads/main
  t_git -C "$1" commit -q --allow-empty -m "chore: initial commit"
}

# t_fixture_repo DIR: a committed copy of the conventions fixture API.
t_fixture_repo() {
  mkdir -p "$1"
  cp -R "$TESTS_DIR/fixtures/api/." "$1/"
  git -C "$1" init -q
  git -C "$1" symbolic-ref HEAD refs/heads/main
  git -C "$1" add -A
  t_git -C "$1" commit -q -m "chore: fixture"
}

ok()  { T_PASS=$((T_PASS + 1)); }
bad() {
  T_FAIL=$((T_FAIL + 1))
  printf '  FAIL  %s\n' "$1"
  shift
  while [ $# -gt 0 ]; do printf '        %s\n' "$1"; shift; done
}

# run_hook NAME JSON: runs hooks/NAME with JSON on stdin. Sets RC, OUT (stdout), ERR (stderr).
run_hook() {
  local errf="$T_TMP/stderr"
  OUT="$(printf '%s' "$2" | bash "$PLUGIN_DIR/hooks/$1" 2>"$errf")"
  RC=$?
  ERR="$(cat "$errf")"
}

expect_rc() {       # LABEL EXPECTED
  if [ "$RC" -eq "$2" ]; then ok; else bad "$1" "expected exit $2, got $RC" "stdout: $OUT" "stderr: $ERR"; fi
}
expect_blocked() {  # LABEL [SUBSTRING-OF-REASON]
  if [ "$RC" -ne 2 ]; then bad "$1" "expected a block (exit 2), got exit $RC" "stderr: $ERR"; return; fi
  if [ -n "${2:-}" ]; then
    case "$ERR" in *"$2"*) ok ;; *) bad "$1" "blocked, but the reason lacks: $2" "stderr: $ERR" ;; esac
  else ok; fi
}
expect_allowed() {  # LABEL
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then ok
  else bad "$1" "expected a silent exit 0, got exit $RC" "stdout: $OUT" "stderr: $ERR"; fi
}
expect_contains() { # LABEL HAYSTACK NEEDLE
  case "$2" in *"$3"*) ok ;; *) bad "$1" "missing: $3" "in: $2" ;; esac
}
expect_lacks() {    # LABEL HAYSTACK NEEDLE
  case "$2" in *"$3"*) bad "$1" "must not contain: $3" ;; *) ok ;; esac
}
expect_eq() {       # LABEL ACTUAL EXPECTED
  if [ "$2" = "$3" ]; then ok; else bad "$1" "expected: $3" "actual:   $2"; fi
}

t_done() {
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$T_PASS" "$T_FAIL"
  [ "$T_FAIL" -eq 0 ]
}
