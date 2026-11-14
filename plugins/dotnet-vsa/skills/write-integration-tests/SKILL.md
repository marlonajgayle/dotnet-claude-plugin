---
name: write-integration-tests
description: "Generate endpoint-level integration tests for one vertical slice: the real ASP.NET Core pipeline in memory (WebApplicationFactory) against SQL Server in a container (Testcontainers), covering 401 for anonymous callers, 403 for the wrong role, 400 for each validation rule, the success response and database state, 404 for another user's resource (IDOR) and for soft-deleted rows, and outbox dispatch of the events the slice raises. Creates the integration test project and fixture on first use. Needs Docker. Use when the user says: integration tests, endpoint tests, test the API end to end, test authorization, WebApplicationFactory, Testcontainers."
argument-hint: "<Domain>.<Slice> | path/to/Endpoint.cs"
---

# Write Integration Tests

Slice: `$ARGUMENTS`

`write-handler-tests` calls a handler directly with SQLite. These tests go through HTTP instead, so they also cover what sits around the handler: authentication, the authorization and rate-limit policies, the validation filter, model binding, `ToHttpResult()` status codes, JSON shape, and the real SQL Server behaviour of the EF Core configuration.

## Step 0: Locate

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `ROOT`, `SLN`, `API_PROJECT`, `API_DIR`, `PROGRAM_CS`, `DBCONTEXT`, `OUTBOX_DISPATCHER`, `AUTH_POLICIES` and `TEST_PROJECTS`.

- `docker info` must succeed. If Docker is not running, stop and say so: these tests cannot run without it.
- Find the slice under `<API_DIR>/Features/<Domain>/<Slice>/`. If it does not exist, stop with the path tried.

## Step 1: Read the slice

Read the endpoint, handler, command or query, validator, the entities it touches and their `{Entity}Errors`, the policy it requires (in `<AUTH_POLICIES>`: which roles or claims), and any events it raises. List what to test:

| Path | Request | Expected |
|---|---|---|
| Anonymous | no caller | 401, unless the endpoint is `// anonymous:` |
| Wrong role | a caller without the policy's role | 403, when the policy requires a role |
| Each validation rule | the smallest invalid body | 400 with that field in `errors` |
| Success | a valid request | the status and body the endpoint returns, plus the database state read back |
| Another user's resource | caller B on caller A's row | 404 (or 403 if the project answers that way) for owner-scoped routes |
| Soft-deleted row | a row after `MarkAsDeleted` | 404 for reads, not found for commands |
| Each `{Entity}Errors` path | the request that triggers it | the mapped status (`ToHttpResult`) and error code |
| Each raised event | a valid request, then `ProcessOutboxAsync()` | the outbox row processed with no error, and the handler's effect |

## Step 2: The test project (first time only)

If a project named `<Api>.IntegrationTests` exists, reuse it and its fixture; skip to Step 3.

Otherwise ask the user to approve the new project and packages, then create it beside the other test projects (`tests/` next to `src/`, or at the repo root):

```bash
dotnet new xunit -n <Api>.IntegrationTests -o <tests-dir>/<Api>.IntegrationTests
cd <tests-dir>/<Api>.IntegrationTests && rm UnitTest1.cs
v=$(bash "${CLAUDE_SKILL_DIR}/../../scripts/nuget-version.sh" Microsoft.AspNetCore.Mvc.Testing 10)
dotnet add package Microsoft.AspNetCore.Mvc.Testing --version "$v"
v=$(bash "${CLAUDE_SKILL_DIR}/../../scripts/nuget-version.sh" Testcontainers.MsSql)
dotnet add package Testcontainers.MsSql --version "$v"
dotnet add reference <relative path to API_PROJECT>
cd - && dotnet sln <SLN> add --include-references false <tests-dir>/<Api>.IntegrationTests/<Api>.IntegrationTests.csproj
```

`Mvc.Testing` must match the API's target framework major (10 for `net10.0`). Prefer the `nuget` MCP tools for both versions when they are connected.

Then copy the fixture into `Infrastructure/`, replacing `DvsaTemplate` with the API's root namespace:

- `${CLAUDE_SKILL_DIR}/templates/ApiFactory.cs`: starts SQL Server once per test run, applies migrations (or `EnsureCreated` when there are none), points the app at it, raises the rate limits, swaps in the test authentication scheme, and replaces the outbox timer with `ProcessOutboxAsync()` so tests decide when events dispatch.
- `${CLAUDE_SKILL_DIR}/templates/TestAuthHandler.cs`: the caller comes from the `X-Test-User` and `X-Test-Roles` headers; no header means anonymous.

The fixture is written for projects made by `init-project`. In another project, adapt it to what the code actually has, and say what you changed:

- The connection string key (`ConnectionStrings:Default`), the DbContext type, and the outbox processor type and method.
- The rate-limit settings, if the project reads them from somewhere else.
- `public partial class Program;` at the end of `<PROGRAM_CS>` if the tests cannot see `Program`. Ask before editing `Program.cs`.
- The xUnit version: the templates use xUnit v2 (`IAsyncLifetime` with `Task`). On xUnit v3 the lifetime methods return `ValueTask`.
- The container image: keep it the same as the one in `compose.yaml`.

## Step 3: The tests — `Features/<Domain>/<Slice>EndpointTests.cs`

One class per slice, in the collection that shares the container, tagged so the end-of-turn check can leave it out:

```csharp
[Collection(ApiCollection.Name)]
[Trait("Category", "Integration")]
public sealed class CreateNoteEndpointTests(ApiFactory api)
{
    [Fact]
    public async Task CreateNote_Anonymous_Returns401()
    {
        var response = await api.CreateAnonymousClient().PostAsJsonAsync("/notes", new { Title = "x" });
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetNote_OtherUsersNote_Returns404()
    {
        var id = await CreateNoteAsync(api.CreateClientAs(NewUser()), "Private");
        var response = await api.CreateClientAs(NewUser()).GetAsync($"/notes/{id}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private static string NewUser() => $"user-{Guid.NewGuid():N}";
}
```

- **Isolation:** the database is shared by every test in the run. Each test creates its own users (`NewUser()`) and rows, and never assumes a table is empty or counts all rows.
- **State:** assert the database with `api.WithDbContextAsync(...)`, a fresh context, using `AsNoTracking()`.
- **Events:** call `await api.ProcessOutboxAsync()`, then assert the `OutboxMessages` row (`ProcessedOnUtc` set, `Error` null) and the handler's effect.
- **Dates:** when a response carries a `DateTime`, assert `Kind == DateTimeKind.Utc`.
- Names follow `Slice_Scenario_Expectation`. Match the style of any existing tests.

## Step 4: Run

```bash
dotnet test <SLN> --filter "FullyQualifiedName~<Slice>EndpointTests" -nologo -v q
```

The first run pulls the SQL Server image, which can take minutes. A failing test is either a test bug (fix it) or an API bug: report API bugs with the failing assertion and the request, and do not change API code unless the user asks.

## Report

The tests added (name and the path each covers), the observed result, any project or fixture created and what was adapted, the paths left untested and why, and that these tests need Docker and are tagged `Category=Integration` (the Stop hook's `stopTests` leaves them out by default). State: uncommitted.

## Rules

- Never point the tests at a real or shared database; only the container.
- Never weaken the API's authorization, validation or rate limiting to make a test pass. Configure the fixture instead.
- Never commit, push or stage.
