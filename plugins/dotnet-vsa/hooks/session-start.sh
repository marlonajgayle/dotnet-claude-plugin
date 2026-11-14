#!/usr/bin/env bash
# SessionStart: orientation that would otherwise take the first minutes of every session.
# stdout becomes session context. Also records the starting commit for stop-verify.
. "$(dirname "$0")/../scripts/lib/common.sh"

dvsa_read_input
if ! dvsa_have jq; then
  echo "dotnet-vsa: jq is not installed, so the plugin's guard hooks are disabled. Install it (brew install jq / apt install jq)."
  exit 0
fi

cwd="$(dvsa_in '.cwd')"; [ -n "$cwd" ] || cwd="$PWD"
git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
dvsa_discover "$cwd"
[ -n "$DVSA_SLN$DVSA_API_PROJECT" ] || exit 0
root="$DVSA_ROOT"
rel() { case "$1" in "$root"/*) printf '%s' "${1#"$root"/}" ;; *) printf '%s' "$1" ;; esac; }

# Starting commit, kept for the whole session (resume and compact keep the first one).
sid="$(dvsa_in '.session_id')"
state="$(dvsa_state_dir "${sid:-unknown}")"
if [ ! -f "$state/start-sha" ]; then
  sha="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904)"
  printf '%s\n' "$sha" > "$state/start-sha"
fi

echo "## dotnet-vsa session context"

branch="$(git -C "$root" branch --show-current 2>/dev/null)"
case "$branch" in
  main|master) echo "- Branch: **$branch**. Create a feature/, bugfix/ or hotfix/ branch before changing code; commits on $branch are blocked." ;;
  "") echo "- Branch: detached HEAD at $(git -C "$root" rev-parse --short HEAD 2>/dev/null)" ;;
  *) echo "- Branch: $branch ($(git -C "$root" status --porcelain 2>/dev/null | wc -l | tr -d ' ') uncommitted change(s))" ;;
esac

if [ -n "$DVSA_SLN" ]; then echo "- Solution: $(rel "$DVSA_SLN")"; else echo "- Solution: not found"; fi
if [ -n "$DVSA_API_PROJECT" ]; then
  echo "- API project: $(rel "$DVSA_API_PROJECT")"
  [ -n "$DVSA_PROGRAM" ] && echo "- Handler registrations: $(rel "$DVSA_PROGRAM")"
  [ -n "$DVSA_OUTBOX" ] && echo "- Outbox dispatcher (string-matched on nameof): $(rel "$DVSA_OUTBOX")"
fi

# Migrations: latest, uncommitted, and unapplied when the project says how to ask the DB.
if [ -n "$DVSA_MIGRATIONS" ] && [ -d "$DVSA_MIGRATIONS" ]; then
  migs="$(ls "$DVSA_MIGRATIONS" 2>/dev/null | grep -E '^[0-9]{14}_.*\.cs$' | grep -v '\.Designer\.cs$' | sed 's/\.cs$//' | sort)"
  n="$(printf '%s\n' "$migs" | grep -c .)"
  latest="$(printf '%s\n' "$migs" | tail -n 1)"
  new="$(git -C "$DVSA_MIGRATIONS" ls-files --others --exclude-standard -- '*.cs' 2>/dev/null | grep -vc -e ModelSnapshot -e Designer)"
  line="- Migrations: $(rel "$DVSA_MIGRATIONS") ($n, latest ${latest:-none}"
  [ "$new" -gt 0 ] && line="$line, $new uncommitted"
  line="$line)"
  probe="$(dvsa_config "$root" .appliedMigrationsCommand)"
  # The command comes from the repository, so it runs only once the person has trusted it.
  if [ -n "$probe" ] && ! dvsa_command_trusted "$root" "$probe"; then
    line="$line; appliedMigrationsCommand is not trusted on this machine, so it was not run"
    untrusted_probe=1
  elif [ -n "$probe" ]; then
    applied="$(cd "$root" && dvsa_timeout 8 bash -c "$probe" 2>/dev/null)"
    if [ -n "$applied" ]; then
      pending="$(printf '%s\n' "$migs" | grep -vxF -f <(printf '%s\n' "$applied" | tr -d '\r ') )"
      line="$line; unapplied locally: $(printf '%s\n' "$pending" | grep -c .)"
      [ -n "$pending" ] && line="$line ($(printf '%s' "$pending" | tr '\n' ' ' | sed 's/ $//'))"
    else
      line="$line; database not reachable, unapplied count skipped"
    fi
  fi
  echo "$line"
  if [ "${untrusted_probe:-0}" = 1 ]; then
    echo "  - If the user wants unapplied migrations reported, they trust the command in their own terminal: \`bash \"$DVSA_PLUGIN_ROOT/scripts/trust-command.sh\" \"$root\"\`. Never run that yourself, and never run the command from .claude/dotnet-vsa.json."
  fi
fi

# Docker services, when the repo has a compose file and the daemon answers quickly.
compose=""
for f in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
  [ -f "$root/$f" ] && { compose="$f"; break; }
done
if [ -n "$compose" ]; then
  if dvsa_have docker; then
    ps="$(cd "$root" && dvsa_timeout 5 docker compose ps --all --format json 2>/dev/null)"
    if [ -n "$ps" ]; then
      svc="$(printf '%s\n' "$ps" | jq -rs 'flatten | map("\(.Service)=\(.State)") | join(", ")' 2>/dev/null)"
      echo "- Docker ($compose): ${svc:-no containers}"
    else
      echo "- Docker ($compose): no containers running (or the daemon is down). Start with: docker compose up -d"
    fi
  else
    echo "- Docker ($compose): docker CLI not found"
  fi
fi

tests="$(dvsa_test_projects)"
if [ -z "$tests" ]; then
  echo "- Tests: **no test project exists**. Never report that tests passed; say so explicitly. The bootstrap-tests skill creates one."
else
  echo "- Tests: $(printf '%s\n' "$tests" | while read -r t; do rel "$t"; printf ' '; done)"
fi

backlog="$(dvsa_config "$root" .backlogFile)"; backlog="${backlog:-.ai/backlog.md}"
if [ -f "$root/$backlog" ]; then
  p1="$(grep -E '^#{2,4} .*\bP1\b' "$root/$backlog" | head -n 3 | sed -E 's/^#+ */  - /')"
  [ -n "$p1" ] && { echo "- Top P1 items in $backlog:"; echo "$p1"; }
fi

# Path-scoped rules: Claude Code loads them from the project, so they have to be installed there.
if ls "$DVSA_PLUGIN_ROOT"/rules/*.md >/dev/null 2>&1; then
  plugin_version="$(jq -r '.version // empty' "$DVSA_PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)"
  rules_source="$root/.claude/rules/dotnet-vsa/.source"
  if [ ! -f "$rules_source" ]; then
    echo "- Rules: the plugin's path-scoped rules are not installed in this repo. Offer to run the install-rules skill once; do not install them unasked."
  else
    installed_version="$(head -n 1 "$rules_source" | tr -d '[:space:]')"
    if [ -n "$plugin_version" ] && [ "$installed_version" != "$plugin_version" ]; then
      echo "- Rules: .claude/rules/dotnet-vsa/ was installed from dotnet-vsa ${installed_version:-an unknown version}; the plugin is now $plugin_version. The install-rules skill shows what changed (install-rules --check)."
    fi
  fi
fi

mcp_missing=""
dvsa_have dnx || mcp_missing="$mcp_missing nuget (needs dnx from the .NET 10 SDK);"
dvsa_have npx || mcp_missing="$mcp_missing context7 (needs npx from Node.js);"
[ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ] || mcp_missing="$mcp_missing github (GITHUB_PERSONAL_ACCESS_TOKEN is not set);"
[ -n "$mcp_missing" ] && echo "- MCP servers that cannot start:${mcp_missing%;}. Say so when a task needs one rather than guessing."

cat <<'EOF'
- Look things up rather than recalling them: .NET 10, ASP.NET Core, EF Core and Azure APIs with the microsoft-learn MCP tools; third-party libraries with context7; package versions and vulnerabilities with nuget. Ask before adding or upgrading a NuGet package.
- Guard rails: long-running commands need run_in_background; committed migrations are immutable; secrets stay out of appsettings*.json (Local excepted); unregistered handlers, missing outbox branches and unsecured endpoints are reported after each edit and block the end of the turn.
- `dotnet build` passing is not the app running. Say what you observed, and say when a runtime check is still pending.
EOF
exit 0
