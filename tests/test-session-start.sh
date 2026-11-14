#!/usr/bin/env bash
# hooks/session-start.sh: the context printed at the start of a session.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

started() { run_hook session-start.sh "$(jq -n --arg cwd "$1" --arg sid "$2" '{hook_event_name: "SessionStart", cwd: $cwd, session_id: $sid}')"; }
version="$(jq -r '.version' "$PLUGIN_DIR/.claude-plugin/plugin.json")"

repo="$T_TMP/shop"; t_fixture_repo "$repo"
started "$repo" s1
expect_rc 'exit 0' 0
expect_contains 'heading' "$OUT" '## dotnet-vsa session context'
expect_contains 'warns about main' "$OUT" '- Branch: **main**.'
expect_contains 'API project' "$OUT" '- API project: src/Fixture.Api/Fixture.Api.csproj'
expect_contains 'outbox dispatcher' "$OUT" 'src/Fixture.Api/Infrastructure/Outbox/OutboxProcessor.cs'
expect_contains 'no test project' "$OUT" 'no test project exists'
expect_eq 'records the starting commit' "$(cat "$CLAUDE_PLUGIN_DATA/sessions/s1/start-sha" 2>/dev/null)" "$(git -C "$repo" rev-parse HEAD)"

# The starting commit survives a later session start (resume, compact).
t_git -C "$repo" commit -q --allow-empty -m "chore: later commit"
first="$(cat "$CLAUDE_PLUGIN_DATA/sessions/s1/start-sha")"
started "$repo" s1
expect_eq 'keeps the first starting commit' "$(cat "$CLAUDE_PLUGIN_DATA/sessions/s1/start-sha")" "$first"

git -C "$repo" checkout -q -b feature/orders
started "$repo" s2
expect_contains 'names a feature branch' "$OUT" '- Branch: feature/orders (0 uncommitted change(s))'

# --- rules notice --------------------------------------------------------------------------
expect_contains 'rules: says when they are not installed' "$OUT" 'path-scoped rules are not installed'
mkdir -p "$repo/.claude/rules/dotnet-vsa"
echo '0.0.1' > "$repo/.claude/rules/dotnet-vsa/.source"
started "$repo" s2
expect_contains 'rules: says when they are older than the plugin' "$OUT" "was installed from dotnet-vsa 0.0.1; the plugin is now $version"
echo "$version" > "$repo/.claude/rules/dotnet-vsa/.source"
started "$repo" s2
expect_lacks 'rules: silent when current' "$OUT" '- Rules:'

# --- repos the plugin does not apply to ------------------------------------------------------
plain="$T_TMP/plain"; t_repo "$plain"
started "$plain" s3; expect_allowed 'silent in a repo without .NET'
mkdir -p "$T_TMP/loose"
if git -C "$T_TMP/loose" rev-parse --is-inside-work-tree >/dev/null 2>&1; then ok
else started "$T_TMP/loose" s4; expect_allowed 'silent outside git'; fi

t_done
