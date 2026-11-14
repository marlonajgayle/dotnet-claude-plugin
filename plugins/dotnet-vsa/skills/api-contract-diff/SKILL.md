---
name: api-contract-diff
description: "Compare the API's OpenAPI contract on this branch against the base branch and flag breaking changes for separate clients (mobile, SPA): removed or renamed routes and operations, removed or renamed properties, newly required request fields, changed types, and changed or removed status codes. Uses the build-time OpenAPI document when the project generates one, otherwise runs each version and fetches /openapi/v1.json. Use before merging API changes, or when the user says: contract diff, breaking changes, did I break the client, api diff, openapi diff."
argument-hint: "[base-branch]"
---

# API Contract Diff

Clients with no shared types (a mobile app, a separate SPA) break at runtime when a DTO property is renamed. This skill finds those changes before merge. Base branch: `$ARGUMENTS`, default `BASE_BRANCH` from discovery.

## Step 0: Locate

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `ROOT`, `API_PROJECT`, `API_DIR`, `HEALTH_URL`, `BASE_BRANCH` and `REVIEWS_DIR`. Scratch files (the two documents and the base worktree) go in a temporary directory: `work=$(mktemp -d)`. The report goes to `<REVIEWS_DIR>/<slug>/api-contract.md`, beside the branch's other reviews (the slug is the branch name minus `feature/`, `bugfix/` or `hotfix/`; on another branch use `<REVIEWS_DIR>/_audits/api-contract-<branch>.md`).

## Step 1: Get both documents

Prefer the build-time document, which needs no running app:

- If `<API_PROJECT>` references `Microsoft.Extensions.ApiDescription.Server`, `dotnet build` writes the document (usually `obj/<Project>.json`, or wherever `OpenApiDocumentsDirectory` points).
- For the base: `git worktree add "$work/base" <base>` and build there, then `git worktree remove "$work/base"` when done. Never check out the base in the user's working tree.

Otherwise, run each version: start it with `run-api` (from the worktree for the base, on a different port via `--urls`), fetch `/openapi/v1.json` (or `/swagger/v1/swagger.json`) into `head.json` / `base.json`, then stop both. If neither works, say so and stop; do not compare against guesses.

Do not add packages to the project to make this work. If the build-time generator is missing, mention it as an option in the report.

## Step 2: Normalise

With `jq`: resolve `$ref`s you need, sort keys, and list for each operation (`METHOD path`): request body schema properties with types and `required`; parameters with `in`, name, type and `required`; response status codes with schema properties and types.

## Step 3: Classify

| Change | Severity |
|---|---|
| Operation removed, or path or method changed | **Breaking** |
| Response property removed or renamed (a removal and an addition with the same type in one schema count as a rename) | **Breaking** |
| Property type changed (string→number, object→array, a `date-time` format change) | **Breaking** |
| Request property or parameter newly required | **Breaking** |
| Success status code changed (200→201), or an error code the client handles removed | **Breaking** |
| Property became nullable in a response | **Risky** (clients may not null-check) |
| Enum value removed | **Breaking**; added: **Risky** |
| New operation, new optional request field, new response property | **Additive** |

## Step 4: Report

```markdown
## API contract: <branch> vs <base>
Source: build-time document | runtime /openapi/v1.json
Breaking N · Risky N · Additive N

### Breaking
- `GET /api/v1/orders/{id}` 200 response: `placedOn` renamed to `placedAt` (string, date-time).
  Clients reading `placedOn` get undefined. Keep the old name, or version the route.
### Risky
### Additive
```

For each breaking change, suggest the non-breaking alternative: keep the old property alongside the new one for a release, add a new versioned route, or make the new request field optional with a default. Save the report to the path from Step 0, with a header line naming the branch, `git rev-parse HEAD` and the base, and print the summary. The approver reads it when endpoints or DTOs changed; it is not one of the three review reports whose commit gates a merge.
