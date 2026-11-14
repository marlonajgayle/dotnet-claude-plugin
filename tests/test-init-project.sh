#!/usr/bin/env bash
# skills/init-project/scaffold.sh: what it writes, what it refuses, and that the plugin's own
# discovery and checks understand the result. tests/e2e/run.sh builds it with the real SDK.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

scaffold="$PLUGIN_DIR/skills/init-project/scaffold.sh"
run() { OUT="$(bash "$scaffold" "$@" 2>"$T_TMP/stderr")"; RC=$?; ERR="$(cat "$T_TMP/stderr")"; }

repo="$T_TMP/shop"; t_repo "$repo"
run "$repo" Contoso.Shop
expect_rc 'writes a new project' 0
api="src/Contoso.Shop.Api"
for f in Contoso.Shop.slnx compose.yaml "$api/Contoso.Shop.Api.csproj" "$api/Program.cs" \
         "$api/SharedKernel/Result.cs" "$api/Infrastructure/Outbox/OutboxDispatcher.cs" \
         "$api/Features/.gitkeep" "$api/Domain/.gitkeep" .claude/dotnet-vsa.json .env "$api/appsettings.Local.json"; do
  if [ -f "$repo/$f" ]; then ok; else bad "wrote $f"; fi
done
expect_contains 'lists what it wrote' "$OUT" "$api/Program.cs"
expect_eq 'no template token is left' "$(grep -rl 'DvsaTemplate\|__USER_SECRETS_ID__' "$repo" --exclude-dir=.git)" ''
expect_contains 'namespaces use the app name' "$(cat "$repo/$api/Program.cs")" 'using Contoso.Shop.Api.Infrastructure.Outbox;'
expect_contains 'the solution names the project' "$(cat "$repo/Contoso.Shop.slnx")" "$api/Contoso.Shop.Api.csproj"
if grep -Eq '<UserSecretsId>[0-9a-f-]{36}</UserSecretsId>' "$repo/$api/Contoso.Shop.Api.csproj"; then ok; else bad 'a user-secrets id is generated'; fi

# Secrets: generated, the same in both local files, and only there.
pw="$(sed -n 's/^MSSQL_SA_PASSWORD=//p' "$repo/.env")"
if [ "${#pw}" -ge 20 ]; then ok; else bad 'a generated sa password'; fi
expect_contains 'Local connection string uses the password' "$(cat "$repo/$api/appsettings.Local.json")" "Password=$pw;"
expect_contains 'Local connection string names the database' "$(cat "$repo/$api/appsettings.Local.json")" 'Database=ContosoShop;'
expect_eq 'the password appears only in the two local files' \
  "$(grep -rlF "$pw" "$repo" --exclude-dir=.git | sed "s|^$repo/||" | sort | tr '\n' ' ')" ".env $api/appsettings.Local.json "
expect_eq 'git ignores both local files' "$(git -C "$repo" status --porcelain --ignored | grep '^!!' | sed 's/^!! //' | sort | tr '\n' ' ')" ".env $api/appsettings.Local.json "
expect_eq 'appsettings.json has no connection string value' "$(jq -r '.ConnectionStrings.Default' "$repo/$api/appsettings.json")" ''
run_hook guard-config-secrets.sh "$(jq -n --arg f "$repo/$api/appsettings.json" --rawfile c "$repo/$api/appsettings.json" '{tool_name: "Write", tool_input: {file_path: $f, content: $c}}')"
expect_allowed 'the secrets guard accepts the generated appsettings.json'

# Valid JSON, and discovery finds everything from the config.
for f in .claude/dotnet-vsa.json "$api/appsettings.json" "$api/appsettings.Development.json" "$api/appsettings.Local.json" "$api/Properties/launchSettings.json"; do
  if jq empty "$repo/$f" 2>/dev/null; then ok; else bad "valid JSON: $f"; fi
done
disc="$(bash "$PLUGIN_DIR/scripts/discover.sh" "$repo")"
expect_contains 'discover: solution' "$disc" 'SLN=Contoso.Shop.slnx'
expect_contains 'discover: API project' "$disc" "API_PROJECT=$api/Contoso.Shop.Api.csproj"
expect_contains 'discover: outbox dispatcher' "$disc" "OUTBOX_DISPATCHER=$api/Infrastructure/Outbox/OutboxDispatcher.cs"
expect_contains 'discover: DbContext' "$disc" "DBCONTEXT=$api/Infrastructure/Persistence/ApplicationDbContext.cs"
expect_contains 'discover: authorization policies' "$disc" "AUTH_POLICIES=$api/Infrastructure/Authorization/AuthorizationPolicies.cs"
expect_contains 'discover: rate-limit policies' "$disc" "RATE_LIMIT_POLICIES=$api/Infrastructure/RateLimiting/RateLimitPolicies.cs"
expect_contains 'discover: health URL from launchSettings' "$disc" 'HEALTH_URL=https://localhost:7143/health'

report="$(bash "$PLUGIN_DIR/scripts/verify-conventions.sh" --root "$repo" --no-build 2>&1)"; RC=$?
expect_eq 'convention checks pass on the empty project' "$RC" 0
expect_lacks 'no warnings on the empty project' "$report" 'WARN'

# The example branch in the dispatcher's comment must not satisfy the outbox check for a real event.
mkdir -p "$repo/$api/Domain/Orders"
printf 'namespace Contoso.Shop.Api.Domain.Orders;\n\npublic sealed record EventName(System.Guid Id) : IDomainEvent;\npublic sealed record OrderPlaced(System.Guid Id) : IDomainEvent;\n' > "$repo/$api/Domain/Orders/OrderEvents.cs"
report="$(bash "$PLUGIN_DIR/scripts/verify-conventions.sh" --root "$repo" --no-build 2>&1)"
expect_contains 'outbox: an event without a branch fails' "$report" 'OrderPlaced has no nameof(OrderPlaced) branch'
expect_contains 'outbox: the comment example does not count' "$report" 'EventName has no nameof(EventName) branch'

# --- refusals ------------------------------------------------------------------------------
run "$repo" Other;               expect_rc 'refuses a repo that already has a project' 2
expect_contains 'says why' "$ERR" 'already has a .NET solution or project'
fresh="$T_TMP/fresh"; t_repo "$fresh"
for name in shop 1Shop 'My Shop' Shop- .Shop Shop..Api ''; do
  run "$fresh" "$name"; expect_rc "refuses the name '$name'" 2
done
run "$fresh"; expect_rc 'needs two arguments' 64
run "$T_TMP/missing" Shop; expect_rc 'refuses a missing directory' 2

clash="$T_TMP/clash"; t_repo "$clash"; echo 'keep me' > "$clash/compose.yaml"
run "$clash" Shop
expect_rc 'refuses to overwrite a file' 2
expect_contains 'names the file' "$ERR" 'compose.yaml'
expect_eq 'leaves the existing file alone' "$(cat "$clash/compose.yaml")" 'keep me'
expect_eq 'writes nothing when it refuses' "$(cd "$clash" && find . -path ./.git -prune -o -type f -print | sort | tr '\n' ' ')" './compose.yaml '

t_done
