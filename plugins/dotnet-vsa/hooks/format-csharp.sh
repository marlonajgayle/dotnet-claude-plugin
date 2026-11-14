#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit): runs scripts/format-csharp.cs (dotnet format on the edited
# file) only when the edited file is C#. Starting `dotnet run --file` costs a second or two even
# when it has nothing to do, so every other edit (Markdown, JSON, YAML...) stops here instead.
# Exit codes pass through: 2 means formatting failed and stderr is shown to Claude.
. "$(dirname "$0")/../scripts/lib/common.sh"

dvsa_read_input
if dvsa_have jq; then
  file="$(dvsa_in '.tool_input.file_path')"
else
  # Without jq, a crude look at the payload: enough to tell a .cs path from anything else.
  file="$(printf '%s' "$DVSA_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi
case "$file" in *.cs|*.CS) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0
dvsa_have dotnet || exit 0

printf '%s' "$DVSA_INPUT" | dotnet run --file "$DVSA_PLUGIN_ROOT/scripts/format-csharp.cs"
