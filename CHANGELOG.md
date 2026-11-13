# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

When cutting a release, rename `[Unreleased]` to the new version and date, and
bump `version` in both `.claude-plugin/marketplace.json` and
`plugins/dotnet-vsa/.claude-plugin/plugin.json` to match. Installed users stay on
the pinned version until it changes.

## [Unreleased]

Targets `0.1.0`.

### Added

- Marketplace manifest (`.claude-plugin/marketplace.json`) listing the `dotnet-vsa` plugin.
- `dotnet-vsa` plugin scaffold: manifest, `commands/`, `agents/`, `skills/`, `hooks/hooks.json`, `scripts/`, and `.mcp.json`.
- Roslyn Language Server integration (`.lsp.json`) for `.cs` files, giving Claude C# diagnostics after edits and symbol navigation. Requires `dotnet tool install --global roslyn-language-server --prerelease`.
- `PostToolUse` hook that runs `dotnet format` on every `.cs` file Claude writes or edits, using the nearest `.csproj` so `.editorconfig` style and analyzer fixes apply (whitespace-only for files outside a project). Implemented as a .NET file-based app (`scripts/format-csharp.cs`), so it needs only the .NET SDK.
- README prerequisites for the .NET 10 SDK and the Roslyn Language Server.
- Guard and verification hooks: `session-start.sh` (session context and starting commit), `guard-bash.sh` (blocks foreground long-running commands, commits on main, force-push to main, volume deletion, destructive or non-local `dotnet ef`, and broad `rm -rf`), `guard-migrations.sh` (committed migrations are immutable), `guard-config-secrets.sh` (no secrets in `appsettings*.json` except Local), `check-cs-conventions.sh` (advisory feedback after each C# edit), and `stop-verify.sh` (build and convention checks block the end of a turn, at most 3 times in a row).
- `scripts/verify-conventions.sh`: the verification checklist as one script shared by the hooks and skills. It checks the build, handler DI, outbox dispatch, endpoint authorization and rate limiting, the soft-delete filter, phantom navigation properties, UTC `DateTime` kinds, `<None Include>` on `.cs` files, and optionally formatting and tests.
- `scripts/discover.sh` and `scripts/lib/common.sh`: find the solution, API project, `Program.cs`, outbox dispatcher and migrations folder, with overrides in `.claude/dotnet-vsa.json`.
- 23 skills: `plan`, `implement-feature`, `review-pr`, `verify`, `add-entity`, `add-endpoint`, `add-domain-event`, `register-handler`, `add-background-job`, `ef-core`, `ef-add-migration`, `check-ef-performance`, `fix-utc-kinds`, `audit-authorization`, `security-audit`, `package-health`, `api-contract-diff`, `bootstrap-tests`, `write-handler-tests`, `run-api`, `smoke-health`, `backlog-sync`, `install-rules`.
- `jq` and `perl` added to the README prerequisites.

[Unreleased]: https://github.com/marlonajgayle/dotnet-claude-plugin/commits/main
