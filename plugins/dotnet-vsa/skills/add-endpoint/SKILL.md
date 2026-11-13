---
name: add-endpoint
description: "Scaffold one complete vertical slice (Command or Query record, Handler, Endpoint, Validator) and register the handler in DI in one pass. Defaults to Result<T>, IApplicationDbContext, AsNoTracking + !IsDeleted for queries, soft delete + audit for commands, an authorization policy and a rate-limit policy. Verifies with dotnet build. Use for a one-off slice that does not need a spec: add endpoint, scaffold CRUD, new feature slice, create a query, create a command, generate handler."
argument-hint: "<get|list|create|update|delete> <Domain>.<Name> [--anon] [--no-validator]"
---

# Add Endpoint

Scaffolds a single slice for when the user already knows what they want and a spec (`plan` / `implement-feature`) is overkill. The result builds clean with DI wired.

Arguments: `$ARGUMENTS`

- `verb`: `get`, `list`, `create`, `update` or `delete`.
- `Domain`: a folder under `<API_DIR>/Features/`.
- `Name`: PascalCase, without a `Command`/`Query` suffix.
- `--anon`: no authorization (requires a `// anonymous: <reason>` comment; ask the user for the reason).
- `--no-validator`: skip the validator (rarely right).

Example: `add-endpoint create Orders.CancelOrder`

## Step 0: Locate the project

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `API_DIR`, `PROGRAM_CS`, `DBCONTEXT`, `AUTH_POLICIES`, `RATE_LIMIT_POLICIES` and `SLN` below.

## Step 1: Validate

- On bad input reply with the usage line from `argument-hint` and stop.
- `<API_DIR>/Features/<Domain>/` must exist; if not, ask whether to create a new domain.
- `<API_DIR>/Features/<Domain>/<Name>/` must not exist; if it does, stop. Never scaffold over existing code.
- One slice per run. If several were requested, ask which first.
- If the slice needs an entity that does not exist yet, stop and suggest `add-entity` first.

## Step 2: Mirror a sibling

Glob `Features/<Domain>/*/` and read the closest sibling of the same verb. Copy its conventions exactly:

- Route prefix and pattern (`/orders`, `/orders/{id:guid}`).
- Handler suffix (`Handler`, `CommandHandler` or `QueryHandler`; match the domain).
- Where DTO records live (own file or inside the query file).
- The authorization policy constant it uses from `<AUTH_POLICIES>`, and the rate-limit constant from `<RATE_LIMIT_POLICIES>`.
- Endpoint shape: logging, try/catch, `.WithName`, `.WithTags`, `.Produces<>` metadata.

Never invent a route pattern or a policy string. If the policy is unclear, pick the least-privileged policy siblings use and name the choice in the report.

## Step 3: Generate files in `Features/<Domain>/<Name>/`

Queries (`get`, `list`):

- `<Name>Query.cs`: `public sealed record <Name>Query(...)`.
- `<Name>QueryHandler.cs`: `public sealed class` with primary-constructor DI on `IApplicationDbContext`. Returns `Result<<Name>Dto>` or `Result<IReadOnlyList<<Name>Dto>>`. Reads use `.AsNoTracking()`, `.Where(x => !x.IsDeleted)`, and project with `Select` to a DTO. Every `DateTime` in the projection is wrapped in `DateTime.SpecifyKind(x, DateTimeKind.Utc)` unless the project has a model-wide UTC converter. Missing rows return `{Entity}Errors.NotFound(id)`.
- `<Name>Endpoint.cs`: implements `IEndpoint`, `MapGet`, returns `result.ToHttpResult()`.
- `<Name>Validator.cs`: only when the route has parameters worth validating.

Commands (`create`, `update`, `delete`):

- `<Name>Command.cs`: `public sealed record` with the inputs.
- `<Name>CommandHandler.cs`: create builds the entity, calls `SetCreatedAuditInfo`, `Add`, `SaveChangesAsync(ct)`. Update loads with `!IsDeleted`, mutates through aggregate methods, calls `SetModifiedAuditInfo`. Delete loads, calls `MarkAsDeleted()`, never `Remove`. Return `Result`/`Result<T>`; failures use `{Entity}Errors`.
- `<Name>Endpoint.cs`: `MapPost`/`MapPut`/`MapDelete` with `.RequireAuthorization(AuthorizationPolicies.X)` (or `--anon` plus its comment) and `.RequireRateLimiting(RateLimitPolicies.X)`.
- `<Name>Validator.cs`: `AbstractValidator<<Name>Command>`.

Always: file-scoped namespaces, `CancellationToken` passed to every async call, and the caller's own id taken from the authenticated user, never from the route or body.

## Step 4: Register the handler

Follow the `register-handler` skill's Step 4: add `AddScoped<...>()` at the end of the domain's block in `<PROGRAM_CS>`.

## Step 5: Verify

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --changed-since HEAD`. It builds and checks DI, authorization and rate limiting for the new files. Fix every FAIL. On a build failure, the usual causes are a missing policy constant or a DbSet name that is not the plural you guessed; re-read the source and fix. Never delete generated files to get a clean build.

## Step 6: Report

```markdown
## Added endpoint: `<verb> <Domain>.<Name>`
- Route: `<METHOD> <route>`
- Policy: `AuthorizationPolicies.X` (or "anonymous: <reason>")
- Rate limit: `RateLimitPolicies.X`
- Files: <links>
- DI: [Program.cs:LN](...)
- Verify: <summary line>
Next: implement the handler body; add-entity / ef-add-migration if the model changed; run-api + smoke-health to see it in OpenAPI.
State: uncommitted.
```

## Rules

- Inject `IApplicationDbContext`, never the concrete DbContext.
- Reuse `Result<T>`, `Error`, `ErrorType`, `IEndpoint` and the base entities from SharedKernel; never redeclare them.
- No new NuGet packages; report a missing dependency instead.
- Never commit, push or stage.
