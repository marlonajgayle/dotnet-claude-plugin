#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit): convention feedback on the file Claude just changed.
# Advisory: it never blocks, because the fix (say, registering the handler) is often the
# agent's very next edit. Findings reach Claude as additionalContext. The Stop hook makes
# the FAIL-level ones binding before the turn can end.
. "$(dirname "$0")/../scripts/lib/common.sh"
. "$DVSA_PLUGIN_ROOT/scripts/lib/conventions.sh"

dvsa_read_input
dvsa_have jq || exit 0
file="$(dvsa_in '.tool_input.file_path')"
case "$file" in *.cs|*.csproj) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

dvsa_discover "$(dirname "$file")"
[ -n "$DVSA_API_DIR" ] || exit 0
case "$file" in "$DVSA_API_DIR"/*) ;; *) exit 0 ;; esac
conv_init || exit 0

findings="$(conv_check_file "$file" | awk -F'\t' '$1=="FAIL"||$1=="WARN" {printf "- %s [%s] %s: %s\n", $1, $2, $3, $4}')"
[ -n "$findings" ] || exit 0

dvsa_emit_context PostToolUse "dotnet-vsa conventions check for $(conv_rel "$file"):
$findings
FAIL items will block the end of the turn (stop-verify) until fixed. WARN items are advisory."
exit 0
