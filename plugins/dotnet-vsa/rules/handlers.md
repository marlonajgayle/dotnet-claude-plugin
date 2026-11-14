---
paths:
  - "**/Features/**/*Handler.cs"
---

# Handlers

Applies to command, query and domain-event handlers in a feature slice.

- **Register it.** A handler needs `builder.Services.AddScoped<TheHandler>();` in `Program.cs`, in its feature's block. A missing registration builds clean and fails at runtime (`Unable to resolve service`, `HTTP2_PROTOCOL_ERROR`). Use `AddScoped`, not `AddTransient` or `AddSingleton`: handlers take a scoped DbContext. Skip this only if the project registers handlers by assembly scanning. The `register-handler` skill adds the line.
- **Return `Result` or `Result<T>`.** Expected failures return an error from the entity's `{Entity}Errors` class. Do not throw for a not-found, a conflict or a validation failure.
- **Reads:** `.AsNoTracking()`, filter `!x.IsDeleted` (unless the project has a global query filter for it), and project to a DTO with `Select` instead of loading entities.
- **Writes:** call `SetCreatedAuditInfo` or `SetModifiedAuditInfo`. Delete with `MarkAsDeleted()`, never `Remove`.
- **No `ExecuteUpdateAsync` or `ExecuteDeleteAsync` on an aggregate that raises domain events.** They bypass `SaveChangesAsync`, so the events are never written to the outbox.
- **`DateTime` in a projection:** wrap it in `DateTime.SpecifyKind(x, DateTimeKind.Utc)` unless the project has a model-wide UTC converter. SQL returns `Kind=Unspecified`, which serialises without a `Z`.
- Inject `IApplicationDbContext`, not the concrete DbContext. Accept a `CancellationToken` and pass it to every async call.
- Take the caller's own id from the authenticated user, never from the route or body.
- Shape: `public sealed class`, primary-constructor DI, file-scoped namespace.
