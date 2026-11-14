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

# --- appliedMigrationsCommand runs only once the person trusts it -----------------------------
export DVSA_TRUST_FILE="$T_TMP/trusted-commands"
probe_repo="$T_TMP/probe"; t_fixture_repo "$probe_repo"
mig="$probe_repo/src/Fixture.Api/Migrations"; mkdir -p "$mig"
touch "$mig/20240101000000_Init.cs" "$mig/20240102000000_Orders.cs"
marker="$T_TMP/probe-ran"
cmd="touch '$marker'; echo 20240101000000_Init"
mkdir -p "$probe_repo/.claude"
jq -n --arg c "$cmd" '{appliedMigrationsCommand: $c}' > "$probe_repo/.claude/dotnet-vsa.json"
root="$(git -C "$probe_repo" rev-parse --show-toplevel)"

started "$probe_repo" s5
expect_contains 'untrusted command: says it was not run' "$OUT" 'appliedMigrationsCommand is not trusted on this machine, so it was not run'
expect_contains 'untrusted command: names the trust script' "$OUT" 'trust-command.sh'
if [ -e "$marker" ]; then bad 'untrusted command: never runs'; else ok; fi

trust_out="$(bash "$PLUGIN_DIR/scripts/trust-command.sh" "$probe_repo" </dev/null 2>&1)"; RC=$?
expect_eq 'trust-command: refuses without a terminal' "$RC" 2
if [ -f "$DVSA_TRUST_FILE" ]; then bad 'trust-command: writes nothing without a terminal'; else ok; fi

jq -cn --arg r "$root" --arg c "$cmd" '{root: $r, command: $c}' > "$DVSA_TRUST_FILE"
started "$probe_repo" s5
expect_contains 'trusted command: reports unapplied migrations' "$OUT" 'unapplied locally: 1 (20240102000000_Orders)'
if [ -e "$marker" ]; then ok; else bad 'trusted command: runs'; fi

# Changing the command in the repo makes it untrusted again.
rm -f "$marker"
jq -n --arg c "$cmd; echo changed" '{appliedMigrationsCommand: $c}' > "$probe_repo/.claude/dotnet-vsa.json"
started "$probe_repo" s5
expect_contains 'changed command: untrusted again' "$OUT" 'is not trusted on this machine'
if [ -e "$marker" ]; then bad 'changed command: never runs'; else ok; fi

bash "$PLUGIN_DIR/scripts/trust-command.sh" --revoke "$probe_repo" >/dev/null
expect_eq 'trust-command --revoke: forgets the repo' "$(cat "$DVSA_TRUST_FILE")" ''
unset DVSA_TRUST_FILE

# --- repos the plugin does not apply to ------------------------------------------------------
plain="$T_TMP/plain"; t_repo "$plain"
started "$plain" s3; expect_allowed 'silent in a repo without .NET'
mkdir -p "$T_TMP/loose"
if git -C "$T_TMP/loose" rev-parse --is-inside-work-tree >/dev/null 2>&1; then ok
else started "$T_TMP/loose" s4; expect_allowed 'silent outside git'; fi

t_done
