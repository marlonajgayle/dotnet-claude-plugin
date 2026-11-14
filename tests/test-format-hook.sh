#!/usr/bin/env bash
# hooks/format-csharp.sh: starts `dotnet format` for C# files only. A fake dotnet on PATH records
# each call, so no SDK is needed.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fakebin="$T_TMP/fakebin"; mkdir -p "$fakebin"
calls="$T_TMP/dotnet-calls"
cat > "$fakebin/dotnet" <<'SH'
#!/usr/bin/env bash
printf '%s|%s\n' "$*" "$(cat)" >> "$FAKE_DOTNET_LOG"
exit "${FAKE_DOTNET_RC:-0}"
SH
chmod +x "$fakebin/dotnet"
export PATH="$fakebin:$PATH" FAKE_DOTNET_LOG="$calls"

src="$T_TMP/src"; mkdir -p "$src"
for f in Order.cs README.md appsettings.json Api.csproj; do echo x > "$src/$f"; done
edited() { : > "$calls"; run_hook format-csharp.sh "$(jq -n --arg f "$1" '{tool_name: "Edit", tool_input: {file_path: $f}}')"; }

edited "$src/Order.cs"
expect_rc 'C#: exit 0 when dotnet format succeeds' 0
expect_contains 'C#: runs the format script' "$(cat "$calls")" 'run --file'
expect_contains 'C#: passes the payload through' "$(cat "$calls")" "$src/Order.cs"

for f in README.md appsettings.json Api.csproj; do
  edited "$src/$f"
  expect_allowed "skips $f"
  expect_eq "does not start dotnet for $f" "$(cat "$calls")" ''
done
edited "$src/Missing.cs"; expect_allowed 'skips a file that does not exist'
expect_eq 'does not start dotnet for a missing file' "$(cat "$calls")" ''

FAKE_DOTNET_RC=2 edited "$src/Order.cs"
expect_rc 'C#: a formatting failure passes exit 2 through' 2

t_done
