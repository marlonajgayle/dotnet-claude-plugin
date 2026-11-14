---
paths:
  - "**/*Event.cs"
  - "**/*Events.cs"
  - "**/*EventHandler.cs"
  - "**/Outbox/**/*.cs"
---

# Domain events and the outbox

`Raise(new SomeEvent(...))` serialises the event into the outbox inside `SaveChangesAsync`. The outbox dispatcher then matches the stored type by name with `nameof(SomeEvent)`.

- **A new event needs four things together:** the `IDomainEvent` type, its handler, the handler's `AddScoped<>` registration in `Program.cs`, and a `nameof(TheEvent)` branch in the outbox dispatcher. Without the branch the event is stored and never dispatched, with no error. The `add-domain-event` skill writes all four.
- **Renaming an event** means updating its dispatch branch too. Rows already in the outbox carry the old name, so ask the user before renaming an event that has been deployed.
- Match the shape of existing events (record or class, primary constructor or properties). The outbox uses `System.Text.Json` and must be able to deserialise them, so keep payloads to simple, serialisable values.
- In the dispatcher, add a branch after the existing ones and copy their exact shape. Do not reorder or rewrite existing branches.
- `ExecuteUpdateAsync` and `ExecuteDeleteAsync` bypass `SaveChangesAsync`, so an aggregate changed that way raises nothing.
