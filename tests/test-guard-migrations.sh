#!/usr/bin/env bash
# hooks/guard-migrations.sh: committed migrations are immutable; the snapshot changes only
# alongside a new migration.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo="$T_TMP/api"; t_repo "$repo"
mig="$repo/src/Fixture.Api/Infrastructure/Persistence/Migrations"
mkdir -p "$mig"
echo '// committed migration' > "$mig/20250101120000_Initial.cs"
echo '// committed designer'  > "$mig/20250101120000_Initial.Designer.cs"
echo '// snapshot'            > "$mig/AppDbContextModelSnapshot.cs"
echo '// entity'              > "$repo/src/Fixture.Api/Order.cs"
git -C "$repo" add -A && t_git -C "$repo" commit -q -m "feat: initial migration"

touch_file() { run_hook guard-migrations.sh "$(jq -n --arg f "$1" --arg t "${2:-Edit}" '{tool_name: $t, tool_input: {file_path: $f, new_string: "x", content: "x"}}')"; }

touch_file "$mig/20250101120000_Initial.cs";          expect_blocked 'blocks: Edit of a committed migration' 'committed migration'
touch_file "$mig/20250101120000_Initial.cs" Write;    expect_blocked 'blocks: Write over a committed migration' 'ef-add-migration'
touch_file "$mig/20250101120000_Initial.Designer.cs"; expect_blocked 'blocks: Edit of a committed designer file'

touch_file "$mig/AppDbContextModelSnapshot.cs"
expect_rc 'asks: snapshot edit with no new migration (exit 0)' 0
expect_eq 'asks: permissionDecision is ask' "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" 'ask'
expect_contains 'asks: reason names the snapshot' "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)" 'AppDbContextModelSnapshot.cs'

# A migration that does not exist yet, then one that exists but is untracked.
touch_file "$mig/20250202120000_AddOrders.cs" Write;  expect_allowed 'allows: Write of a new migration'
echo '// new migration' > "$mig/20250202120000_AddOrders.cs"
touch_file "$mig/20250202120000_AddOrders.cs";        expect_allowed 'allows: Edit of an uncommitted migration'
touch_file "$mig/AppDbContextModelSnapshot.cs";       expect_allowed 'allows: snapshot edit beside a new migration'
touch_file "$mig/20250101120000_Initial.cs";          expect_blocked 'blocks: committed migration even with a new one beside it'

touch_file "$repo/src/Fixture.Api/Order.cs";          expect_allowed 'allows: a file outside Migrations/'
touch_file "$repo/docs/Migrations/notes.md";          expect_allowed 'allows: a non-.cs file under a Migrations folder'

# Outside git there is no "committed", so nothing is blocked.
loose="$T_TMP/loose/Migrations"; mkdir -p "$loose"; echo '// m' > "$loose/20250101120000_Initial.cs"
if git -C "$loose" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok   # the temp directory sits inside some git repository; the case cannot be set up here
else
  touch_file "$loose/20250101120000_Initial.cs";      expect_allowed 'allows: a migration outside any git repository'
fi

run_hook guard-migrations.sh ''; expect_allowed 'allows: empty payload'

t_done
