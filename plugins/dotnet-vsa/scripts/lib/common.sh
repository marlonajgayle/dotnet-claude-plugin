#!/usr/bin/env bash
# Shared helpers for dotnet-vsa hooks and scripts.
#
# Discovery, not hard-coding: the solution, the API project, Program.cs, the outbox
# dispatcher and the migrations folder are located from the repo layout, and any of
# them can be overridden in <repo>/.claude/dotnet-vsa.json (paths relative to the repo root):
#
#   {
#     "sln": "src/MyApp.sln",
#     "apiProject": "src/MyApp.Api/MyApp.Api.csproj",
#     "programCs": "src/MyApp.Api/Program.cs",
#     "outboxDispatcher": "src/MyApp.Api/Infrastructure/Outbox/OutboxProcessor.cs",
#     "migrationsDir": "src/MyApp.Api/Infrastructure/Persistence/Migrations",
#     "specsDir": ".ai/specs",
#     "reviewsDir": ".ai/reviews",
#     "backlogFile": ".ai/backlog.md",
#     "baseBranch": "main",                     (else origin's default branch, then main or master)
#     "appHost": "src/MyApp.AppHost/MyApp.AppHost.csproj",
#     "designDoc": "DESIGN.md",
#     "docsDir": "docs",
#     "healthUrl": "https://localhost:7143/health",
#     "appliedMigrationsCommand": "",
#     "fast": false,
#     "stopTests": "off",                       (off | changed | all)
#     "stopTestsFilter": "Category!=Integration", ("none" for no extra filter)
#     "checks": { "handlerDi": true, "outbox": true, "softDelete": true, "endpointAuth": true,
#                 "rateLimit": true, "phantomNav": true, "utcKinds": true, "csproj": true },
#     "approver": { "autoMerge": false, "maxAutoMergeRisk": "low", "mergeMethod": "squash" }
#   }
#
# Written for macOS /bin/bash 3.2: no associative arrays, no mapfile, no ${x,,}.

DVSA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DVSA_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$DVSA_LIB_DIR/../.." && pwd)}"

dvsa_have() { command -v "$1" >/dev/null 2>&1; }

# Reads the hook payload once. Hooks call this first; the payload is kept in DVSA_INPUT.
dvsa_read_input() {
  DVSA_INPUT="$(cat)"
}

# jq over the hook payload; prints nothing when jq or the field is missing.
dvsa_in() {
  dvsa_have jq || return 0
  printf '%s' "$DVSA_INPUT" | jq -r "$1 // empty" 2>/dev/null
}

# Repo root for a directory (defaults to the payload cwd, then $PWD).
dvsa_repo_root() {
  local dir="${1:-}"
  [ -z "$dir" ] && dir="$(dvsa_in '.cwd')"
  [ -z "$dir" ] && dir="$PWD"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$dir"
}

# Reads a key from <root>/.claude/dotnet-vsa.json. Prints nothing when the key is absent or
# null; a key set to false prints "false" (jq's `//` would drop it, which is why it is not used).
dvsa_config() {
  local root="$1" key="$2" file="$1/.claude/dotnet-vsa.json"
  [ -f "$file" ] && dvsa_have jq || return 0
  jq -r "$key | if . == null then empty else . end" "$file" 2>/dev/null
}

# Is a check enabled? Defaults to on.
dvsa_check_enabled() {
  local v
  v="$(dvsa_config "$DVSA_ROOT" ".checks.$1")"
  [ "$v" != "false" ]
}

dvsa_abs() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$DVSA_ROOT" "$1" ;;
  esac
}

# find(1) over the repo that skips build output, dependencies and VCS metadata.
dvsa_find() {
  local start="$1"; shift
  find "$start" \( -name .git -o -name bin -o -name obj -o -name node_modules -o -name .vs -o -name .idea \) -prune -o "$@" -print 2>/dev/null
}

# Is this .csproj a test project by its location? True when a dotted segment of the project's
# name ends in Test or Tests (Shop.Api.Tests, Shop.IntegrationTests, ShopTests), or a folder
# between the repo root and the project is named test/tests. Folders above DVSA_ROOT are
# ignored, and so is "test" inside a word (Contest.Api, Latest.Web).
dvsa_is_test_path() {
  local p="$1" rel name
  name="$(basename "$p" .csproj)"
  printf '%s\n' "$name" | grep -Eq '(^|[._-])([A-Za-z0-9]*Tests?|[Tt]ests?)([._-]|$)' && return 0
  rel="${p#"$DVSA_ROOT"/}"
  case "/$rel" in */[Tt]est/*|*/[Tt]ests/*|*/TEST/*|*/TESTS/*) return 0 ;; esac
  return 1
}

# Populates DVSA_ROOT, DVSA_SLN, DVSA_API_PROJECT, DVSA_API_DIR, DVSA_PROGRAM,
# DVSA_OUTBOX, DVSA_MIGRATIONS. Any may be empty when the repo is not a .NET API.
dvsa_discover() {
  DVSA_ROOT="$(dvsa_repo_root "${1:-}")"
  local v

  v="$(dvsa_config "$DVSA_ROOT" .sln)"
  if [ -n "$v" ]; then
    DVSA_SLN="$(dvsa_abs "$v")"
  else
    DVSA_SLN="$(dvsa_find "$DVSA_ROOT" -maxdepth 3 \( -name '*.sln' -o -name '*.slnx' \) | sort | head -n 1)"
  fi

  v="$(dvsa_config "$DVSA_ROOT" .apiProject)"
  if [ -n "$v" ]; then
    DVSA_API_PROJECT="$(dvsa_abs "$v")"
  else
    # The first web SDK project that is not a test project. Only the project's own name and the
    # folders inside the repo decide that: a repo cloned under ~/latest/ or ~/contest/ is not a test.
    DVSA_API_PROJECT=""
    local p
    for p in $(dvsa_find "$DVSA_ROOT" -maxdepth 5 -name '*.csproj' | sort); do
      dvsa_is_test_path "$p" && continue
      if grep -q 'Sdk="Microsoft.NET.Sdk.Web"' "$p" 2>/dev/null; then
        DVSA_API_PROJECT="$p"; break
      fi
    done
  fi
  DVSA_API_DIR=""
  [ -n "$DVSA_API_PROJECT" ] && DVSA_API_DIR="$(dirname "$DVSA_API_PROJECT")"

  v="$(dvsa_config "$DVSA_ROOT" .programCs)"
  if [ -n "$v" ]; then DVSA_PROGRAM="$(dvsa_abs "$v")"
  elif [ -n "$DVSA_API_DIR" ] && [ -f "$DVSA_API_DIR/Program.cs" ]; then DVSA_PROGRAM="$DVSA_API_DIR/Program.cs"
  else DVSA_PROGRAM=""; fi

  v="$(dvsa_config "$DVSA_ROOT" .outboxDispatcher)"
  if [ -n "$v" ]; then
    DVSA_OUTBOX="$(dvsa_abs "$v")"
  elif [ -n "$DVSA_API_DIR" ]; then
    # The file that string-matches message types with nameof(...).
    DVSA_OUTBOX="$(grep -rlE --include='*.cs' --exclude-dir=bin --exclude-dir=obj \
      'Type[[:space:]]*==[[:space:]]*nameof\(|case[[:space:]]+nameof\(' "$DVSA_API_DIR" 2>/dev/null \
      | grep -i 'outbox' | head -n 1)"
  else
    DVSA_OUTBOX=""
  fi

  v="$(dvsa_config "$DVSA_ROOT" .migrationsDir)"
  if [ -n "$v" ]; then DVSA_MIGRATIONS="$(dvsa_abs "$v")"
  elif [ -n "$DVSA_API_DIR" ]; then DVSA_MIGRATIONS="$(dvsa_find "$DVSA_API_DIR" -type d -name Migrations | head -n 1)"
  else DVSA_MIGRATIONS=""; fi
}

# Test projects: a .csproj that references xunit, NUnit or MSTest.
dvsa_test_projects() {
  local p
  for p in $(dvsa_find "$DVSA_ROOT" -maxdepth 5 -name '*.csproj'); do
    grep -qiE 'xunit|nunit|mstest|Microsoft\.NET\.Test\.Sdk' "$p" 2>/dev/null && printf '%s\n' "$p"
  done
}

# Repository commands the person has trusted on this machine (appliedMigrationsCommand). The
# file lives outside every repository, so cloning a repo can never trust its own command. One
# JSON object per line: {"root": "<repo root>", "command": "<exact command>"}.
dvsa_trust_file() {
  printf '%s\n' "${DVSA_TRUST_FILE:-$HOME/.claude/dotnet-vsa/trusted-commands}"
}

# dvsa_command_trusted ROOT COMMAND: true when exactly this command is trusted for this repo.
dvsa_command_trusted() {
  local f; f="$(dvsa_trust_file)"
  [ -f "$f" ] && dvsa_have jq || return 1
  jq -se --arg r "$1" --arg c "$2" 'any(.[]; .root == $r and .command == $c)' "$f" >/dev/null 2>&1
}

# Per-session state, used to remember the starting commit and the last verified tree.
dvsa_state_dir() {
  local sid="${1:-unknown}" base="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/dotnet-vsa}"
  local d="${base%/}/sessions/$sid"
  mkdir -p "$d" 2>/dev/null
  printf '%s\n' "$d"
}

# Runs a command with a wall-clock limit (macOS has no timeout(1)). Returns 124 on timeout.
dvsa_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watcher=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  [ $rc -eq 143 ] && return 124
  return $rc
}

# JSON-escapes stdin into a string literal.
dvsa_json_string() {
  if dvsa_have jq; then jq -Rs .; else
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}' | sed 's/^/"/; s/$/"/'
  fi
}

# Emits non-blocking context for the agent from a PostToolUse / SessionStart hook.
dvsa_emit_context() {
  local event="$1" text="$2"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":%s}}\n' \
    "$event" "$(printf '%s' "$text" | dvsa_json_string)"
}

# Blocks a PreToolUse call or a Stop: reason on stderr, exit 2.
dvsa_block() {
  printf '%s\n' "$*" >&2
  exit 2
}
