---
name: plan
description: "Write a feature specification for a vertical-slice .NET API. Explores the codebase first (entities, slices, endpoints, policies, events, reusable helpers) and writes a complete spec to the specs folder (default .ai/specs/<slug>.md) listing affected slices, entities, migrations, events, policies and verification steps. Does not implement. Use when the user wants to plan, spec or design a feature or change: plan a feature, write a spec, design this change, scope this work, requirement doc, feature spec."
argument-hint: "<feature or change request>"
---

# Plan

Feature or change request: `$ARGUMENTS`

The output is a spec that `implement-feature` can execute step by step. Do not write any code.

## Step 0: Locate the project

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `API_DIR`, `PROGRAM_CS`, `OUTBOX_DISPATCHER`, `DBCONTEXT`, `AUTH_POLICIES`, `MIGRATIONS_DIR`, `SPECS_DIR`, `SLN` and `HEALTH_URL`. If `BACKLOG_FILE` exists and the request names a backlog item (`F2`, `E4`), read that item first.

## Step 1: Explore

Find what already exists for this request before proposing anything new:

- Entities and their base types under `Domain/`; their `IEntityTypeConfiguration<T>`.
- Sibling slices under `Features/<Domain>/` that the change should mirror.
- Policies in `<AUTH_POLICIES>`, rate-limit policies, and how the caller's identity is resolved.
- Domain events and the outbox dispatcher, if the change raises or reacts to events.
- Shared helpers (static rule classes, lookups) that must be reused rather than duplicated.
- The project's CLAUDE.md and any `.claude/rules/*.md` that apply to the touched paths.

## Step 2: Write `<SPECS_DIR>/<slug>.md`

Slug: kebab-case from the request. Fill every section.

```markdown
# <Title>

## Context
Why the change is needed, the current state of the relevant code (with paths), and the intended outcome.

## Requirements
1. ...

## Affected surface
| Kind | Item | Change |
|---|---|---|
| Slice | Features/<Domain>/<Name>/ | NEW / MODIFY |
| Entity | Domain/.../<Entity>.cs | NEW / MODIFY |
| Migration | <Name> | NEW (via ef-add-migration) |
| Domain event | <EventName> | NEW (via add-domain-event) |
| Endpoint policy | <METHOD> <route> | AuthorizationPolicies.X, RateLimitPolicies.Y |

## Implementation Steps
## Step N: <short description>
**[NEW|MODIFY]:** `path/to/file.cs`
- What to do, specifically.
(Use tables for mappings such as endpoint-to-policy or field-to-type.)

## Files Changed Summary
| File | Type | Description |
|---|---|---|

## Existing Code to Reuse
- `Type.Method()` in `path` — what it does and why to reuse it.

## Verification
1. `bash <plugin>/scripts/verify-conventions.sh` (build, DI, outbox, authorization).
2. Runtime: the requests to make against <HEALTH_URL base>, with expected status codes and bodies.
3. Tests to write (write-handler-tests), or "no test project" if none exists.
```

The spec must account for the conventions that otherwise fail silently: every new handler gets an `AddScoped<>` step; every new event gets a dispatch-branch step; every endpoint names its policy (or "anonymous: <reason>") and rate-limit policy; reads use `AsNoTracking()` + `!IsDeleted`; deletes are `MarkAsDeleted()`; writes call the audit setters; outgoing `DateTime` values are stamped UTC; a model change gets a migration step.

## Step 3: Report

Print the spec path, the number of implementation steps, and any open question that needs the user's decision before implementation.
