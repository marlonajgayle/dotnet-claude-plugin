# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

When cutting a release, rename `[Unreleased]` to the new version and date, and
bump `version` in both `.claude-plugin/marketplace.json` and
`plugins/dotnet-vsa/.claude-plugin/plugin.json` to match. Installed users stay on
the pinned version until it changes.

## [Unreleased]

## [0.1.0] - 2026-11-14

First release.

### Added

- Marketplace manifest (`.claude-plugin/marketplace.json`) listing the `dotnet-vsa` plugin.
- `dotnet-vsa` plugin scaffold: manifest, `agents/`, `skills/`, `hooks/hooks.json`, `scripts/`, and `.mcp.json`.
- Roslyn Language Server integration (`.lsp.json`) for `.cs` files, giving Claude C# diagnostics after edits and symbol navigation. Requires `dotnet tool install --global roslyn-language-server --prerelease`.
- `PostToolUse` hook that runs `dotnet format` on every `.cs` file Claude writes or edits, using the nearest `.csproj` so `.editorconfig` style and analyzer fixes apply (whitespace-only for files outside a project). Implemented as a .NET file-based app (`scripts/format-csharp.cs`), so it needs only the .NET SDK.
- README prerequisites for the .NET 10 SDK and the Roslyn Language Server.
- Guard and verification hooks: `session-start.sh` (session context and starting commit), `guard-bash.sh` (blocks foreground long-running commands, commits on main, force-push to main, volume deletion, destructive or non-local `dotnet ef`, and broad `rm -rf`), `guard-migrations.sh` (committed migrations are immutable), `guard-config-secrets.sh` (no secrets in `appsettings*.json` except Local), `check-cs-conventions.sh` (advisory feedback after each C# edit), and `stop-verify.sh` (build and convention checks block the end of a turn, at most 3 times in a row).
- `scripts/verify-conventions.sh`: the verification checklist as one script shared by the hooks and skills. It checks the build, handler DI, outbox dispatch, endpoint authorization and rate limiting, the soft-delete filter, phantom navigation properties, UTC `DateTime` kinds, `<None Include>` on `.cs` files, and optionally formatting and tests.
- `scripts/discover.sh` and `scripts/lib/common.sh`: find the solution, API project, `Program.cs`, outbox dispatcher and migrations folder, with overrides in `.claude/dotnet-vsa.json`.
- 21 skills: `write-feature-docs`, `verify`, `add-entity`, `add-endpoint`, `add-domain-event`, `register-handler`, `add-background-job`, `ef-core`, `ef-add-migration`, `check-ef-performance`, `fix-utc-kinds`, `audit-authorization`, `security-audit`, `package-health`, `api-contract-diff`, `bootstrap-tests`, `write-handler-tests`, `run-api`, `smoke-health`, `backlog-sync`, `install-rules`.
- Six subagents in `agents/`: `spec-writer` (feature and bugfix specs), `implementer`, `code-reviewer`, `security-reviewer`, `ux-reviewer` (against the project's `DESIGN.md` and WCAG 2.2 AA) and `approver` (risk-scored MERGE or HUMAN REVIEW decision). They hand off through `.ai/specs/<slug>.md` and `.ai/reviews/<slug>/{code,security,ux,decision}.md`.
- `documenter` subagent (Sonnet) that documents a change once the approver decides MERGE, and the `write-feature-docs` skill it uses: a guide in `docs/features/<slug>.md` structured like a DigitalOcean community tutorial, with a template (`template.md`) and style guide (`style.md`). The approver now accepts docs-only commits made after the review.
- `designDoc`, `docsDir` and `approver` (`autoMerge`, `maxAutoMergeRisk`, `mergeMethod`) keys in `.claude/dotnet-vsa.json`.
- `jq` and `perl` added to the README prerequisites.
- Bundled MCP servers in `.mcp.json`: `microsoft-learn` (current .NET and Azure docs), `nuget` (`dnx NuGet.Mcp.Server`: package information and vulnerability fixes), `context7` (third-party library docs) and `github` (issues, pull requests and Actions runs; needs `GITHUB_PERSONAL_ACCESS_TOKEN`).
- Agents get only the MCP servers they need in their `tools` lists. The `implementer` asks before adding or upgrading a package and picks the version with `nuget`. The `spec-writer` reads GitHub issues. The `code-reviewer` reads failing Actions runs on the PR. `package-health`, `security-audit` and the `security-reviewer` use `nuget` read-only to name the fixed version.
- `session-start.sh` lists bundled MCP servers that cannot start (no `dnx`, no `npx`, no GitHub token).
- README section on MCP servers, with project-level `.mcp.json` snippets for Playwright, Sentry, Azure MCP (Application Insights and Azure Monitor) and Azure DevOps.
- Node.js and a GitHub token added to the README prerequisites.
- Test suite for the hooks and convention checks (`tests/run.sh`, needs only `bash`, `git`, `jq` and `perl`) with a fixture API, and a GitHub Actions workflow that runs it on Linux and macOS with ShellCheck and `claude plugin validate`.
- Seven path-scoped rule files in `rules/` (handlers, endpoints, entities, domain events, migrations, DTOs, appsettings), each restating the conventions the hooks check so Claude sees them before it writes. The `install-rules` skill copies them into a project's `.claude/rules/dotnet-vsa/`, and `session-start.sh` says when they are missing or older than the plugin.
- `ship` skill: runs the whole pipeline for one change (spec-writer, implementer, the three reviewers in parallel, up to `--rounds` fix rounds, approver, documenter), committing on the branch and stopping after the spec, on open questions, on unresolved findings and at the approver's decision.
- `init-project` skill: scaffolds a new API with the SharedKernel (`Result`, `Error`, auditable and aggregate-root entities with soft delete, domain events), an EF Core SQL Server DbContext that writes events to an outbox, the outbox processor and a dispatcher that records unhandled events as errors, authorization and rate-limit policy classes, endpoint discovery, a FluentValidation filter, `compose.yaml` and `.claude/dotnet-vsa.json`. Microsoft packages are pinned to the target framework's major version.
- `write-integration-tests` skill: endpoint tests through `WebApplicationFactory` against SQL Server in Testcontainers, with a fixture that lets each test choose its caller and dispatch the outbox on demand.
- `stopTests` and `stopTestsFilter` in `.claude/dotnet-vsa.json`: the Stop hook can run the tests for the changed slices, or all tests, and blocks the turn when one fails. Integration tests are left out by default. The Stop hook's time limit is now 10 minutes.
- `scripts/nuget-version.sh`: the newest stable version of a package within a major version.
- `tests/e2e/run.sh` and a CI job that scaffold, build and run the templates' integration tests end to end.
- `init-project --aspire`: an Aspire AppHost that runs SQL Server and the API, and a ServiceDefaults project (OpenTelemetry to the Aspire dashboard, a `/alive` liveness probe, resilient `HttpClient`s), instead of `compose.yaml`. `run-api` starts the AppHost when there is one, and discovery reports it as `APP_HOST` (or `appHost` in `.claude/dotnet-vsa.json`).
- `write-handler-tests` templates: `SqliteDbContextFactory.cs` (a real `ApplicationDbContext` over SQLite in memory) and `TestDoubles.cs` (`TestClock`, `TestCurrentUser`). The end-to-end script runs handler tests built from them, and builds the `--aspire` variant.
- An eval suite for `claude plugin eval` in `plugins/dotnet-vsa/evals/`: 18 cases that check natural phrasing loads the right skill, that easily confused skills are told apart, and that no skill loads for unrelated questions. A manually started *Plugin evals* workflow runs it in GitHub Actions.
- `baseBranch` in `.claude/dotnet-vsa.json` and `BASE_BRANCH`/`BASE_REF` from discovery: the agents and skills compare against `origin/<base>` when it exists and the local base branch otherwise, so repositories without a remote, or with `master`, work.
- `scripts/trust-command.sh`: trusts a repository's `appliedMigrationsCommand` on this machine.
- `CLAUDE.md` with the rules for working on the plugin itself.

### Fixed

- `verify-conventions.sh` reported tests as passed when a filter matched no tests (`dotnet test` exits 0); it now reports that no tests ran.
- `protectMain: false` and `checks.<name>: false` in `.claude/dotnet-vsa.json` were ignored, so commits on `main` stayed blocked and checks could not be switched off.
- `guard-bash.sh` no longer blocks a command because `--watch` appears inside a quoted argument (for example a commit message), and allows `docker compose up --wait`, which returns once the services are healthy.
- Discovery skipped every project when the repository's path contained "test" (a clone under `~/latest/` or `~/contest/`), so every hook and skill silently did nothing. Only the project's own name and the folders inside the repository now mark a test project.
- The handler registration check counted `AddScoped<...>` written in comments, so the example in the scaffolded `Program.cs` hid an unregistered handler of the same name. Comments are now ignored, and `AddScoped<IService, Impl>` counts for `Impl`.
- The handler registration check was off until a project had its first registration, so the first unregistered handler went unreported. It is now on unless handlers are registered by scanning (Scrutor, MediatR, Wolverine, or an `Add…HandlersFrom…` helper).
- The format hook started `dotnet run` for every edited file, Markdown and JSON included, costing a second or two each time. A small bash wrapper now starts it only for `.cs` files.
- `appliedMigrationsCommand` from a repository's `.claude/dotnet-vsa.json` ran at session start as soon as the repository was opened. It now runs only after the person trusts that exact command with `trust-command.sh`, and the Bash guard refuses to run the trust script inside a session.
- The Stop hook's count of blocks in a row carried over from an interrupted turn into the next one. It now follows `stop_hook_active`, so every new turn gets all three attempts.
- The template folders could carry `bin/` and `obj/` from a local build into scaffolded projects; the scaffold now skips them.

### Changed

- Review output shares one layout under `reviewsDir` (default `.ai/reviews`): one folder per branch for the agents' reports, and `_audits/<timestamp>.md` for the `security-audit` skill (was `.claude/security-audits/`), which now honours `reviewsDir`. Reports at the old path are left in place.
- The `spec-writer`, `implementer` and `code-reviewer` agents now carry their whole method: the spec template (including the Bug, UX and Risk notes sections), the implementation and verification steps, and the review checklist. The `implementer` creates the branch the spec names, so bug fixes land on `bugfix/`. The agents read the project's rules, or the plugin's copies when they are not installed, instead of restating the conventions.
- `guard-bash.sh` also blocks commands that destroy work for good, in any repository: `git reset --hard`, `git clean -f`, `git checkout .` and `git restore .`, `git branch -D`, `git stash clear` and `drop`. It blocks `dotnet ef database update` when `ASPNETCORE_ENVIRONMENT`, `DOTNET_ENVIRONMENT` or `--environment` names an environment other than the local one or Development.
- `guard-config-secrets.sh` covers `launchSettings.json`, `.env` files, `*.csproj`/`*.props`/`*.targets` and C# string literals as well as `appsettings*.json`, and skips files git ignores, test projects and migrations.
- The `ship` skill runs the UX reviewer only when a user-facing file changed, and otherwise writes a NOT APPLICABLE `ux.md` itself. The approver's list of user-facing files now includes validators and `*Errors.cs`, whose messages reach users.
- `check-ef-performance` writes to `<reviewsDir>/_audits/` (was `.claude/ef-performance/`), and `api-contract-diff` writes `<reviewsDir>/<slug>/api-contract.md` (was `.claude/api-contract/`), with its scratch files in a temporary directory.
- `bootstrap-tests` generates a registration test that reads `AddScoped` calls from syntax trees, so comments do not count, and that skips itself when handlers are registered by scanning.
- The manifests describe the plugin as skills, subagents, hooks and MCP servers; it never shipped separate slash commands.

### Removed

- Blazor and Azure from the plugin's description, the marketplace description, the README introduction and the manifest keywords. The plugin has no Blazor or Azure skills, so it no longer advertises them. Reviews of `.razor` files, Azure documentation lookups and the optional Azure MCP snippets are unchanged.
- The `plan`, `implement-feature` and `review-pr` skills, which duplicated the `spec-writer`, `implementer` and `code-reviewer` agents and had drifted from them. Ask for the agents instead ("use the spec-writer agent to …").
- The empty `commands/` folder. Every skill is already available as a slash command.

[Unreleased]: https://github.com/marlonajgayle/dotnet-claude-plugin/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/marlonajgayle/dotnet-claude-plugin/releases/tag/v0.1.0
