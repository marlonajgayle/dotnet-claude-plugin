---
name: bootstrap-tests
description: "Create the missing xUnit test project for a vertical-slice .NET API, add it to the solution, and seed three Roslyn-based conventions tests that fail when (1) a *Handler under Features/ has no AddScoped<> registration, (2) an IDomainEvent has no nameof() branch in the outbox dispatcher, (3) an endpoint has neither RequireAuthorization nor an '// anonymous:' justification. Turns silent runtime failures into dotnet test failures. Use when the user says: bootstrap tests, create test project, add xunit, set up testing, add conventions tests."
---

# Bootstrap Tests

Creates `tests/<Api>.Tests/` with three conventions tests that run as static analysis over the source (Roslyn syntax trees). They need no database and do not start the app.

## Step 0: Locate the project

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `ROOT`, `SLN`, `API_PROJECT`, `API_DIR`, `PROGRAM_CS`, `OUTBOX_DISPATCHER` and `TEST_PROJECTS`.

## Step 1: Pre-flight

- If `TEST_PROJECTS` is non-empty, stop and list them. Never overwrite a test project.
- `dotnet --version` must match the SDK the API targets (read `global.json` if present).
- If `git status --short` is dirty, ask whether to continue.
- Test location: a `tests/` folder beside the API's `src/` folder if one exists, otherwise `tests/` at the repo root. Name: `<ApiProjectName>.Tests`.

## Step 2: Create the project

```bash
dotnet new xunit -n <Api>.Tests -o <tests-dir>/<Api>.Tests
cd <tests-dir>/<Api>.Tests
dotnet add package Microsoft.CodeAnalysis.CSharp
dotnet add reference <relative path to API_PROJECT>
cd - && dotnet sln <SLN> add --include-references false <tests-dir>/<Api>.Tests/<Api>.Tests.csproj
```

Delete the template's `UnitTest1.cs`. Use plain xUnit `Assert` (no extra assertion library unless the solution already uses one).

## Step 3: `Conventions/SourceFiles.cs`

Locates the API folder from the test assembly by walking up to the directory containing the solution file, then joining the API's repo-relative path (`API_DIR`). Exposes `EnumerateCs(string relativeFolder)` (skipping `bin/`, `obj/`, `Migrations/`), `Read(string relativePath)`, and `Parse(string path)` returning a `CSharpSyntaxTree` root.

## Step 4: The three tests

`Conventions/HandlerRegistrationTests.cs`
- Collect every `ClassDeclarationSyntax` under `Features/` whose name ends in `Handler`, skipping `abstract` classes and classes deriving from `DelegatingHandler`, `AuthorizationHandler<>` or `AuthenticationHandler<>`.
- Collect registered names from `AddScoped<...>` invocations in the syntax trees of every `.cs` file (registrations may live outside `Program.cs`). Walk `InvocationExpressionSyntax` nodes rather than matching text, so a registration that exists only in a comment does not count. For `AddScoped<IService, Impl>` the last type argument is the handler. Match on the type's simple name.
- If the API registers handlers by scanning (`Scan(`, `AddClasses(`, `AddMediatR(`, `RegisterServicesFromAssembly`, or a helper named `Add...HandlersFrom...`), skip the test with that reason, as the plugin's own check does. `AddValidatorsFromAssembly...` is not handler registration.
- Assert the difference is empty; the failure message lists the missing handlers and says "register-handler <Name>".

`Conventions/DomainEventDispatchTests.cs`
- Collect every class or record whose base list contains `IDomainEvent`.
- Read the outbox dispatcher (repo-relative `OUTBOX_DISPATCHER`; skip the test with a clear message if the project has none).
- Assert each name appears as `nameof(<Name>)`.

`Conventions/EndpointAuthorizationTests.cs`
- For every file under `Features/` containing `MapGet|MapPost|MapPut|MapPatch|MapDelete(`, assert it contains `RequireAuthorization` or a `// anonymous:` comment.
- If the API sets an authorization `FallbackPolicy`, mark the test as skipped with that reason instead.

Make each failure message list every offender, not just the first.

## Step 5: Run

```bash
dotnet test <SLN> -nologo -v q
```

- Green: report how many handlers, events and endpoints each test covered.
- Red: the tests are doing their job; the codebase has existing gaps. Quote the failure messages and point at `register-handler`, `add-domain-event` or `audit-authorization`. Do not change API code to make them pass.
- Build failure (package or framework mismatch): show the diagnostic and stop.

## Step 6: Report

Project path, packages, the three tests with result and coverage, and next steps: `write-handler-tests` for handler behaviour, `write-integration-tests` for endpoints through HTTP against a real database; a CI workflow running `dotnet build` and `dotnet test`. State: uncommitted.

## Rules

- Never modify API source from this skill.
- No database, Testcontainers or WebApplicationFactory here; those belong in behaviour tests.
- Never commit, push or stage.
