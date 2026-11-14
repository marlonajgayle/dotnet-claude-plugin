---
name: smoke-health
description: "Read-only runtime check of a running ASP.NET Core API: /health status and timing, the OpenAPI document (path and tag counts), and whether the routes this branch touched appear in it. Reports observed results only. Use after run-api to confirm a change is live rather than just built: smoke test, is it up, verify the api, did my change land, check health."
---

# Smoke Health

Gives a real answer to "is it working?" instead of "the build was clean". It never starts or stops processes and never writes data.

## Step 0: Locate

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `HEALTH_URL` and `API_DIR`. Base URL = `HEALTH_URL` minus its path.

## Step 1: Pre-flight

`curl -ks -o /dev/null -w '%{http_code}' <HEALTH_URL>`. If it does not return a status, stop: "The API is not reachable at <url>. Run run-api first." Use `-k` only against `localhost`.

## Step 2: Health

`curl -ks -w '\n%{http_code} %{time_total}' <HEALTH_URL>`.

- Not 200: Critical, with the first 200 characters of the body.
- A JSON body whose status is not `Healthy`: High, naming the failing check.
- Slower than 2 s: Medium.

## Step 3: OpenAPI

Try `/openapi/v1.json`, then `/swagger/v1/swagger.json`, then any path `MapOpenApi(...)` sets in the source. With `jq`: count `.paths`, count operations, and group operations by tag.

Then compare with the branch: from `git diff --name-only <BASE_REF>...HEAD` (plus untracked files), read each changed `*Endpoint.cs` and extract its route template and method. Each one should appear in `.paths` (allow for a version prefix such as `/api/v1`). A missing route is High, and the likely causes are: the endpoint class does not implement `IEndpoint`, the file is excluded from compilation, or the app was started before the change (restart with `run-api stop` then `run-api`).

## Step 4: Report

```markdown
## Smoke — <base url>
| Check | Result | Time | Notes |
|---|---|---|---|
| /health | 200 Healthy | 42 ms | |
| OpenAPI | 200 | 110 ms | 73 paths, 10 tags |
| Branch routes | 3 of 3 present | | POST /api/v1/orders/{id}/refund … |
### Findings
- **[High]** … (request, status and body excerpt)
```

Print `_No findings._` when everything passed. Say plainly that this checks presence and health, not behaviour: calling an endpoint with real input is a separate step, and a missing handler registration only shows when its endpoint is called.
