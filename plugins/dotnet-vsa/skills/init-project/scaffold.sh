#!/usr/bin/env bash
# Writes the dotnet-vsa project skeleton into a repository: a .slnx solution, the API project with
# SharedKernel, persistence, outbox, authorization and rate-limit policies, .claude/dotnet-vsa.json,
# and the local database setup, which is one of:
#   - default:  compose.yaml for SQL Server, with the local-only .env and appsettings.Local.json
#   - --aspire: an Aspire AppHost that runs SQL Server and the API, and a ServiceDefaults project
#               (OpenTelemetry to the Aspire dashboard, liveness, resilient HttpClients)
# Copies files only: it needs no .NET SDK and touches no network. The init-project skill adds the
# NuGet packages and builds afterwards.
#
# Usage: scaffold.sh <repo-dir> <AppName> [--aspire <AspireVersion>]
#   AppName is a PascalCase C# identifier, optionally dotted (Shop, Contoso.Shop). The API project
#   becomes src/<AppName>.Api. AspireVersion is the Aspire.AppHost.Sdk version (13.6.5), chosen by
#   the skill with the nuget tools, since this script works offline.
#
# Exit 0 and prints each written path; exit 2 with a reason when the repo already has a solution
# or project, or an argument is invalid. Never overwrites a file.
set -u

usage() { echo "usage: scaffold.sh <repo-dir> <AppName> [--aspire <AspireVersion>]" >&2; exit 64; }
die() { echo "scaffold: $*" >&2; exit 2; }

[ $# -eq 2 ] || [ $# -eq 4 ] || usage
repo="$1"; app="$2"; aspire=""
if [ $# -eq 4 ]; then
  [ "$3" = "--aspire" ] || usage
  aspire="$4"
  printf '%s' "$aspire" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$' \
    || die "'$aspire' is not an Aspire version (for example 13.6.5)."
fi
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$here/template"
template_aspire="$here/template-aspire"

printf '%s' "$app" | grep -Eq '^[A-Z][A-Za-z0-9]*(\.[A-Z][A-Za-z0-9]*)*$' \
  || die "'$app' is not a PascalCase C# name (letters and digits, optionally dotted: Shop, Contoso.Shop)."
[ -d "$repo" ] || die "$repo is not a directory."
repo="$(cd "$repo" && pwd)"

existing="$(find "$repo" \( -name .git -o -name bin -o -name obj -o -name node_modules \) -prune -o \
  \( -name '*.sln' -o -name '*.slnx' -o -name '*.csproj' \) -print 2>/dev/null | head -n 3)"
[ -z "$existing" ] || die "this repository already has a .NET solution or project, so it is not a new project:
$existing"

# Every template file as "<template-dir><TAB><path>". With --aspire, the Aspire template adds the
# AppHost and ServiceDefaults and replaces the solution file; compose.yaml is not needed.
sources() {
  (cd "$template" && find . \( -name bin -o -name obj \) -prune -o -type f -print | sed 's|^\./||' | sort) | while read -r f; do
    if [ -n "$aspire" ]; then
      case "$f" in compose.yaml) continue ;; esac
      [ -f "$template_aspire/$f" ] && continue
    fi
    printf '%s\t%s\n' "$template" "$f"
  done
  if [ -n "$aspire" ]; then
    (cd "$template_aspire" && find . \( -name bin -o -name obj \) -prune -o -type f -print | sed 's|^\./||' | sort) | while read -r f; do
      printf '%s\t%s\n' "$template_aspire" "$f"
    done
  fi
}
target_of() { printf '%s' "$1" | sed -e "s/DvsaTemplate/$app/g"; }

if [ -n "$aspire" ]; then local_files=".claude/dotnet-vsa.json"
else local_files=".claude/dotnet-vsa.json .env src/$app.Api/appsettings.Local.json"; fi

# Every target must be new.
conflicts=""
TAB="$(printf '\t')"
while IFS="$TAB" read -r _ f; do
  target="$(target_of "$f")"
  [ -e "$repo/$target" ] && conflicts="$conflicts $target"
done <<EOF
$(sources)
EOF
for f in $local_files; do
  [ -e "$repo/$f" ] && conflicts="$conflicts $f"
done
[ -z "$conflicts" ] || die "these files already exist and would be overwritten:$conflicts"

random() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"; }
uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z'
  else cat /proc/sys/kernel/random/uuid; fi
}
secrets_id="$(uuid)"
apphost_secrets_id="$(uuid)"
db_name="$(printf '%s' "$app" | tr -d '.')"
ident="$(printf '%s' "$app" | tr '.' '_')"   # Aspire's generated Projects.<Name> class

# --- template files ------------------------------------------------------------------------
while IFS="$TAB" read -r dir f; do
  target="$(target_of "$f")"
  mkdir -p "$(dirname "$repo/$target")"
  if [ "$(basename "$f")" = .gitkeep ]; then
    : > "$repo/$target"
  else
    sed -e "s/DvsaTemplateIdent/$ident/g" -e "s/DvsaTemplate/$app/g" \
        -e "s/__USER_SECRETS_ID__/$secrets_id/g" -e "s/__APPHOST_USER_SECRETS_ID__/$apphost_secrets_id/g" \
        -e "s/__ASPIRE_VERSION__/$aspire/g" -e "s/__DB_NAME__/$db_name/g" \
        "$dir/$f" > "$repo/$target"
  fi
  echo "$target"
done <<EOF
$(sources)
EOF

api="src/$app.Api"

if [ -n "$aspire" ]; then
  # --- wire the API into Aspire ------------------------------------------------------------
  # ServiceDefaults: OpenTelemetry to the dashboard and /alive. The API keeps its own /health.
  perl -0pi -e "s|for running against the docker compose\n// database\.|for running under the Aspire AppHost,\n// which supplies the database connection string.|" "$repo/$api/Program.cs"
  perl -0pi -e 's/(var builder = WebApplication\.CreateBuilder\(args\);\n)/$1\n\/\/ Aspire service defaults: OpenTelemetry to the dashboard, a liveness check, resilient HttpClients.\nbuilder.AddServiceDefaults();\n/; s/(app\.MapHealthChecks\("\/health"\);\n)/$1app.MapDefaultEndpoints();\n/' "$repo/$api/Program.cs"
  perl -0pi -e "s|</Project>|  <ItemGroup>\n    <ProjectReference Include=\"..\\\\$app.ServiceDefaults\\\\$app.ServiceDefaults.csproj\" />\n  </ItemGroup>\n\n</Project>|" "$repo/$api/$app.Api.csproj"
else
  # --- local-only files --------------------------------------------------------------------
  # SQL Server needs upper, lower, digit and symbol.
  sa_password="$(random 20)Aa1!"
  printf 'MSSQL_SA_PASSWORD=%s\n' "$sa_password" > "$repo/.env"
  echo ".env"
  cat > "$repo/$api/appsettings.Local.json" <<JSON
{
  "ConnectionStrings": {
    "Default": "Server=localhost,1433;Database=$db_name;User Id=sa;Password=$sa_password;TrustServerCertificate=True;Encrypt=False"
  }
}
JSON
  echo "$api/appsettings.Local.json"
fi

# Keep the local-only files out of git.
gitignore="$repo/.gitignore"
for pattern in .env appsettings.Local.json bin/ obj/; do
  grep -qxF "$pattern" "$gitignore" 2>/dev/null || printf '%s\n' "$pattern" >> "$gitignore"
done
echo ".gitignore"

# --- plugin configuration ------------------------------------------------------------------
mkdir -p "$repo/.claude"
apphost_line=""
[ -n "$aspire" ] && apphost_line="
  \"appHost\": \"src/$app.AppHost/$app.AppHost.csproj\","
cat > "$repo/.claude/dotnet-vsa.json" <<JSON
{
  "sln": "$app.slnx",
  "apiProject": "$api/$app.Api.csproj",$apphost_line
  "programCs": "$api/Program.cs",
  "outboxDispatcher": "$api/Infrastructure/Outbox/OutboxDispatcher.cs",
  "migrationsDir": "$api/Infrastructure/Persistence/Migrations",
  "healthUrl": "https://localhost:7143/health",
  "localEnvironment": "Local"
}
JSON
echo ".claude/dotnet-vsa.json"
