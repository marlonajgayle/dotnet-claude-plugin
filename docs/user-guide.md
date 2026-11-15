# dotnet-vsa user guide

This guide takes you from a machine without the plugin to shipping a reviewed feature in a .NET 10 API. Follow the parts in order the first time; later you can jump to the part you need.

1. [Install the prerequisites](#part-1-install-the-prerequisites)
2. [Install the plugin](#part-2-install-the-plugin)
3. [Check that it works](#part-3-check-that-it-works)
4. [Set up a project](#part-4-set-up-a-project): a new API, or an existing one
5. [Build a feature step by step](#part-5-build-a-feature-step-by-step)
6. [Ship a change with the full pipeline](#part-6-ship-a-change-with-the-full-pipeline)
7. [Day-to-day checks](#part-7-day-to-day-checks)
8. [Work with the guardrails](#part-8-work-with-the-guardrails)
9. [Share the setup with your team](#part-9-share-the-setup-with-your-team)
10. [Update or remove the plugin](#part-10-update-or-remove-the-plugin)
11. [Troubleshooting](#troubleshooting)

The examples use an app called `Shop` with an `Orders` area. Replace the names with your own.

Every skill is also a slash command, written `/dotnet-vsa:<skill>`. You don't have to type them: asking in plain words ("add an endpoint to cancel an order") loads the same skill. This guide shows the slash commands because they are exact.

---

## Part 1: Install the prerequisites

You need these once per machine.

### Step 1. Install the .NET 10 SDK

Download it from [dotnet.microsoft.com/download](https://dotnet.microsoft.com/download), then check:

```sh
dotnet --version
```

The output starts with `10.`.

### Step 2. Install the Roslyn Language Server

It gives Claude C# diagnostics after each edit and lets it navigate symbols.

```sh
dotnet tool install --global roslyn-language-server --prerelease
```

Make sure `~/.dotnet/tools` is on your `PATH`:

```sh
echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> ~/.zprofile   # macOS; use ~/.bashrc or ~/.profile on Linux
```

### Step 3. Install the shell tools

The guard hooks need `bash`, `git`, `perl` and `jq`. macOS and most Linux distributions have all but `jq`:

```sh
brew install jq          # macOS
sudo apt install jq      # Debian and Ubuntu
```

Without `jq`, the hooks stay out of the way and the session-start message tells you so. You lose the guardrails, not the skills.

### Step 4. Install Node.js 18 or later

From [nodejs.org](https://nodejs.org). The Context7 documentation server starts with `npx`.

### Step 5. Create a GitHub token (optional)

The bundled GitHub MCP server lets Claude read issues, pull requests and Actions runs. Skip this step if you don't use GitHub; everything else still works.

1. Open [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new).
2. Choose the repositories you work on.
3. Grant **read** access to Issues, Pull requests, Actions and Contents. Add **write** access to Pull requests only if Claude should comment on PRs.
4. Export the token in your shell profile:

   ```sh
   export GITHUB_PERSONAL_ACCESS_TOKEN=github_pat_...
   ```

### Step 6. Install Docker (optional)

Docker (or Podman) runs SQL Server locally and the integration tests. You can scaffold and build without it, but you need it to run the API against a database.

---

## Part 2: Install the plugin

Install the plugin at project scope, once per .NET repository. Project scope records the marketplace and the plugin in the repository's `.claude/settings.json`, so the plugin is active only in that repository, in both the terminal CLI and the VS Code extension, and everyone who opens the repository is offered it once you commit the file (see [Part 9](#part-9-share-the-setup-with-your-team)).

### Option A: from the Claude Code CLI

1. Go to the root of your .NET repository:

   ```sh
   cd ~/src/Shop
   ```

2. Add the marketplace and install the plugin at project scope:

   ```sh
   claude plugin marketplace add marlonajgayle/dotnet-claude-plugin --scope project
   claude plugin install dotnet-vsa@dotnet-claude-plugin --scope project
   ```

3. Commit the `.claude/settings.json` the commands wrote.

4. Start a session with `claude`. The plugin loads when a session starts.

Inside a session you can use the plugin manager instead: type `/plugins`, choose `dotnet-vsa`, and pick the project scope when it asks where to install.

### Option B: from VS Code

1. Open the Extensions view (`Cmd+Shift+X` on macOS, `Ctrl+Shift+X` elsewhere), search for **Claude Code**, and install the extension published by Anthropic. Open it from the Claude icon in the activity bar and sign in.
2. Make your environment visible to VS Code. The extension uses VS Code's environment, not that of a terminal you have open, so the `PATH` and token exports from Part 1 must be in your shell profile. Then **quit VS Code completely** (`Cmd+Q` on macOS) and start it again, or start it from a terminal with `code .`.

   If a variable still doesn't reach the extension, put it under `env` in `~/.claude/settings.json`. That file is never committed, but it stores the token as plain text.
3. Open your .NET repository as the workspace folder. Run the two commands from Option A in VS Code's integrated terminal, which starts in the workspace root, or type `/plugins` in the Claude Code panel, choose `dotnet-vsa` and pick the project scope. Commit the `.claude/settings.json` it writes.
4. Start a new session in the panel.

---

## Part 3: Check that it works

Open a session in a repository (any repository works for the first two checks).

1. **Skills are listed.** Type `/dotnet-vsa:` in the prompt. The list shows `ship`, `init-project`, `add-endpoint` and the other skills.
2. **MCP servers are connected.** Type `/mcp`. You see `microsoft-learn`, `nuget`, `context7` and `github`. A server that failed to connect usually means a missing prerequisite: `nuget` needs the .NET 10 SDK, `context7` needs Node.js, `github` needs the token. The session-start message also lists servers that cannot start.
3. **The project was discovered.** In a repository with a .NET API, ask:

   ```text
   Which solution and API project did the plugin find?
   ```

   Claude answers from the session-start context: the branch, the solution, the API project, the latest migration and the compose services. In a repository with no .NET API the hooks stay silent. That is expected.

---

## Part 4: Set up a project

Choose **4A** for a new API or **4B** for an API you already have.

### 4A. Start a new API

`init-project` creates an API with everything the other skills assume: a `Result` type, soft delete and audit fields, an outbox for domain events, authorization and rate-limit policies, endpoint discovery and validation.

#### Step 1. Create an empty repository

```sh
mkdir shop && cd shop
git init
```

The repository must not contain a `.sln`, `.slnx` or `.csproj` yet.

#### Step 2. Run the scaffold

Start Claude Code in the folder and run:

```text
/dotnet-vsa:init-project Shop
```

To run SQL Server and the API through .NET Aspire (with the Aspire dashboard and OpenTelemetry) instead of `compose.yaml`, add `--aspire`:

```text
/dotnet-vsa:init-project Shop --aspire
```

Claude shows the files and NuGet packages it will add and waits for your approval. Then it writes the files, adds the packages pinned to .NET 10, builds, and runs the convention checks. On a new project every check reports `PASS` or `n/a`.

You get:

```text
Shop.slnx
compose.yaml                      (not with --aspire)
.env                              local SQL Server password, git-ignored
.claude/dotnet-vsa.json           plugin configuration
src/Shop.Api/
  Program.cs
  SharedKernel/                   Result, Error, base entities, IDomainEvent
  Domain/                         your entities
  Features/                       your slices
  Infrastructure/                 authorization, rate limiting, endpoints, persistence, outbox
  appsettings.Local.json          local connection string, git-ignored
src/Shop.AppHost/                 (only with --aspire)
src/Shop.ServiceDefaults/         (only with --aspire)
```

Nothing is committed. `.env` and `appsettings.Local.json` hold a generated password and must stay out of git.

#### Step 3. Install the rules

```text
/dotnet-vsa:install-rules
```

This copies the plugin's rules to `.claude/rules/dotnet-vsa/` after showing you a diff. Each rule loads only when Claude touches a matching file, for example the endpoint rule when it edits `*Endpoint.cs`.

#### Step 4. Create the test project

```text
/dotnet-vsa:bootstrap-tests
```

This adds an xUnit project with three conventions tests that fail when a handler isn't registered, a domain event has no outbox dispatch branch, or an endpoint has no authorization.

#### Step 5. Start the database

Without Aspire:

```sh
docker compose up -d
```

With Aspire, the AppHost starts SQL Server for you; `run-api` (Part 7) starts the AppHost.

#### Step 6. Make your first commit

```sh
git add -A
git commit -m "chore: scaffold Shop API"
```

Check that `git status` doesn't list `.env` or `appsettings.Local.json` as staged.

Continue with [Part 5](#part-5-build-a-feature-step-by-step).

### 4B. Use an existing API

The plugin finds your solution, API project (the one using `Microsoft.NET.Sdk.Web`), `Program.cs`, outbox dispatcher and migrations folder by itself.

#### Step 1. Check discovery

Open a session at the repository root and ask which solution and API project the plugin found (Part 3, check 3).

#### Step 2. Override what it got wrong

If discovery picked the wrong path, or your repository has several APIs, create `.claude/dotnet-vsa.json` with only the keys you need:

```json
{
  "sln": "src/MyApp.sln",
  "apiProject": "src/MyApp.Api/MyApp.Api.csproj",
  "migrationsDir": "src/MyApp.Api/Infrastructure/Persistence/Migrations",
  "baseBranch": "main"
}
```

Paths are relative to the repository root. Start a new session for the change to take effect. The README's [Configuration](../README.md#configuration) section lists every key.

#### Step 3. Switch off checks that don't fit

Checks switch themselves off where they don't apply. For example, the handler registration check is off when you register handlers by assembly scanning (Scrutor, MediatR, Wolverine), and the authorization check is off when a `FallbackPolicy` is set. To turn one off yourself:

```json
{
  "checks": { "rateLimit": false }
}
```

#### Step 4. Install the rules

```text
/dotnet-vsa:install-rules
```

The rules assume slices under `Features/` and entities under `Domain/`. If your layout differs, copy the rules to a folder outside `.claude/rules/dotnet-vsa/` and adjust their `paths:`. The skill never writes outside its own folder.

#### Step 5. Run the checks once

```text
/dotnet-vsa:verify full
```

You get a pass/fail table. Fix or switch off what fails before you rely on the end-of-turn check, which blocks Claude from finishing while a check on changed files fails.

#### Step 6. Add tests if you have none

```text
/dotnet-vsa:bootstrap-tests
```

#### Step 7. Commit the plugin files

```sh
git add .claude/rules/dotnet-vsa .claude/dotnet-vsa.json
git commit -m "chore: add dotnet-vsa rules and configuration"
```

---

## Part 5: Build a feature step by step

This part builds an "orders" feature one piece at a time, so you see what each skill does. Part 6 shows how to get the same result with one command.

Work on a branch. The Bash guard blocks commits on `main` and `master`.

```sh
git switch -c feature/orders
```

### Step 1. Add an entity

```text
/dotnet-vsa:add-entity Orders.Order CustomerId:Guid Total:decimal Notes:string? --aggregate
```

Claude writes the entity under `Domain/Orders/`, an `OrderErrors` class, the EF Core configuration and the `DbSet`. `--aggregate` makes it an aggregate root, which can raise domain events. It then offers to create the migration.

### Step 2. Create and apply the migration

```text
/dotnet-vsa:ef-add-migration AddOrders apply
```

Claude generates the migration, reviews it for destructive operations (dropped columns or tables, data loss) and, with `apply`, updates your **local** database. Leave out `apply` to review first.

The Bash guard only lets `dotnet ef database update` run against a local database, and committed migrations can't be edited. Add a new migration instead.

### Step 3. Add endpoints

One command creates a whole slice: the command or query, its handler, the endpoint, the validator, and the DI registration.

```text
/dotnet-vsa:add-endpoint create Orders.CreateOrder
/dotnet-vsa:add-endpoint get Orders.GetOrder
/dotnet-vsa:add-endpoint list Orders.ListOrders
/dotnet-vsa:add-endpoint delete Orders.DeleteOrder
```

Every endpoint gets an authorization policy and a rate limit. For a public endpoint, add `--anon`; Claude marks it with an `// anonymous: <reason>` comment so the check accepts it. `--no-validator` skips the validator.

### Step 4. Add a domain event (optional)

When something else should happen after an order is placed:

```text
/dotnet-vsa:add-domain-event Orders.OrderPlaced OrderId:Guid CustomerId:Guid
```

This writes the event, its handler, the DI registration and the outbox dispatch branch together. Events go through the outbox, so they're delivered even if the process stops right after the save.

### Step 5. Write tests

Handler tests run fast against SQLite in memory:

```text
/dotnet-vsa:write-handler-tests CreateOrderHandler
```

Integration tests call the endpoint over HTTP against SQL Server in a container (Docker must be running). They cover 401, 403, validation, success, another user's data and soft-deleted rows:

```text
/dotnet-vsa:write-integration-tests Orders.CreateOrder
```

### Step 6. Run the API and try it

```text
/dotnet-vsa:run-api
```

Claude starts the database (compose or the Aspire AppHost) and the API in the background and waits for `/health`. Then:

```text
/dotnet-vsa:smoke-health
```

checks `/health`, the OpenAPI document, and that this branch's routes are live.

To call protected endpoints yourself, create a local token:

```sh
dotnet user-jwts create --role admin
```

Stop the API when you're done:

```text
/dotnet-vsa:run-api stop
```

### Step 7. Verify and commit

```text
/dotnet-vsa:verify
```

When the table is all `PASS` or `n/a`, commit:

```sh
git add -A
git commit -m "feat: orders"
```

---

## Part 6: Ship a change with the full pipeline

`ship` runs seven agents in sequence: it writes a spec, implements it, reviews it from three angles, fixes the findings, decides whether it can merge, and documents it. It commits after each step on its own branch and stops whenever a person should decide.

### Step 1. Start from a clean working tree

```sh
git status --short
```

The output must be empty. Commit or stash first: `ship` commits as it goes and must not pick up unrelated changes.

### Step 2. Describe the change

```text
/dotnet-vsa:ship Let customers cancel an order while it is still pending
```

You can name a GitHub issue (`#123`) and the spec-writer reads it.

### Step 3. Approve the spec

The `spec-writer` writes `.ai/specs/<slug>.md` and Claude shows you its requirements, steps and risks. Approve it, or say what to change. If the spec has open questions, Claude asks you first.

`--auto` skips this pause. Open questions still stop the run.

### Step 4. Let it implement and review

Without further input from you:

1. The `implementer` creates `feature/<slug>` (or `bugfix/<slug>`), writes the code with the skills from Part 5, verifies it, and the run commits it.
2. The `code-reviewer`, `security-reviewer` and `ux-reviewer` run in parallel and write their reports to `.ai/reviews/<slug>/`. The UX reviewer runs only when something user-facing changed.
3. If a report has a Critical or High finding, the implementer fixes it and all reviewers run again. This repeats up to two rounds (`--rounds N` changes that). If findings remain after the last round, Claude stops and asks you how to proceed.

### Step 5. Read the decision

The `approver` checks that every review is current, reruns verification, scores the risk, and writes `.ai/reviews/<slug>/decision.md`:

- **MERGE**: the branch is ready. It doesn't merge unless you turned on `approver.autoMerge` (see Part 9).
- **HUMAN REVIEW**: Claude shows the risk level and the reasons. Migrations that alter data, authentication or authorization changes and breaking API changes always land here. You decide.

### Step 6. Get the documentation

After MERGE, the `documenter` writes a tutorial-style guide to `docs/features/<slug>.md` and the run commits it. Skip it with `--no-docs`.

### Step 7. Push and open a PR

`ship` never pushes or opens a PR unless you ask. When you're ready:

```sh
git push -u origin feature/<slug>
```

Or ask Claude to push and open the PR.

### Resuming a run

To pick up an existing spec at a later step:

```text
/dotnet-vsa:ship cancel-pending-order --from review
```

`--from` accepts `implement`, `review` and `approve`.

### Running the agents by hand

You can also run each agent yourself and stop between them:

1. "Write a spec for letting customers cancel a pending order."
2. "Use the implementer agent on cancel-pending-order."
3. "Run the code, security and UX reviewers on cancel-pending-order."
4. "Have the implementer fix the findings", then rerun the reviewers.
5. "Ask the approver for a decision on cancel-pending-order."
6. "Use the documenter on cancel-pending-order."

---

## Part 7: Day-to-day checks

| When | Run |
|---|---|
| Before a PR | `/dotnet-vsa:verify`, `/dotnet-vsa:api-contract-diff` |
| After adding endpoints | `/dotnet-vsa:audit-authorization` |
| Queries feel slow | `/dotnet-vsa:check-ef-performance` |
| Clients get local times | `/dotnet-vsa:fix-utc-kinds` |
| Regularly, or before a release | `/dotnet-vsa:package-health`, `/dotnet-vsa:security-audit` |
| A handler isn't found at runtime | `/dotnet-vsa:register-handler CreateOrderHandler` |
| Something runs on a schedule | `/dotnet-vsa:add-background-job ExpireCarts --every 15m` |
| Tracking follow-ups | `/dotnet-vsa:backlog-sync add fix "Cancel returns 500 for shipped orders"` |
| Documenting a finished feature | `/dotnet-vsa:write-feature-docs <slug>` |

What each one gives you:

- **`verify`**: a pass/fail table of the build and every convention check. `changed` checks only this branch's files, `full` everything; `--tests` adds `dotnet test`.
- **`api-contract-diff`**: breaking OpenAPI changes compared with `main`, written to `.ai/reviews/<slug>/api-contract.md`.
- **`audit-authorization`**: a table of every endpoint with its policy and rate limit, flagging endpoints that load data by id without an ownership check.
- **`check-ef-performance`**: a read-only scan for N+1 queries, missing indexes, unbounded queries and bulk updates that bypass the outbox.
- **`package-health`**: vulnerable, deprecated and outdated NuGet packages. Ask "fix my vulnerable packages" to apply the fixes.
- **`security-audit`**: a six-layer audit with a severity-rated report in `.ai/reviews/_audits/`. Add that folder to `.gitignore`.
- **`backlog-sync`**: keeps `.ai/backlog.md`. The top three P1 items appear in every session-start message.

### Run tests at the end of every turn

By default, when Claude finishes a turn that changed API code, it builds and runs the convention checks on the changed files, and keeps working if one fails. To add tests, set `stopTests` in `.claude/dotnet-vsa.json`:

```json
{
  "stopTests": "changed",
  "stopTestsFilter": "Category!=Integration"
}
```

`changed` runs the tests named after the changed slices; `all` runs everything. The default filter keeps the Docker-based integration tests out. Set `"fast": true` to skip the build and keep only the convention checks.

---

## Part 8: Work with the guardrails

The hooks run on every session. You don't call them; you notice them when they stop something. Each block message says what to do instead.

| You see Claude blocked from | Why | What to do |
|---|---|---|
| `dotnet run`, `dotnet watch`, `docker compose up` without `-d` | They never exit and would hang the session | Use `/dotnet-vsa:run-api`, or run them in the background |
| Committing or force-pushing on `main`/`master` | Protects the main branch | Work on a branch |
| `git reset --hard`, `git clean -f`, `git checkout .`, `git branch -D` | They destroy work for good | Run them yourself in a terminal if you really mean it |
| `docker compose down -v`, `dotnet ef database drop` | They delete data | Set `ASPNETCORE_ENVIRONMENT=Local` for local-only `ef` commands |
| `dotnet ef database update` against a non-local database | Production migrations shouldn't come from a chat | Apply them through your deployment pipeline |
| Editing a committed migration | Others may already have applied it | Add a new migration |
| Writing a secret into `appsettings.json`, `.env`, `launchSettings.json` or code | It would be committed | Put it in `appsettings.Local.json`, user secrets or environment variables |

After every C# edit, Claude also gets advice about the edited file (an unregistered handler, an endpoint without a policy, a query missing the soft-delete filter) and every `.cs` file it writes is formatted with `dotnet format` using your `.editorconfig`.

---

## Part 9: Share the setup with your team

### Step 1. Offer the plugin to everyone who opens the repository

Commit `.claude/settings.json`. The project-scope install in Part 2 writes these entries; you can also write them by hand:

```json
{
  "extraKnownMarketplaces": {
    "dotnet-claude-plugin": {
      "source": { "source": "github", "repo": "marlonajgayle/dotnet-claude-plugin" }
    }
  },
  "enabledPlugins": {
    "dotnet-vsa@dotnet-claude-plugin": true
  }
}
```

When a teammate trusts the folder, Claude Code offers to install the marketplace and plugin. Each person still installs the prerequisites (Part 1) and uses their own GitHub token.

### Step 2. Commit the shared files

| Commit | Don't commit |
|---|---|
| `.claude/settings.json` | `.env` |
| `.claude/dotnet-vsa.json` | `appsettings.Local.json` |
| `.claude/rules/dotnet-vsa/` | `.ai/reviews/_audits/` |
| `.ai/specs/`, `.ai/reviews/<slug>/`, `.ai/backlog.md` | |
| `docs/features/` | |

### Step 3. Decide on auto-merge (optional)

By default the approver only decides. To let it merge low-risk changes that have an open PR:

```json
{
  "approver": { "autoMerge": true, "maxAutoMergeRisk": "low", "mergeMethod": "squash" }
}
```

High and Critical risk always go to a person.

### Step 4. Add project MCP servers (optional)

Playwright, Sentry, Azure and Azure DevOps aren't bundled. The README's [Optional servers](../README.md#optional-servers-for-your-project) section has a `.mcp.json` snippet for each.

---

## Part 10: Update or remove the plugin

Update:

```sh
claude plugin marketplace update dotnet-claude-plugin
```

Then start a new session in each repository and check whether the rules changed:

```text
/dotnet-vsa:install-rules --check
```

The session-start message also tells you when the repository's rules are older than the plugin. Run `/dotnet-vsa:install-rules` to update them and commit the result.

Remove, from the repository root:

```sh
claude plugin uninstall dotnet-vsa@dotnet-claude-plugin --scope project
```

The files the plugin wrote into your repositories (`.claude/rules/dotnet-vsa/`, `.claude/dotnet-vsa.json`, `.ai/`) stay until you delete them.

---

## Troubleshooting

**The skills don't appear under `/dotnet-vsa:`.**
Start a new session; plugins load at session start. Check that `/plugin` lists `dotnet-vsa` as installed and enabled.

**The session-start message says `jq` is missing.**
Install it (Part 1, Step 3) and start a new session. Until then the hooks do nothing.

**An MCP server shows as failed in `/mcp`.**
`nuget` needs `dnx` from the .NET 10 SDK, `context7` needs `npx` from Node.js, and `github` needs `GITHUB_PERSONAL_ACCESS_TOKEN`. In VS Code, quit the editor completely after changing your profile, or set the variable under `env` in `~/.claude/settings.json`. To turn off a server you don't use, disable it in `/mcp`.

**The hooks say nothing in my repository.**
They stay silent when they find no API project (a project using `Microsoft.NET.Sdk.Web`). Ask Claude which project it found, and set `apiProject` in `.claude/dotnet-vsa.json` if needed.

**Claude keeps working after I expected it to stop.**
The end-of-turn check found a failing build or convention check and sent Claude back to fix it. It gives up after three blocks in a row. Run `/dotnet-vsa:verify` to see the failure, or switch the check off in `.claude/dotnet-vsa.json` if it doesn't fit your project.

**A check flags an endpoint that's meant to be public.**
Add a comment such as `// anonymous: health probe for the load balancer` above the endpoint mapping.

**`init-project` refuses to run.**
It runs only in a repository without a `.sln`, `.slnx` or `.csproj`, and only with the .NET 10 SDK. For an existing project, follow Part 4B.

**The session-start message mentions unapplied migrations.**
It can only know this if you set `appliedMigrationsCommand` in `.claude/dotnet-vsa.json` and trusted it in your own terminal. The session-start message prints the exact `trust-command.sh` command to run. See the README's [Configuration](../README.md#configuration) section.
