---
name: write-handler-tests
description: "Generate xUnit tests for one vertical-slice handler: a success case asserting the Result value, one test per {Entity}Errors failure the handler can return, a soft-deleted-row case, and for commands the audit and outbox side effects. Uses a SQLite in-memory ApplicationDbContext so relational behaviour (constraints, filtered indexes) is close to SQL Server. Use when the user says: write tests for this handler, test this slice, add handler tests, cover the booking rules."
argument-hint: "<HandlerTypeName | path/to/Handler.cs>"
---

# Write Handler Tests

Handler: `$ARGUMENTS`

## Step 0: Locate

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `API_DIR`, `DBCONTEXT`, `TEST_PROJECTS` and `SLN`. If `TEST_PROJECTS` is empty, stop: "No test project yet; run bootstrap-tests first."

## Step 1: Read the slice

Read the handler, its command or query, its validator, the entities it touches, their `{Entity}Errors`, and `DBCONTEXT`. List every path through `HandleAsync`: each `return Result...Failure(...)` with the `Errors` factory it uses, the success return, and every side effect (rows added or changed, `MarkAsDeleted()`, audit setters, `Raise(...)`).

Read any existing tests in the test project and match their style (naming, builders, assertion library).

## Step 2: Test infrastructure (once per test project)

If the test project has no database fixture yet, add `Infrastructure/SqliteDbContextFactory.cs`:

- An open `SqliteConnection("DataSource=:memory:")` kept alive for the test's lifetime.
- `new ApplicationDbContext(options, ...)` built with `UseSqlite(connection)`, passing simple fakes for the constructor's other dependencies (current user, clock, encryption). Read the constructor; never mock the DbContext itself.
- `EnsureCreated()`. SQL Server-only configuration (`IsClustered`, filters using `[IsDeleted] = 0`, `HasDefaultValueSql("getutcdate()")`) can fail on SQLite. Prefer guarding it in the configuration with `Database.IsSqlServer()` rather than weakening the test; if that is not acceptable, fall back to the EF in-memory provider and note what it cannot check (constraints, transactions).

Add `Microsoft.EntityFrameworkCore.Sqlite` to the test project if it is missing; it is a test-only dependency, so mention it in the report.

## Step 3: Tests — `tests/.../Features/<Domain>/<Name>HandlerTests.cs`

One class per handler, `Method_Scenario_Expectation` names, arrange through the domain factory methods (not by setting private state):

- **Success**: seed the minimum data, call `HandleAsync`, assert `IsSuccess` and the important fields of the value. For queries, assert `DateTime` values come back with `Kind == DateTimeKind.Utc` when the DTO carries dates.
- **Each failure**: one test per `{Entity}Errors` path, asserting the specific error code and `ErrorType`, not just `IsFailure`.
- **Soft-deleted rows**: seed a matching row, `MarkAsDeleted()`, save; a query must not return it, and a command must treat it as not found.
- **Commands**: assert the persisted state with a fresh context (not the tracked instance), the audit fields being set, and for aggregates that raise events, the expected `OutboxMessages` row with `Type == nameof(<Event>)` after `SaveChangesAsync`.
- **Validators**: if the slice has one, a few `TestValidate` cases for the rules that guard business invariants.
- Pass `CancellationToken.None` (or `TestContext.Current.CancellationToken` on xUnit v3).

## Step 4: Run

`dotnet test <SLN> --filter "FullyQualifiedName~<Name>HandlerTests" -nologo -v q`. A failing test is either a test bug (fix it) or a handler bug: report handler bugs with the failing assertion and do not change the handler unless the user asks.

## Report

The tests added (name and the path each covers), the pass/fail result as observed, any infrastructure added, and the handler paths left untested and why.
