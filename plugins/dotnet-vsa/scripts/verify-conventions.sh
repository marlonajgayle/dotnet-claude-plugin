#!/usr/bin/env bash
# The Agent Verification Checklist as a script. Used by the `verify` skill, the Stop hook
# and the implementer and reviewer agents, so all of them share one implementation.
#
# Usage: verify-conventions.sh [options]
#   --root DIR            repo to verify (default: current directory)
#   --changed-since SHA   only check .cs/.csproj files changed since SHA (plus untracked ones)
#   --no-build            skip `dotnet build`
#   --format              also run `dotnet format --verify-no-changes`
#   --tests               also run `dotnet test` when a test project exists
#   --test-filter EXPR    pass EXPR to `dotnet test --filter` (implies --tests)
#
# Prints a pass/fail table, the findings, and a one-line summary. Exit 0 when nothing
# FAILs (WARN does not fail), 1 when something does, 3 when no API project was found.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/conventions.sh
. "$SCRIPT_DIR/lib/conventions.sh"

ROOT_ARG="$PWD"; SINCE=""; DO_BUILD=1; DO_FORMAT=0; DO_TESTS=0; TEST_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT_ARG="$2"; shift 2 ;;
    --changed-since) SINCE="$2"; shift 2 ;;
    --no-build) DO_BUILD=0; shift ;;
    --format) DO_FORMAT=1; shift ;;
    --tests) DO_TESTS=1; shift ;;
    --test-filter) DO_TESTS=1; TEST_FILTER="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "verify-conventions: unknown option $1" >&2; exit 64 ;;
  esac
done

DVSA_INPUT=""
dvsa_discover "$ROOT_ARG"
if [ -z "$DVSA_API_DIR" ]; then
  echo "verify: no ASP.NET Core project (Sdk=\"Microsoft.NET.Sdk.Web\") found under $DVSA_ROOT. Set apiProject in .claude/dotnet-vsa.json."
  exit 3
fi
conv_init

# --- files in scope ----------------------------------------------------------------------
FILES="$(mktemp "${TMPDIR:-/tmp}/dvsa-files.XXXXXX")"
FINDINGS="$(mktemp "${TMPDIR:-/tmp}/dvsa-findings.XXXXXX")"
trap 'rm -f "$FILES" "$FINDINGS"' EXIT

if [ -n "$SINCE" ]; then
  {
    git -C "$DVSA_ROOT" diff --name-only "$SINCE" -- '*.cs' '*.csproj' 2>/dev/null
    git -C "$DVSA_ROOT" ls-files --others --exclude-standard -- '*.cs' '*.csproj' 2>/dev/null
  } | sort -u | while read -r f; do
    abs="$DVSA_ROOT/$f"
    case "$abs" in "$DVSA_API_DIR"/*) [ -f "$abs" ] && printf '%s\n' "$abs" ;; esac
  done > "$FILES"
  SCOPE="$(wc -l < "$FILES" | tr -d ' ') file(s) changed since ${SINCE:0:8}"
else
  dvsa_find "$DVSA_API_DIR" \( -name '*.cs' -o -name '*.csproj' \) | grep -v '/Migrations/' > "$FILES"
  SCOPE="whole API project ($(wc -l < "$FILES" | tr -d ' ') files)"
fi

while read -r f; do conv_check_file "$f"; done < "$FILES" > "$FINDINGS"

# --- build / format / tests --------------------------------------------------------------
TARGET="${DVSA_SLN:-$DVSA_API_PROJECT}"
BUILD_STATUS="SKIP"; BUILD_DETAIL="--no-build"
if [ "$DO_BUILD" = 1 ]; then
  if ! dvsa_have dotnet; then
    BUILD_STATUS="FAIL"; BUILD_DETAIL="dotnet not found on PATH"
  else
    out="$(dotnet build "$TARGET" -nologo -v q -clp:ErrorsOnly 2>&1)"; rc=$?
    if [ $rc -eq 0 ]; then
      BUILD_STATUS="PASS"; BUILD_DETAIL="clean"
    else
      BUILD_STATUS="FAIL"
      BUILD_DETAIL="$(printf '%s\n' "$out" | grep -E 'error [A-Z]+[0-9]+' | sort -u | wc -l | tr -d ' ') error(s)"
      printf '%s\n' "$out" | grep -E 'error [A-Z]+[0-9]+' | sort -u | head -n 15 | while read -r line; do
        conv_emit FAIL build "-" "$line"
      done >> "$FINDINGS"
    fi
  fi
fi

FORMAT_STATUS="SKIP"; FORMAT_DETAIL="pass --format to check"
if [ "$DO_FORMAT" = 1 ] && dvsa_have dotnet; then
  if [ -n "$SINCE" ] && [ -s "$FILES" ]; then
    # shellcheck disable=SC2046
    out="$(cd "$DVSA_ROOT" && dotnet format "$TARGET" --verify-no-changes -v q --include $(sed "s|^$DVSA_ROOT/||" "$FILES" | grep '\.cs$' | tr '\n' ' ') 2>&1)"; rc=$?
  else
    out="$(dotnet format "$TARGET" --verify-no-changes -v q 2>&1)"; rc=$?
  fi
  if [ $rc -eq 0 ]; then FORMAT_STATUS="PASS"; FORMAT_DETAIL="no changes needed"
  else
    FORMAT_STATUS="WARN"; FORMAT_DETAIL="$(printf '%s\n' "$out" | grep -c 'error\|warning') file issue(s); run dotnet format"
  fi
fi

TEST_PROJECTS="$(dvsa_test_projects)"
if [ -z "$TEST_PROJECTS" ]; then
  TEST_STATUS="NONE"; TEST_DETAIL="no test project (bootstrap-tests)"
elif [ "$DO_TESTS" = 1 ]; then
  if [ -n "$TEST_FILTER" ]; then
    out="$(dotnet test "$TARGET" -nologo -v q --filter "$TEST_FILTER" 2>&1)"; rc=$?
  else
    out="$(dotnet test "$TARGET" -nologo -v q 2>&1)"; rc=$?
  fi
  summary="$(printf '%s\n' "$out" | grep -E '(Passed|Failed)!|Total tests|total:' | tail -n 1 | sed 's/^[[:space:]]*//')"
  if [ $rc -ne 0 ]; then
    TEST_STATUS="FAIL"; conv_emit FAIL tests "-" "${summary:-dotnet test failed}" >> "$FINDINGS"
    TEST_DETAIL="${summary:-exit $rc}"
  elif [ -z "$summary" ]; then
    # dotnet test exits 0 when a filter matches nothing. That is not a pass.
    TEST_STATUS="SKIP"; TEST_DETAIL="no tests ran"
  else
    TEST_STATUS="PASS"; TEST_DETAIL="$summary"
  fi
  [ -n "$TEST_FILTER" ] && TEST_DETAIL="$TEST_DETAIL (filter: $TEST_FILTER)"
else
  TEST_STATUS="SKIP"; TEST_DETAIL="$(printf '%s\n' "$TEST_PROJECTS" | wc -l | tr -d ' ') test project(s); pass --tests to run"
fi

# --- report ------------------------------------------------------------------------------
count() { awk -F'\t' -v l="$1" -v c="$2" '$1==l && $2==c' "$FINDINGS" | wc -l | tr -d ' '; }
row() {
  local label="$1" check="$2" noun="$3" p w f status detail
  p="$(count PASS "$check")"; w="$(count WARN "$check")"; f="$(count FAIL "$check")"
  if [ "$f" -gt 0 ]; then status="FAIL"; elif [ "$w" -gt 0 ]; then status="WARN"
  elif [ "$p" -gt 0 ] || [ "$noun" = "-" ]; then status="PASS"; else status="n/a"; fi
  if [ "$noun" = "-" ]; then detail=""; else detail="$p $noun"; fi
  [ "$w" -gt 0 ] && detail="${detail:+$detail, }$w warning(s)"
  [ "$f" -gt 0 ] && detail="${detail:+$detail, }$f failing"
  [ -z "$detail" ] && detail="clean"
  printf '| %s | %s | %s |\n' "$label" "$status" "$detail"
}

echo "## verify: $SCOPE"
echo
echo "| Check | Result | Detail |"
echo "|---|---|---|"
printf '| Build | %s | %s |\n' "$BUILD_STATUS" "$BUILD_DETAIL"
row "Handler DI" handler-di "handlers registered"
row "Outbox dispatch" outbox "events dispatched"
row "Endpoint authorization" endpoint-auth "endpoints secured"
row "Rate limiting" rate-limit "endpoints limited"
row "Soft-delete filter" soft-delete "queries filtered"
row "Phantom navigations" phantom-nav "-"
row "UTC DateTime kinds" utc-kinds "DTOs stamped UTC"
row "csproj compile items" csproj "-"
printf '| Formatting | %s | %s |\n' "$FORMAT_STATUS" "$FORMAT_DETAIL"
printf '| Tests | %s | %s |\n' "$TEST_STATUS" "$TEST_DETAIL"

if grep -qE '^(FAIL|WARN)' "$FINDINGS"; then
  echo
  echo "### Findings"
  awk -F'\t' '$1=="FAIL"{printf "- **FAIL** [%s] `%s` %s\n", $2, $3, $4}' "$FINDINGS"
  awk -F'\t' '$1=="WARN"{printf "- WARN [%s] `%s` %s\n", $2, $3, $4}' "$FINDINGS"
fi

FAILS="$(grep -c '^FAIL' "$FINDINGS")"
[ "$BUILD_STATUS" = FAIL ] && [ "$(count FAIL build)" -eq 0 ] && FAILS=$((FAILS + 1))

echo
if [ "$FAILS" -eq 0 ]; then
  b="build clean"; [ "$BUILD_STATUS" = SKIP ] && b="build skipped"
  line="verify: $b, $(count PASS handler-di) handlers registered, $(count PASS outbox) events dispatched, $(count PASS endpoint-auth) endpoints secured."
else
  line="verify: $FAILS failing check(s). Fix them before reporting the work as done."
fi
[ "$TEST_STATUS" = NONE ] && line="$line tests: none (bootstrap-tests)."
echo "$line"

[ "$FAILS" -eq 0 ]
