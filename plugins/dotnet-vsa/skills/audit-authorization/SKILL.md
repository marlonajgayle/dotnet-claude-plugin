---
name: audit-authorization
description: "List every endpoint of a minimal-API .NET project with its HTTP method, route, authorization policy, rate-limit policy, and whether a route or body parameter names an owner (userId, customerId, accountId...). Flags endpoints with no policy, anonymous endpoints without a justification, and IDOR candidates: owner-scoped routes protected only by 'authenticated' with no ownership check in the handler. Use before a review or when the user says: audit authorization, endpoint policies, who can call what, IDOR check, auth table, unsecured endpoints."
argument-hint: "[changed]"
---

# Audit Authorization

Read-only. Produces the route table that IDOR and missing-policy findings come from. `changed` limits the table to endpoints changed against `BASE_REF` from `scripts/discover.sh`; the default is every endpoint.

## Step 0: Locate

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `API_DIR`, `PROGRAM_CS`, `AUTH_POLICIES` and `RATE_LIMIT_POLICIES`. Read `AUTH_POLICIES` and the `AddAuthorization`/`AddAuthorizationBuilder` registration so you know what each policy actually requires (roles, claims, or only an authenticated user). Note whether a `FallbackPolicy` exists and how route groups are built (`MapGroup(...)` with group-level `RequireAuthorization`).

## Step 1: Mechanical pass

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --no-build
```

The endpoint-auth and rate-limit rows give the files with no policy, anonymous endpoints without a `// anonymous:` justification, and endpoints with no rate limit.

## Step 2: Build the table

For every file with `MapGet|MapPost|MapPut|MapPatch|MapDelete(` under `<API_DIR>` (including `Program.cs`): the method; the full route including the group prefix; the policy or `anonymous`; the rate-limit policy; **owner parameters**, meaning a route parameter or request-body field naming a principal-owned resource (`userId`, `customerId`, `accountId`, `memberId`, `ownerId`, `profileId`, or `{id}` on a per-user resource); and the handler class.

## Step 3: Judge each row

- **No policy and no justification**: High (Critical when it returns or changes personal data).
- **Anonymous with justification**: list it. Confirm the reason holds (login, register, password reset, public catalogue, health). Anonymous endpoints should be rate-limited; flag Medium if not.
- **IDOR candidate**: an owner parameter, a policy that only requires authentication (no role or resource requirement), and a handler that never compares the parameter with the caller's id (Grep the handler for the current-user accessor, `ClaimTypes.NameIdentifier`, `User.FindFirst`, or an ownership-check helper). That is **Critical**: any signed-in user can read or change another user's data by swapping the id. Fix: resolve the caller from the token on a "me" route, or check ownership in the handler and return 404 (not 403) on mismatch, or restrict the route to staff policies.
- **Debug endpoints** mapped in `Program.cs` (`/test-*`, `/debug`, `/send-email`) without an environment guard: High.
- **Admin-only actions** (delete, role change, bulk export) under a non-admin policy: High.

## Step 4: Report

```markdown
## Authorization audit — <N> endpoints
| Method | Route | Policy | Rate limit | Owner params | Handler | Verdict |
|---|---|---|---|---|---|---|
| GET | /api/v1/customers/{customerId}/orders | Authenticated | IpFixedWindow | customerId (route) | GetOrdersForCustomerHandler | **IDOR (Critical)** |
| POST | /api/v1/auth/login | anonymous: login | IpFixedWindow | — | LoginHandler | ok |

### Findings
- **[Critical]** IDOR: `GET /customers/{customerId}/orders` — [Endpoint.cs:LN](...) — handler never compares customerId with the caller. Fix: …
```

Print the summary in chat, with the full table if it has under 40 rows; otherwise save it to `.claude/audit-authorization.md` and print the findings only.
