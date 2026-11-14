# Working on dotnet-claude-plugin

This repo is a Claude Code marketplace with one plugin, `plugins/dotnet-vsa`. The README describes what the plugin does for its users; this file is for changing the plugin itself.

## Layout

- `plugins/dotnet-vsa/hooks/`: the hook scripts and `hooks.json`. Each hook sources `scripts/lib/common.sh` first.
- `plugins/dotnet-vsa/scripts/lib/common.sh`: discovery (solution, API project, Program.cs, outbox dispatcher, migrations) and `.claude/dotnet-vsa.json` reading. Every hook, script and skill gets paths from here or from `scripts/discover.sh`; never hard-code a project layout.
- `plugins/dotnet-vsa/scripts/lib/conventions.sh`: the convention checks. One implementation with three callers: the post-edit hook, the Stop hook and `verify-conventions.sh`.
- `plugins/dotnet-vsa/scripts/lib/guard_bash.pl`: the Bash command analysis behind `guard-bash.sh`.
- `plugins/dotnet-vsa/skills/`, `agents/`, `rules/`: Markdown instructions. `init-project`, `write-handler-tests` and `write-integration-tests` also ship C# templates.
- `plugins/dotnet-vsa/evals/`: the `claude plugin eval` suite, which checks that natural phrasing loads the right skill.
- `tests/`: the shell test suite, its fixture API (`tests/fixtures/api`) and the end-to-end script (`tests/e2e/run.sh`).

## Rules

- **Bash 3.2.** The hooks run on macOS's `/bin/bash`. No associative arrays, `mapfile`, `${x,,}`, `|&` or `declare -n`. Use `perl` (core modules only) for anything multi-line, and `jq` for JSON. BSD and GNU tools differ: no `sed -i` without a suffix argument in shipped scripts, no `grep -P`, no `timeout` (use `dvsa_timeout`).
- **Hooks fail open.** Without `jq`, outside git, or in a repo with no .NET API, a hook exits 0 silently. Only a confirmed problem blocks, and the block message says what to do instead.
- **Never echo a secret.** A message from `guard-config-secrets.sh` names the key or the kind of secret, never the value.
- **Every hook or check change gets a test case** in the matching `tests/test-*.sh` file: a command that is now blocked and a near miss that is still allowed, or a fixture change that makes a check pass and fail.
- **Every new skill, agent or rule gets a README row.** `tests/test-static.sh` fails otherwise. A new skill that people reach for by phrasing also gets an eval case.
- **Templates are verified for real.** After changing anything under a skill's `template*/` or `templates/` folder, run `bash tests/e2e/run.sh` (needs the .NET 10 SDK, network and Docker; `--no-docker` and `--no-aspire` skip parts).
- **Keep the CHANGELOG.** Add a line under `[Unreleased]` for each user-visible change.

## Commands

```sh
bash tests/run.sh                         # the whole suite: bash, git, jq and perl only
bash tests/run.sh test-guard-bash.sh      # one file
bash tests/e2e/run.sh                     # templates end to end
shellcheck -x -S error -e SC1090,SC1091 $(git ls-files '*.sh')
claude plugin validate plugins/dotnet-vsa
cd plugins/dotnet-vsa && claude plugin eval . --scaffold --ablation none --runs 1   # quick eval pass, costs model calls
```

Run `bash tests/run.sh` before reporting any change as done.
