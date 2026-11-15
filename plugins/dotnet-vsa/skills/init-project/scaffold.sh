#!/usr/bin/env bash
# Writes the dotnet-vsa project skeleton into a repository: a .slnx solution, the API project with
# SharedKernel, persistence, outbox, authorization and rate-limit policies, .claude/dotnet-vsa.json,
# and compose.yaml for SQL Server, with the local-only .env and appsettings.Local.json.
# Copies files only: it needs no .NET SDK and touches no network. The init-project skill adds the
# NuGet packages and builds afterwards.
#
# Usage: scaffold.sh <repo-dir> <AppName>
#   AppName is a PascalCase C# identifier, optionally dotted (Shop, Contoso.Shop). The API project
#   becomes src/<AppName>.Api.
#
# Exit 0 and prints each written path; exit 2 with a reason when the repo already has a solution
# or project, or an argument is invalid. Never overwrites a file.
set -u

usage() { echo "usage: scaffold.sh <repo-dir> <AppName>" >&2; exit 64; }
die() { echo "scaffold: $*" >&2; exit 2; }

[ $# -eq 2 ] || usage
repo="$1"; app="$2"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$here/template"

printf '%s' "$app" | grep -Eq '^[A-Z][A-Za-z0-9]*(\.[A-Z][A-Za-z0-9]*)*$' \
  || die "'$app' is not a PascalCase C# name (letters and digits, optionally dotted: Shop, Contoso.Shop)."
[ -d "$repo" ] || die "$repo is not a directory."
repo="$(cd "$repo" && pwd)"

existing="$(find "$repo" \( -name .git -o -name bin -o -name obj -o -name node_modules \) -prune -o \
  \( -name '*.sln' -o -name '*.slnx' -o -name '*.csproj' \) -print 2>/dev/null | head -n 3)"
[ -z "$existing" ] || die "this repository already has a .NET solution or project, so it is not a new project:
$existing"

# Every template file, as a path relative to the template.
sources() {
  (cd "$template" && find . \( -name bin -o -name obj \) -prune -o -type f -print | sed 's|^\./||' | sort)
}
target_of() { printf '%s' "$1" | sed -e "s/DvsaTemplate/$app/g"; }

local_files=".claude/dotnet-vsa.json .env src/$app.Api/appsettings.Local.json"

# Every target must be new.
conflicts=""
while read -r f; do
  target="$(target_of "$f")"
  [ -e "$repo/$target" ] && conflicts="$conflicts $target"
done <<EOF
$(sources)
EOF
for f in $local_files; do
  [ -e "$repo/$f" ] && conflicts="$conflicts $f"
done
[ -z "$conflicts" ] || die "these files already exist and would be overwritten:$conflicts"

# Reads a bounded amount of /dev/urandom, so tr reaches end of input and exits on its own. The
# usual `tr < /dev/urandom | head -c N` relies on SIGPIPE to stop tr; where SIGPIPE is ignored (the
# GitHub Actions macOS runners), BSD tr never stops and the script hangs.
random() {
  local out=""
  while [ "${#out}" -lt "$1" ]; do
    out="$out$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
  done
  printf '%s' "${out:0:$1}"
}
uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z'
  else cat /proc/sys/kernel/random/uuid; fi
}
secrets_id="$(uuid)"
db_name="$(printf '%s' "$app" | tr -d '.')"

# --- template files ------------------------------------------------------------------------
while read -r f; do
  target="$(target_of "$f")"
  mkdir -p "$(dirname "$repo/$target")"
  if [ "$(basename "$f")" = .gitkeep ]; then
    : > "$repo/$target"
  else
    sed -e "s/DvsaTemplate/$app/g" -e "s/__USER_SECRETS_ID__/$secrets_id/g" \
        -e "s/__DB_NAME__/$db_name/g" "$template/$f" > "$repo/$target"
  fi
  echo "$target"
done <<EOF
$(sources)
EOF

api="src/$app.Api"

# --- local-only files ----------------------------------------------------------------------
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

# Keep the local-only files out of git.
gitignore="$repo/.gitignore"
for pattern in .env appsettings.Local.json bin/ obj/; do
  grep -qxF "$pattern" "$gitignore" 2>/dev/null || printf '%s\n' "$pattern" >> "$gitignore"
done
echo ".gitignore"

# --- plugin configuration ------------------------------------------------------------------
mkdir -p "$repo/.claude"
cat > "$repo/.claude/dotnet-vsa.json" <<JSON
{
  "sln": "$app.slnx",
  "apiProject": "$api/$app.Api.csproj",
  "programCs": "$api/Program.cs",
  "outboxDispatcher": "$api/Infrastructure/Outbox/OutboxDispatcher.cs",
  "migrationsDir": "$api/Infrastructure/Persistence/Migrations",
  "healthUrl": "https://localhost:7143/health",
  "localEnvironment": "Local"
}
JSON
echo ".claude/dotnet-vsa.json"
