---
name: init-project
description: "Create a new vertical-slice .NET 10 API that the rest of dotnet-vsa works with from day one: a .slnx solution and an ASP.NET Core project with the SharedKernel (Result, Error, auditable and aggregate-root entities with soft delete, domain events), an EF Core SQL Server DbContext that writes events to an outbox, the outbox processor and dispatcher, authorization and rate-limit policy classes, endpoint discovery, a FluentValidation filter, compose.yaml for SQL Server, and .claude/dotnet-vsa.json. Only for a repository with no .NET solution yet. Use when the user says: new project, start a new API, scaffold the project, init project, set up the solution, create the skeleton."
argument-hint: "<AppName>"
---

# Init Project

App name: `$ARGUMENTS`

Every other skill assumes the project already has a Result type, `{Entity}Errors`, soft delete, an outbox and policy classes. This skill creates them, in the shape the skills, rules and checks expect.

## Step 1: Check the repository

- `AppName` must be a PascalCase C# name, optionally dotted (`Shop`, `Contoso.Shop`). If it is missing or invalid, ask for one and stop.
- Find the repository root (`git rev-parse --show-toplevel`). If it is not a git repository, ask whether to run `git init` first.
- If the repository already has a `.sln`, `.slnx` or `.csproj`, stop: this skill is for new projects. For an existing one, point the user at `.claude/dotnet-vsa.json` (see the plugin README) and `bootstrap-tests`.
- `dotnet --version` must be 10.x. If it is not, stop and say which SDK is installed.
- If `git status --short` is not empty, ask whether to continue.

## Step 2: Confirm with the user

Show what will be created and ask before writing anything:

- `<AppName>.slnx`, `src/<AppName>.Api/` (layout below), `compose.yaml`, `.claude/dotnet-vsa.json`.
- `.env` and `src/<AppName>.Api/appsettings.Local.json` with a generated SQL Server password. Both are added to `.gitignore` and must never be committed.
- These NuGet packages (the user approves new packages):

| Package | Why | Version |
|---|---|---|
| `Microsoft.EntityFrameworkCore.SqlServer` | EF Core on SQL Server | newest 10.x |
| `Microsoft.EntityFrameworkCore.Design` | `dotnet ef` migrations | newest 10.x |
| `Microsoft.AspNetCore.Authentication.JwtBearer` | bearer tokens | newest 10.x |
| `Microsoft.AspNetCore.OpenApi` | the OpenAPI document | newest 10.x |
| `FluentValidation.DependencyInjectionExtensions` | validators and their registration | newest stable |

```text
src/<AppName>.Api/
  Program.cs                  services, pipeline, and the block where handlers are registered
  SharedKernel/               Result, Error, BaseEntity, AuditableEntity, AggregateRoot, IDomainEvent
  Domain/                     entities (add-entity)
  Features/                   slices (add-endpoint)
  Infrastructure/
    Authorization/            AuthorizationPolicies (User, Admin), ICurrentUser
    RateLimiting/             RateLimitPolicies (Read, Write), limits per caller
    Endpoints/                IEndpoint discovery, ToHttpResult(), WithValidation<T>()
    Persistence/              ApplicationDbContext, IApplicationDbContext, Configurations/
    Outbox/                   OutboxMessage, OutboxProcessor, OutboxDispatcher
```

## Step 3: Write the files

```bash
bash "${CLAUDE_SKILL_DIR}/scaffold.sh" <repo-root> <AppName>
```

It copies the template, never overwrites a file, and prints every path it wrote. Exit 2 means it refused (the reason is on stderr); report it and stop.

## Step 4: Add the packages

Pin every `Microsoft.*` package to the target framework's major version. A bare `dotnet add package` picks the newest major, which can target a newer .NET and break the build. Choose each version with the `nuget` MCP tools (newest compatible, no known vulnerability). Without them, use the helper:

```bash
cd src/<AppName>.Api
v=$(bash "${CLAUDE_SKILL_DIR}/../../scripts/nuget-version.sh" Microsoft.EntityFrameworkCore.SqlServer 10)
dotnet add package Microsoft.EntityFrameworkCore.SqlServer --version "$v"
# ...the same for Design, JwtBearer and OpenApi, with major 10
v=$(bash "${CLAUDE_SKILL_DIR}/../../scripts/nuget-version.sh" FluentValidation.DependencyInjectionExtensions)
dotnet add package FluentValidation.DependencyInjectionExtensions --version "$v"
```

## Step 5: Build and verify

```bash
dotnet build <AppName>.slnx -nologo -v q
bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --no-build
```

The project sets `TreatWarningsAsErrors`, so the build must be clean. If it fails, show the diagnostics and fix the cause; the usual one is a package on the wrong major version. The convention checks should all be `n/a` or `PASS` on an empty project.

## Step 6: Offer the next steps

Ask before each; do not run them unasked:

1. **Rules:** `install-rules`, so the conventions load when Claude edits matching files.
2. **Tests:** `bootstrap-tests` for the conventions tests, then `write-integration-tests` once the first slice exists.
3. **Database:** `docker compose up -d`, then the first entity with `add-entity` and its migration with `ef-add-migration` (create migrations with `ASPNETCORE_ENVIRONMENT=Local` so the Local connection string is used).
4. **A token for local calls:** `dotnet user-jwts create --role admin` prints a bearer token that the Local environment accepts.

## Report

The files written, the packages and versions added, the build result and the verify summary line, what was not done (no migration exists yet; the database is not started), and the next steps above. State: uncommitted. Remind the user that `.env` and `appsettings.Local.json` hold a local password and are git-ignored.

## Rules

- Never run this in a repository that already has a .NET solution or project.
- Never add a package the table does not list without asking.
- Never commit, push or stage.
