#!/usr/bin/env bash
# Stop: when API code changed this session, build and run the convention checks on the
# changed files before the turn may end. Any FAIL blocks (exit 2, report on stderr) so the
# agent fixes it rather than reporting done.
#
# - Skips when no .cs/.csproj under the API project changed since the session's first commit.
# - Skips when the tree is identical to the last one that verified clean.
# - "fast": true in .claude/dotnet-vsa.json skips the build and keeps only the checks.
# - "stopTests" runs dotnet test as well: "changed" runs the tests whose names contain a
#   changed slice's folder name (Features/<Domain>/<Slice>/), "all" runs every test, "off"
#   (the default) runs none. "stopTestsFilter" is added to the filter; it defaults to
#   "Category!=Integration" so tests that need Docker stay out of the end-of-turn check.
# - Blocks at most 3 times in a row, then lets the turn end and tells the user, so an
#   unfixable or pre-existing failure cannot trap the session in a loop.
. "$(dirname "$0")/../scripts/lib/common.sh"

MAX_BLOCKS=3

dvsa_read_input
dvsa_have jq || exit 0
cwd="$(dvsa_in '.cwd')"; [ -n "$cwd" ] || cwd="$PWD"
git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
dvsa_discover "$cwd"
[ -n "$DVSA_API_DIR" ] || exit 0

sid="$(dvsa_in '.session_id')"
state="$(dvsa_state_dir "${sid:-unknown}")"
since="$(cat "$state/start-sha" 2>/dev/null)"
[ -n "$since" ] || since="$(git -C "$DVSA_ROOT" rev-parse HEAD 2>/dev/null)"
[ -n "$since" ] || exit 0

api_rel="${DVSA_API_DIR#"$DVSA_ROOT"/}"
changed="$( { git -C "$DVSA_ROOT" diff --name-only "$since" -- "$api_rel" 2>/dev/null
              git -C "$DVSA_ROOT" ls-files --others --exclude-standard -- "$api_rel" 2>/dev/null; } \
            | grep -E '\.(cs|csproj)$' | sort -u)"
[ -n "$changed" ] || exit 0

# Fingerprint of the changed API code; unchanged since the last clean run means nothing to do.
fingerprint="$( { git -C "$DVSA_ROOT" diff "$since" -- "$api_rel" 2>/dev/null
                  printf '%s\n' "$changed" | while read -r f; do
                    git -C "$DVSA_ROOT" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || cat "$DVSA_ROOT/$f" 2>/dev/null
                  done; } | cksum | tr -d ' ')"
[ "$fingerprint" = "$(cat "$state/last-verified" 2>/dev/null)" ] && exit 0

set -- --root "$DVSA_ROOT" --changed-since "$since"
[ "$(dvsa_config "$DVSA_ROOT" .fast)" = "true" ] && set -- "$@" --no-build

# Tests, when switched on. A slice is the folder under Features/<Domain>/; its tests are the
# ones whose fully qualified name contains the slice name (<Slice>HandlerTests and so on).
tests_mode="$(dvsa_config "$DVSA_ROOT" .stopTests)"
extra_filter="$(dvsa_config "$DVSA_ROOT" .stopTestsFilter)"
[ -n "$extra_filter" ] || extra_filter="Category!=Integration"
[ "$extra_filter" = "none" ] && extra_filter=""
case "$tests_mode" in
  all)
    if [ -n "$extra_filter" ]; then set -- "$@" --test-filter "$extra_filter"; else set -- "$@" --tests; fi
    ;;
  changed)
    slices="$(printf '%s\n' "$changed" | sed -n 's|.*/Features/[^/]*/\([^/]*\)/.*|\1|p' | sort -u)"
    if [ -n "$slices" ]; then
      filter="$(printf '%s\n' "$slices" | sed 's/^/FullyQualifiedName~/' | paste -sd '|' -)"
      [ -n "$extra_filter" ] && filter="($filter)&$extra_filter"
      set -- "$@" --test-filter "$filter"
    fi
    ;;
esac

report="$(bash "$DVSA_PLUGIN_ROOT/scripts/verify-conventions.sh" "$@" 2>&1)"
rc=$?
summary="$(printf '%s\n' "$report" | tail -n 1)"

if [ $rc -eq 0 ]; then
  printf '%s\n' "$fingerprint" > "$state/last-verified"
  rm -f "$state/blocks"
  printf '{"systemMessage":%s}\n' "$(printf '%s' "$summary" | dvsa_json_string)"
  exit 0
fi
[ $rc -eq 3 ] && exit 0

blocks=$(( $(cat "$state/blocks" 2>/dev/null || echo 0) + 1 ))
if [ "$blocks" -gt "$MAX_BLOCKS" ]; then
  rm -f "$state/blocks"
  msg="dotnet-vsa stop-verify: still failing after $MAX_BLOCKS attempts, so the turn was allowed to end. Run the verify skill to see the open items. $summary"
  printf '{"systemMessage":%s}\n' "$(printf '%s' "$msg" | dvsa_json_string)"
  exit 0
fi
printf '%s\n' "$blocks" > "$state/blocks"

{
  echo "dotnet-vsa stop-verify (attempt $blocks of $MAX_BLOCKS): the API code changed this session and verification failed, so the work is not done yet."
  echo "Fix the FAIL items below, or if one is a false positive, tell the user why instead of reporting success."
  echo
  printf '%s\n' "$report"
} >&2
exit 2
