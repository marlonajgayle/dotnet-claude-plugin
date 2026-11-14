---
paths:
  - "**/Features/**/*Dto.cs"
  - "**/Features/**/*Response.cs"
  - "**/Features/**/*Query.cs"
---

# DTOs and responses

- **A `DateTime` that reaches a client must be UTC.** Values read from SQL have `Kind=Unspecified` and serialise without a `Z`, so clients read them as local time. Unless the project has a model-wide UTC converter, the projection that fills this type wraps each one: `DateTime.SpecifyKind(x, DateTimeKind.Utc)`. The `fix-utc-kinds` skill finds and fixes these.
- Commands, queries and DTOs are `public sealed record` types in file-scoped namespaces.
- Return a DTO, never an entity. Leave out fields the caller should not see: password hashes, tokens, internal flags, other users' data.
- Changing or removing a field on a published response is a breaking API change. The `api-contract-diff` skill shows what changed against `main`.
