#!/usr/bin/env bash
# Trusts a repository's appliedMigrationsCommand (from .claude/dotnet-vsa.json) on this machine,
# so the session-start hook may run it to report unapplied migrations.
#
# The command comes from the repository, so anyone who can commit to it could put any shell
# command there. Session start never runs it until you have read it and trusted it here. Trust is
# for the exact command text in this exact repository: if the command changes, it is untrusted
# again. Run this in your own terminal; the plugin's Bash guard refuses it inside a session.
#
# Usage: trust-command.sh [repo-dir]            show the command and ask before trusting it
#        trust-command.sh --revoke [repo-dir]   forget every trusted command for the repo
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

revoke=0
[ "${1:-}" = "--revoke" ] && { revoke=1; shift; }
dvsa_have jq || { echo "trust-command: jq is required" >&2; exit 1; }
DVSA_INPUT=""
root="$(dvsa_repo_root "${1:-$PWD}")"
file="$(dvsa_trust_file)"

if [ "$revoke" = 1 ]; then
  [ -f "$file" ] || { echo "Nothing is trusted yet."; exit 0; }
  tmp="$(mktemp)"
  jq -c --arg r "$root" 'select(.root != $r)' "$file" > "$tmp" && mv "$tmp" "$file"
  echo "Removed every trusted command for $root."
  exit 0
fi

cmd="$(dvsa_config "$root" .appliedMigrationsCommand)"
if [ -z "$cmd" ]; then
  echo "$root/.claude/dotnet-vsa.json sets no appliedMigrationsCommand; nothing to trust."
  exit 0
fi
if dvsa_command_trusted "$root" "$cmd"; then
  echo "Already trusted for $root:"; printf '  %s\n' "$cmd"
  exit 0
fi

if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "trust-command: run this in your own terminal, so you can read the command before trusting it." >&2
  exit 2
fi

echo "Repository: $root"
echo "Session start will run this command with bash, as you, at the start of every session:"
echo
printf '  %s\n' "$cmd"
echo
printf 'Trust it? [y/N] '
read -r answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) echo "Not trusted."; exit 1 ;;
esac

mkdir -p "$(dirname "$file")"
jq -cn --arg r "$root" --arg c "$cmd" '{root: $r, command: $c}' >> "$file"
chmod 600 "$file" 2>/dev/null
echo "Trusted. Start a new session to see unapplied migrations."
