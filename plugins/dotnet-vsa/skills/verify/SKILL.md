---
name: verify
description: "Run the vertical-slice verification checklist and print a pass/fail table: build, handler DI registration, outbox dispatch branches, endpoint authorization, rate limiting, AsNoTracking + !IsDeleted, phantom navigation properties, UTC DateTime kinds, <None Include> on .cs files, formatting and tests. Use before reporting work as done, or when the user says: verify, run the checklist, check conventions, is this ready, did I miss anything."
argument-hint: "[changed | full] [--format] [--tests] [--no-build]"
---

# Verify

Runs `scripts/verify-conventions.sh`, the same checks the Stop hook runs at the end of a turn, so you can see the result before it blocks you.

Arguments: `$ARGUMENTS`

- `changed` (default when on a feature branch): only files changed against the base branch (`BASE_REF` from `scripts/discover.sh`), plus untracked ones.
- `full` (default on the base branch): the whole API project.
- `--format`: also `dotnet format --verify-no-changes`. `--tests`: also `dotnet test`. `--no-build`: skip the build.

## Step 1: Run

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" [--changed-since <BASE_REF>] [--format] [--tests] [--no-build]
```

For `changed`, get `BASE_REF` from `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"` and pass `--changed-since <BASE_REF>`. Exit codes: 0 means no FAIL; 1 means at least one FAIL; 3 means no ASP.NET Core project was found (say so and stop).

## Step 2: Show the result

Print the table and findings as the script emits them. Then, for each FAIL, name the fix:

| Check | Fix |
|---|---|
| handler-di | `register-handler <Name>` |
| outbox | add the `nameof(<Event>)` branch (`add-domain-event` shows the shape) |
| endpoint-auth | `.RequireAuthorization(AuthorizationPolicies.X)`, or `// anonymous: <reason>` if it is public by design |
| csproj | delete the `<None Include>` line, or use `<Compile Remove>` if exclusion was intended |
| build / tests | the diagnostics shown |

WARN items are heuristics. Read the code before acting on one, and say so when one is a false positive (for example a `DateTime` that comes from `DateTime.UtcNow`, or an entity that is not soft-deletable).

## Step 3: Offer to fix

If anything FAILs, offer to fix it. Do not fix it unasked if the user only asked for a check.

## Honesty

- The summary line is the claim you may make. "Build clean" is not "the app runs": use `run-api` and `smoke-health` for that.
- If the Tests row says NONE, report "no test project" and never say tests passed.
