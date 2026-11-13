---
name: implement-feature
description: "Implement a feature from a spec written by the plan skill (default .ai/specs/<slug>.md). Creates a feature branch, walks the spec's Implementation Steps in order, applies the vertical-slice conventions that fail silently (handler DI, outbox dispatch, Result pattern, AsNoTracking + !IsDeleted, soft delete, auditing, authorization), then runs verify-conventions. Use when the user says: implement this feature, build the spec, execute the plan, implement-feature <slug>."
argument-hint: "<slug | path/to/spec.md>"
---

# Implement Feature

Spec to implement: `$ARGUMENTS`

## Step 0: Locate the project

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `SPECS_DIR`, `API_DIR`, `PROGRAM_CS`, `OUTBOX_DISPATCHER`, `SLN` and `TEST_PROJECTS`.

## Step 1: Resolve the spec

- Empty: reply `Usage: implement-feature <slug-or-path>` and stop.
- A value ending in `.md` or containing `/` is a path; anything else is `<SPECS_DIR>/<slug>.md`.
- If the file does not exist, stop and give the exact path tried. Never pick a different spec.

## Step 2: Parse it

Extract Requirements, Implementation Steps (each `NEW` or `MODIFY` with a path), Files Changed Summary, Existing Code to Reuse, and Verification. Make one todo per Implementation Step plus a final verification todo. If there are no Implementation Steps, stop and say so; do not improvise.

## Step 3: Branch

1. `git status --short`. If the tree is dirty, ask whether to continue.
2. `git checkout -b feature/<slug>`, or `git checkout feature/<slug>` if it exists. (Bug fixes use `bugfix/`, urgent production fixes `hotfix/`.)

## Step 4: Implement, step by step

For each step: mark it in progress, apply it as written, reuse what "Existing Code to Reuse" names, mark it complete immediately. Prefer the scaffolding skills where they fit: `add-entity`, `add-endpoint`, `add-domain-event`, `ef-add-migration`.

If a step conflicts with an existing file's evident purpose (for example a MODIFY that would rewrite `Program.cs` wholesale), stop and ask.

## Step 5: Conventions that fail silently

The `check-cs-conventions` hook reports these after each edit; act on its findings as you go.

- Handlers: `sealed class`, primary-constructor DI on `IApplicationDbContext`; commands and queries are `sealed record`.
- Every new handler has `AddScoped<>()` in `<PROGRAM_CS>`.
- Every new `IDomainEvent` has a `nameof(...)` branch in `<OUTBOX_DISPATCHER>`.
- Handlers return `Result`/`Result<T>`; endpoints return `result.ToHttpResult()`; expected failures use `{Entity}Errors`, not exceptions.
- Reads: `AsNoTracking()` and `!x.IsDeleted`. Deletes: `MarkAsDeleted()`. Writes: `SetCreatedAuditInfo` / `SetModifiedAuditInfo`.
- Every endpoint: `.RequireAuthorization(AuthorizationPolicies.X)` (or `// anonymous: <reason>` when the spec says anonymous) and `.RequireRateLimiting(...)`. The caller's own id comes from the authenticated user, never the route or body.
- Outgoing `DateTime` values are stamped `DateTimeKind.Utc`.
- No `= new()` on navigation properties; no `ExecuteUpdate`/`ExecuteDelete` on aggregates that raise events.

## Step 6: Verify

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --changed-since main --tests
```

Fix every FAIL and rerun until it passes. Do not delete code to make it build. If an error survives a reasonable attempt, stop and report it with file:line.

Then work through the spec's runtime Verification steps. For anything that needs the running app, use `run-api` and `smoke-health` (or start it with `run_in_background`); never run `dotnet run` in the foreground. Anything you could not observe is reported as pending, not as passed.

## Step 7: Report

- Branch: `feature/<slug>`
- Files changed: NEW and MODIFY lists
- Verify: the summary line from verify-conventions
- Tests: the result, or "no test project" (never "tests passed" when none ran)
- Runtime: what was observed, and what is still pending
- State: uncommitted; the user reviews and commits.
