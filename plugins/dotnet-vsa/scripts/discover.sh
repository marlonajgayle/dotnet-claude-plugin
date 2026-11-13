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

echo "ROOT=$root"
echo "SLN=$(rel "$DVSA_SLN")"
echo "API_PROJECT=$(rel "$DVSA_API_PROJECT")"
echo "API_DIR=$(rel "$DVSA_API_DIR")"
echo "PROGRAM_CS=$(rel "$DVSA_PROGRAM")"
echo "OUTBOX_DISPATCHER=$(rel "$DVSA_OUTBOX")"
echo "MIGRATIONS_DIR=$(rel "$DVSA_MIGRATIONS")"
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
