#!/usr/bin/env bash
# Prints the project layout that dotnet-vsa skills work against, as KEY=value lines with
# repo-relative paths. Skills run this first instead of hard-coding paths.
# Override any value in <repo>/.claude/dotnet-vsa.json (see scripts/lib/common.sh).
#
# Usage: discover.sh [repo-dir]
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
DVSA_INPUT=""
dvsa_discover "${1:-$PWD}"
root="$DVSA_ROOT"
rel() { case "$1" in "$root"/*) printf '%s' "${1#"$root"/}" ;; *) printf '%s' "$1" ;; esac; }
cfg() { local v; v="$(dvsa_config "$root" "$1")"; printf '%s' "${v:-$2}"; }

# Health URL: config, else the first https applicationUrl in launchSettings.json + /health.
health="$(cfg .healthUrl "")"
if [ -z "$health" ] && [ -n "$DVSA_API_DIR" ] && [ -f "$DVSA_API_DIR/Properties/launchSettings.json" ]; then
  base="$(grep -o '"applicationUrl"[^,]*' "$DVSA_API_DIR/Properties/launchSettings.json" | grep -o 'https://[^;"]*' | head -n 1)"
  [ -z "$base" ] && base="$(grep -o '"applicationUrl"[^,]*' "$DVSA_API_DIR/Properties/launchSettings.json" | grep -o 'http://[^;"]*' | head -n 1)"
  [ -n "$base" ] && health="${base%/}/health"
fi

# Base branch: config, else the remote's default branch, else main or master, whichever exists.
# BASE_REF is what to diff against: origin/<base> when that remote branch exists, else <base>, so
# a repo with no remote still works.
base="$(cfg .baseBranch "")"
if [ -z "$base" ]; then
  base="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
fi
if [ -z "$base" ]; then
  if git -C "$root" show-ref --verify --quiet refs/heads/main; then base=main
  elif git -C "$root" show-ref --verify --quiet refs/heads/master; then base=master
  else base=main; fi
fi
if git -C "$root" show-ref --verify --quiet "refs/remotes/origin/$base"; then base_ref="origin/$base"; else base_ref="$base"; fi

echo "ROOT=$root"
echo "BASE_BRANCH=$base"
echo "BASE_REF=$base_ref"
echo "SLN=$(rel "$DVSA_SLN")"
echo "API_PROJECT=$(rel "$DVSA_API_PROJECT")"
echo "API_DIR=$(rel "$DVSA_API_DIR")"
echo "PROGRAM_CS=$(rel "$DVSA_PROGRAM")"
echo "OUTBOX_DISPATCHER=$(rel "$DVSA_OUTBOX")"
echo "MIGRATIONS_DIR=$(rel "$DVSA_MIGRATIONS")"
# Aspire AppHost: config, else the project built with the Aspire.AppHost.Sdk. When there is one,
# the AppHost starts the database and the API together (run-api uses it instead of compose).
apphost="$(cfg .appHost "")"
if [ -z "$apphost" ]; then
  for p in $(dvsa_find "$root" -maxdepth 5 -name '*.csproj' | sort); do
    grep -q 'Aspire\.AppHost\.Sdk' "$p" 2>/dev/null && { apphost="$(rel "$p")"; break; }
  done
fi
echo "APP_HOST=$apphost"
if [ -n "$DVSA_API_DIR" ]; then
  echo "DBCONTEXT=$(rel "$(grep -rlE --include='*.cs' --exclude-dir=bin --exclude-dir=obj ':[[:space:]]*(Identity)?DbContext\b|:[[:space:]]*IdentityDbContext<' "$DVSA_API_DIR" 2>/dev/null | grep -v Factory | head -n 1)")"
  echo "AUTH_POLICIES=$(rel "$(dvsa_find "$DVSA_API_DIR" -name 'AuthorizationPolicies.cs' | head -n 1)")"
  echo "RATE_LIMIT_POLICIES=$(rel "$(dvsa_find "$DVSA_API_DIR" -name 'RateLimitPolicies.cs' | head -n 1)")"
fi
echo "TEST_PROJECTS=$(dvsa_test_projects | while read -r t; do rel "$t"; printf ' '; done | sed 's/ $//')"
echo "SPECS_DIR=$(cfg .specsDir .ai/specs)"
echo "REVIEWS_DIR=$(cfg .reviewsDir .ai/reviews)"
echo "DOCS_DIR=$(cfg .docsDir docs)"
echo "BACKLOG_FILE=$(cfg .backlogFile .ai/backlog.md)"
echo "LOCAL_ENVIRONMENT=$(cfg .localEnvironment Local)"
echo "HEALTH_URL=$health"
