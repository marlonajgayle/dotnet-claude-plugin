#!/usr/bin/env bash
# hooks/guard-bash.sh: which Bash tool calls are blocked, and which are left alone.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

tmp="$T_TMP"
# A .NET repo on main, the same repo layout on a feature branch, and a repo with no .NET in it.
api_main="$tmp/api-main"; t_fixture_repo "$api_main"
api_feature="$tmp/api-feature"; t_fixture_repo "$api_feature"; git -C "$api_feature" checkout -q -b feature/orders
plain_main="$tmp/plain-main"; t_repo "$plain_main"
unprotected="$tmp/api-unprotected"; t_fixture_repo "$unprotected"
mkdir -p "$unprotected/.claude"; echo '{"protectMain": false}' > "$unprotected/.claude/dotnet-vsa.json"
custom_env="$tmp/api-custom-env"; t_fixture_repo "$custom_env"
mkdir -p "$custom_env/.claude"; echo '{"localEnvironment": "Dev"}' > "$custom_env/.claude/dotnet-vsa.json"

# guard CWD COMMAND [BACKGROUND]
guard() {
  local payload
  payload="$(jq -n --arg cmd "$2" --arg cwd "$1" --argjson bg "${3:-false}" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: ({command: $cmd} + (if $bg then {run_in_background: true} else {} end))}')"
  run_hook guard-bash.sh "$payload"
}
blocks() { guard "${3:-$api_feature}" "$1"; expect_blocked "blocks: $1" "${2:-}"; }
allows() { guard "${2:-$api_feature}" "$1"; expect_allowed "allows: $1"; }

# --- commands that never exit --------------------------------------------------------------
blocks 'dotnet run' 'run_in_background'
blocks 'dotnet run --project src/Fixture.Api'
blocks 'dotnet watch run'
blocks 'dotnet watch --project src/Fixture.Api test'
blocks 'ASPNETCORE_ENVIRONMENT=Local dotnet run'
blocks 'npm start'
blocks 'npm run dev'
blocks 'pnpm dev'
blocks 'npx expo start'
blocks 'dotnet test --watch'
blocks 'docker compose up'
blocks 'docker compose -f docker-compose.yml up --build'
blocks 'docker-compose up'
blocks 'docker compose logs -f api'
blocks 'tail -f logs/app.log'
blocks 'tail -n 50 -F logs/app.log'
# ...found anywhere in a compound command
blocks 'cd src/Fixture.Api && dotnet run'
blocks 'dotnet build; dotnet run'
blocks 'dotnet build | tee build.log && tail -f build.log'
blocks 'bash -c "dotnet run"'
blocks 'sudo dotnet run'

guard "$api_feature" 'dotnet run' true;             expect_allowed 'allows: dotnet run with run_in_background'
guard "$api_feature" 'docker compose up' true;      expect_allowed 'allows: docker compose up with run_in_background'
allows 'dotnet run &'
allows 'dotnet run > api.log 2>&1 &'
allows 'dotnet run --file scripts/tool.cs'
allows 'dotnet run scripts/tool.cs'
allows 'dotnet build'
allows 'dotnet test'
allows 'dotnet build 2>&1 | tail -n 20'
allows 'docker compose up -d'
allows 'docker compose up --detach'
allows 'docker compose up --wait'
allows 'docker compose logs api'
allows 'tail -n 50 logs/app.log'
allows 'npm install'
allows 'npm run build'
# ...and a blocked command that is only text inside a quoted argument is not a command
allows 'echo "dotnet run; tail -f app.log"'
allows "grep -rn 'dotnet watch' docs"
allows 'git commit -m "fix: stop dotnet run && tail -f from hanging"'
allows 'git commit -m "docs: describe the --watch flag"'

# --- git -----------------------------------------------------------------------------------
blocks 'git commit -m "feat: x"' "you are on 'main'" "$api_main"
blocks 'git add -A && git commit -m "feat: x"' "you are on 'main'" "$api_main"
blocks 'git -C . commit -m "feat: x"' "you are on 'main'" "$api_main"
allows 'git commit -m "feat: x"' "$api_feature"
allows 'git checkout -b feature/x && git commit -m "feat: x"' "$api_main"
allows 'git switch -c feature/x && git commit -m "feat: x"' "$api_main"
allows 'git commit -m "feat: x"' "$plain_main"      # not a .NET repo
allows 'git commit -m "feat: x"' "$unprotected"     # protectMain: false
allows 'git status' "$api_main"
allows 'git log --oneline | head -n 5' "$api_main"

blocks 'git push --force origin main' 'force-push'
blocks 'git push -f origin master' 'force-push'
blocks 'git push --force-with-lease origin main' 'force-push'
blocks 'git push origin +main'
blocks 'git push origin +HEAD:main'
blocks 'git push --force origin HEAD:refs/heads/main'
blocks 'git push --force' 'force-push' "$api_main"   # no refspec: pushes the current branch
allows 'git push --force origin feature/orders'
allows 'git push --force-with-lease'
allows 'git push -u origin feature/orders'
allows 'git push origin main' "$api_main"            # a plain push is the remote's call

# --- docker volumes ------------------------------------------------------------------------
blocks 'docker compose down -v' 'volume'
blocks 'docker compose down --volumes'
blocks 'docker-compose down -v --remove-orphans'
blocks 'docker volume rm fixture_sqldata'
blocks 'docker volume prune -f'
blocks 'docker system prune --volumes'
allows 'docker compose down'
allows 'docker compose down --remove-orphans'
allows 'docker volume ls'

# --- dotnet ef -----------------------------------------------------------------------------
blocks 'dotnet ef database drop --force' 'ASPNETCORE_ENVIRONMENT=Local'
blocks 'dotnet ef migrations remove' 'ASPNETCORE_ENVIRONMENT=Local'
blocks 'ASPNETCORE_ENVIRONMENT=Production dotnet ef database drop'
blocks 'ASPNETCORE_ENVIRONMENT=Local dotnet ef database drop' 'ASPNETCORE_ENVIRONMENT=Dev' "$custom_env"
blocks 'dotnet ef database update --connection "Server=sql-prod.example.com;Database=Shop;User Id=sa"' 'non-local'
allows 'ASPNETCORE_ENVIRONMENT=Local dotnet ef database drop --force'
allows 'ASPNETCORE_ENVIRONMENT=Local dotnet ef migrations remove'
allows 'dotnet ef database drop --environment Local'
allows 'ASPNETCORE_ENVIRONMENT=Dev dotnet ef database drop' "$custom_env"
allows 'dotnet ef database update'
allows 'dotnet ef database update --connection "Server=localhost,1433;Database=Shop;User Id=sa"'
allows 'dotnet ef migrations add AddOrders'
allows 'dotnet ef migrations list'
allows 'dotnet ef migrations script --idempotent'

# --- rm -rf --------------------------------------------------------------------------------
blocks 'rm -rf src' 'rm -rf src'
blocks 'rm -rf /'
blocks 'rm -fr ~/Repos/shop'
blocks 'rm -r -f src/Fixture.Api/Features'
blocks 'rm --recursive --force src'
blocks 'rm -rf bin ../other'
blocks 'dotnet clean && rm -rf .'
allows 'rm -rf bin obj'
allows 'rm -rf src/Fixture.Api/bin src/Fixture.Api/obj'
allows 'rm -rf node_modules'
allows 'rm -rf /tmp/dvsa-scratch'
allows 'rm -rf "$TMPDIR/dvsa-scratch"'
allows 'rm -r src/Fixture.Api/Features/Old'    # no -f: rm asks, or fails loudly
allows 'rm -f src/Fixture.Api/Old.cs'
allows 'rm src/Fixture.Api/Old.cs'

# --- payloads the hook must ignore ---------------------------------------------------------
run_hook guard-bash.sh '{"tool_name":"Bash","tool_input":{}}';  expect_allowed 'allows: payload without a command'
run_hook guard-bash.sh '';                                      expect_allowed 'allows: empty payload'
run_hook guard-bash.sh 'not json';                              expect_allowed 'allows: payload that is not JSON'

t_done
