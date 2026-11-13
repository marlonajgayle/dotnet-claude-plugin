# dotnet-claude-plugin
Claude Code plugin marketplace with an agentic harness for .NET 10 projects. Ships slash commands, review and security subagents, guardrail hooks, MCP servers, and skills that enforce Domain-Driven Design with Vertical Slice Architecture, so Claude builds ASP.NET Core, Blazor, and Azure apps the way your team does.

## Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download)
- Roslyn Language Server, which gives Claude C# diagnostics after edits and symbol navigation:

  ```sh
  dotnet tool install --global roslyn-language-server --prerelease
  ```

  Make sure `~/.dotnet/tools` is on the `PATH` of the shell you launch `claude` from.

- `bash`, `git`, `perl` and [`jq`](https://jqlang.org) for the guard hooks (`brew install jq` on macOS). Without `jq` the hooks stay out of the way and the session-start message says so.

## Formatting

Every `.cs` file Claude writes or edits is formatted with `dotnet format`, using the nearest `.csproj`, so your `.editorconfig` code style and analyzer settings apply. Files outside a project get whitespace formatting only. Add an `.editorconfig` to your repo to control the style.

## Hooks

Hooks enforce the conventions that otherwise depend on Claude remembering them. They find the solution, the API project (the `Microsoft.NET.Sdk.Web` project), `Program.cs`, the outbox dispatcher and the migrations folder on their own, and do nothing in repos without a .NET API.

| Hook | When | What it does |
|---|---|---|
| `session-start.sh` | Session start | Adds context: branch, solution and API paths, migrations (latest, uncommitted, and unapplied if configured), docker compose services, whether a test project exists, and the top three P1 backlog items. Records the starting commit. |
| `guard-bash.sh` | Before Bash | Blocks commands that never exit unless run in the background (`dotnet run`/`watch`, `npm start`, `--watch`, `docker compose up` without `-d`, `tail -f`); commits on `main`/`master`; force-pushes to `main`/`master`; `docker compose down -v` and volume removal; `dotnet ef database drop` and `migrations remove` without `ASPNETCORE_ENVIRONMENT=Local`; `dotnet ef database update` against a non-local connection; `rm -rf` outside `bin/`, `obj/`, `node_modules/` and temp. |
| `guard-migrations.sh` | Before Edit/Write | Blocks edits to committed migrations. Asks before a hand edit to the model snapshot unless a new migration sits beside it. |
| `guard-config-secrets.sh` | Before Edit/Write | Blocks secrets in `appsettings*.json` other than `appsettings.Local.json`: populated secret, password, key or token values, connection strings with passwords or account keys, JWTs, private keys, and long base64 keys. The message names the key, never the value. |
| `check-cs-conventions.sh` | After Edit/Write | Advisory feedback on the edited file: unregistered handler, event without an outbox dispatch branch, endpoint without an authorization or rate-limit policy, `AsNoTracking()` without `!IsDeleted`, `= new()` on a navigation property, DTO `DateTime` not stamped UTC, `<None Include>` on a `.cs` file. |
| `stop-verify.sh` | End of turn | If API code changed this session: builds and runs the convention checks on the changed files. A failing check blocks the turn from ending (at most 3 times in a row), so Claude fixes it before reporting done. |

All checks come from one script, `scripts/verify-conventions.sh`, which the `verify` skill also runs.

## Agents

Seven subagents that take a change from request to merge decision and documentation. Each hands its work to the next through a file, so you can run them one at a time, stop between steps, or rerun one after a fix.

| Agent | Reads | Writes | What it does |
|---|---|---|---|
| `spec-writer` | the request, the codebase | `.ai/specs/<slug>.md` | Writes the spec for a feature or bug fix (bugs add reproduction, root cause and a regression test), including UX and risk notes. No code. |
| `implementer` | the spec, review reports | code on `feature/<slug>` or `bugfix/<slug>` | Implements the spec with the scaffolding skills and verifies it; later fixes review findings. Leaves changes uncommitted unless asked. |
| `code-reviewer` | the branch diff, spec, `CLAUDE.md`, `.claude/rules/` | `.ai/reviews/<slug>/code.md` | Conventions, project rules, correctness, performance, tests and spec conformance. Read-only. |
| `security-reviewer` | the branch diff | `.ai/reviews/<slug>/security.md` | Authorization and IDOR, validation, injection, secrets, auth and CORS changes, data exposure, new packages. Read-only. |
| `ux-reviewer` | the branch diff, the design doc, the spec's UX section | `.ai/reviews/<slug>/ux.md` | User-facing changes against `DESIGN.md` and WCAG 2.2 AA; "not applicable" when nothing user-facing changed. Read-only. |
| `approver` | the three reports, the diff | `.ai/reviews/<slug>/decision.md` | Checks the reviews are complete and current, reruns verification, scores risk, and decides MERGE or HUMAN REVIEW. Merges only when `approver.autoMerge` is on. |
| `documenter` | the decision, spec, reports and code | `docs/features/<slug>.md`, `docs/README.md` | Once a change is approved, writes a tutorial-style guide with the `write-feature-docs` skill. Changes only files under `docs/`. |

A typical run: ask for the spec, then "use the implementer agent on <slug>", then run the three reviewers (they are independent, so they can run in parallel), have the implementer fix any findings and rerun the reviewers, then ask the approver. Once it decides MERGE, run the documenter before merging so the guide ships with the code; docs-only commits after the review do not make the reports stale.

The approver sends a change to a human when any gate fails (dirty tree, missing or stale review, open Critical or High finding, failing verification or checks) or when its risk is above `approver.maxAutoMergeRisk`. Migrations that alter data, authentication and authorization changes, breaking API contract changes and hotfixes are always Critical; any other migration, `Program.cs` pipeline changes, new packages, new anonymous endpoints and infrastructure files are High.

## Skills

| Skill | Purpose |
|---|---|
| `plan` | Explore the codebase and write a feature spec to `.ai/specs/<slug>.md`. |
| `implement-feature` | Implement a spec on a feature branch, then verify. |
| `review-pr` | Read-only pre-merge review: conventions, security, performance, spec conformance. |
| `verify` | Run the verification checklist and print a pass/fail table. |
| `add-entity` | Entity, `{Name}Errors`, EF configuration and DbSet, then a migration. |
| `add-endpoint` | One complete slice (command/query, handler, endpoint, validator) with DI wired. |
| `add-domain-event` | Event, handler, DI registration and outbox dispatch branch together. |
| `register-handler` | Add a missing `AddScoped<>` registration (and dispatch branch for event handlers). |
| `add-background-job` | A `BackgroundService` with options, jitter, a scope per run and a health check. |
| `ef-core` | EF Core 10 reference for this architecture. |
| `ef-add-migration` | Generate a migration and review it for destructive operations before applying. |
| `check-ef-performance` | Read-only scan for N+1, missing indexes, unbounded queries and outbox-bypassing bulk updates. |
| `fix-utc-kinds` | Find and fix `DateTime` values that reach clients without a UTC kind. |
| `audit-authorization` | Endpoint table with policies and rate limits; flags IDOR candidates. |
| `security-audit` | Six-layer security audit with a severity-rated report. |
| `package-health` | Vulnerable, deprecated and outdated NuGet packages. |
| `api-contract-diff` | Breaking OpenAPI changes on this branch compared with `main`. |
| `bootstrap-tests` | Create the test project with three conventions tests. |
| `write-handler-tests` | xUnit tests for one handler: success, each error, soft-deleted rows, side effects. |
| `run-api` | Start the API (and compose services) in the background and wait for `/health`. |
| `smoke-health` | Check `/health`, the OpenAPI document and that this branch's routes are live. |
| `write-feature-docs` | Tutorial-style feature guide in `docs/features/<slug>.md`: steps with commands and output, a Mermaid diagram, and endpoint, error, event and configuration reference. |
| `backlog-sync` | Add or close items in `.ai/backlog.md`. |
| `install-rules` | Copy the plugin's path-scoped rules into `.claude/rules/` (once the plugin ships rules). |

## Configuration

Discovery works without configuration. To override a path or switch a check off, add `.claude/dotnet-vsa.json` to your repo (paths are relative to the repo root; every key is optional):

```json
{
  "sln": "src/MyApp.sln",
  "apiProject": "src/MyApp.Api/MyApp.Api.csproj",
  "programCs": "src/MyApp.Api/Program.cs",
  "outboxDispatcher": "src/MyApp.Api/Infrastructure/Outbox/OutboxProcessor.cs",
  "migrationsDir": "src/MyApp.Api/Infrastructure/Persistence/Migrations",
  "specsDir": ".ai/specs",
  "reviewsDir": ".ai/reviews",
  "backlogFile": ".ai/backlog.md",
  "designDoc": "DESIGN.md",
  "docsDir": "docs",
  "healthUrl": "https://localhost:7143/health",
  "localEnvironment": "Local",
  "appliedMigrationsCommand": "",
  "protectMain": true,
  "fast": false,
  "checks": {
    "handlerDi": true, "outbox": true, "endpointAuth": true, "rateLimit": true,
    "softDelete": true, "phantomNav": true, "utcKinds": true, "csproj": true
  },
  "approver": { "autoMerge": false, "maxAutoMergeRisk": "low", "mergeMethod": "squash" }
}
```

- `designDoc` is the design document the `ux-reviewer` and `spec-writer` agents use. Without it they look for `DESIGN.md` or `design.md` at the repo root, then under `docs/`.
- `docsDir` is where the `documenter` agent and `write-feature-docs` skill write guides (`<docsDir>/features/<slug>.md`) and the index (`<docsDir>/README.md`).
- `approver.autoMerge: true` lets the `approver` agent run `gh pr merge` when its decision is MERGE and the branch has an open PR. Off by default: the approver decides and reports only. `maxAutoMergeRisk` (`low` or `medium`) is the highest risk it may merge without a person; High and Critical always go to a human.
- `fast: true` skips the build in the end-of-turn check and keeps only the convention checks.
- `appliedMigrationsCommand` is a shell command that prints applied migration ids, one per line (for example a `sqlcmd` query against `__EFMigrationsHistory`). When set, session start reports unapplied migrations.
- Checks switch themselves off where they do not apply: handler DI when handlers are registered by assembly scanning, endpoint authorization when a `FallbackPolicy` is set, soft delete when a global `IsDeleted` query filter exists, and UTC kinds when a model-wide converter exists.
- Anonymous endpoints pass the authorization check when marked with a `// anonymous: <reason>` comment.
