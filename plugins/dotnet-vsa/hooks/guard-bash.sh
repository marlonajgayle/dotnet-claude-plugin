#!/usr/bin/env bash
# PreToolUse(Bash): blocks commands that hang the shell or destroy shared state.
#   - dotnet run/watch, npm start, expo start, --watch, docker compose up (no -d), tail -f
#     unless run_in_background is set
#   - git commit on main/master (in .NET repos), force-push to main/master
#   - docker compose down -v, docker volume rm/prune
#   - dotnet ef database drop / migrations remove unless ASPNETCORE_ENVIRONMENT=<local env>
#   - dotnet ef database update --connection <non-local>
#   - ASPNETCORE_ENVIRONMENT/DOTNET_ENVIRONMENT=<other env> dotnet ef database update
#   - rm -rf outside bin/, obj/, node_modules/ and the temp directory
#   - work that cannot be recovered: git reset --hard, git clean -f, git checkout/restore .,
#     git branch -D, git stash clear/drop (in any repo, .NET or not)
#   - trusting a repo's appliedMigrationsCommand (scripts/trust-command.sh): the user does that
# Exit 2 with the reason on stderr blocks the call; the reason is shown to Claude.
. "$(dirname "$0")/../scripts/lib/common.sh"

dvsa_read_input
dvsa_have jq || exit 0
cmd="$(dvsa_in '.tool_input.command')"
[ -n "$cmd" ] || exit 0

cwd="$(dvsa_in '.cwd')"; [ -n "$cwd" ] || cwd="$PWD"

# Discovery is only needed to decide whether this repo's main branch is protected.
protect=0; local_env="Local"
case "$cmd" in
  *commit*|*" ef "*)
    dvsa_discover "$cwd"
    if [ -n "$DVSA_SLN$DVSA_API_PROJECT" ] && [ "$(dvsa_config "$DVSA_ROOT" .protectMain)" != "false" ]; then protect=1; fi
    v="$(dvsa_config "$DVSA_ROOT" .localEnvironment)"; [ -n "$v" ] && local_env="$v"
    ;;
esac

reason="$(DVSA_CMD="$cmd" DVSA_BG="$(dvsa_in '.tool_input.run_in_background')" DVSA_CWD="$cwd" \
  DVSA_PROTECT_MAIN="$protect" DVSA_LOCAL_ENV="$local_env" \
  perl "$DVSA_PLUGIN_ROOT/scripts/lib/guard_bash.pl")"
[ $? -eq 1 ] && [ -n "$reason" ] && dvsa_block "$reason"
exit 0
