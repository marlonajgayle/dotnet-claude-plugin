#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit): committed EF Core migrations are immutable.
#   - A migration file tracked by git is blocked: add a new migration instead.
#   - The model snapshot may change while a new, uncommitted migration sits next to it
#     (that is what `dotnet ef migrations add` produces). Otherwise the user is asked.
#   - New, untracked migration files are allowed.
. "$(dirname "$0")/../scripts/lib/common.sh"

dvsa_read_input
dvsa_have jq || exit 0
file="$(dvsa_in '.tool_input.file_path')"
case "$file" in */Migrations/*.cs) ;; *) exit 0 ;; esac

dir="$(dirname "$file")"
[ -d "$dir" ] || exit 0
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
base="$(basename "$file")"

case "$base" in
  *ModelSnapshot.cs)
    if [ -n "$(git -C "$dir" ls-files --others --exclude-standard -- '*.cs' 2>/dev/null | grep -v ModelSnapshot)" ]; then
      exit 0
    fi
    reason="dotnet-vsa: hand-editing $base with no new migration beside it puts the snapshot out of step with the migrations. Normally the snapshot changes only through dotnet ef migrations add / remove (see the ef-add-migration skill)."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' \
      "$(printf '%s' "$reason" | dvsa_json_string)"
    exit 0
    ;;
esac

if git -C "$dir" ls-files --error-unmatch -- "$base" >/dev/null 2>&1; then
  dvsa_block "dotnet-vsa: $base is a committed migration, and committed or applied migrations are immutable: other databases may already have run it. Change the model and add a new migration with the ef-add-migration skill."
fi
exit 0
