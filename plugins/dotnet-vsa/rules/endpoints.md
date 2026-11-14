---
paths:
  - "**/Features/**/*Endpoint.cs"
  - "**/Features/**/*Endpoints.cs"
---

# Endpoints

- **Every endpoint has an authorization policy:** `.RequireAuthorization(AuthorizationPolicies.X)`, using a constant that sibling endpoints already use. Never invent a policy string. This is not needed only when the project sets a `FallbackPolicy`.
- **A public endpoint says why.** Put `// anonymous: <reason>` beside `.AllowAnonymous()`. Without the comment the conventions check reports it. Ask the user before making an endpoint anonymous.
- **Every endpoint has a rate-limit policy** when the project uses rate limiting without a global limiter: `.RequireRateLimiting(RateLimitPolicies.X)`, or `.DisableRateLimiting()` when that is intended.
- **Ownership:** a route that carries an owner id (`{userId}`, `{customerId}`, `{accountId}`) needs a check that the caller owns the resource, in the policy or the handler. Requiring authentication alone is an IDOR.
- Return `result.ToHttpResult()`. Keep `.Produces<>` metadata in step with what the handler really returns.
- User input needs an `AbstractValidator<T>` for its command or query.
- Copy the route prefix, tags and endpoint shape of sibling endpoints in the same feature.

The `add-endpoint` skill scaffolds a slice with all of this wired. `audit-authorization` lists every endpoint with its policies.
