---
name: add-domain-event
description: "Scaffold a domain event end to end so it cannot be silently dropped: the IDomainEvent record, its IDomainEventHandler<T>, the Program.cs DI registration and the outbox dispatch branch, in one set of edits. Verifies with dotnet build. Use when the user mentions: add domain event, new domain event, raise event, IDomainEvent, outbox dispatcher, domain event handler, or the conventions hook reports an outbox FAIL."
argument-hint: "<Area>.<EventName> [Field:Type ...]"
---

# Add Domain Event

`Raise(new SomeEvent())` serialises the event into `OutboxMessages` inside `SaveChangesAsync`. The outbox dispatcher then matches the stored type with `nameof(SomeEvent)`. A missing branch means the event is stored and never dispatched, with no error. This skill writes the event, its handler, the DI line and the dispatch branch together.

Arguments: `$ARGUMENTS`, for example `Orders.OrderShippedDomainEvent OrderId:Guid ShippedOnUtc:DateTime`.

## Step 0: Locate the project

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `API_DIR`, `PROGRAM_CS`, `OUTBOX_DISPATCHER` and `SLN`. If `OUTBOX_DISPATCHER` is empty, Grep `<API_DIR>` for `nameof(` near `OutboxMessage`; if there is still none, stop and ask the user where events are dispatched.

## Step 1: Validate

- Empty: reply `Usage: add-domain-event <Area>.<EventName> [Field:Type ...]` and stop.
- `EventName` is PascalCase and ends in `DomainEvent` or `Event` (match the folder's existing convention).
- No type with that name already exists (Grep `class|record <EventName>`).

## Step 2: Choose the folder

Read where existing events live (Grep `: IDomainEvent` under `<API_DIR>`) and follow that convention: alongside the entity under `Domain/`, or alongside the feature under `Features/<Area>/`. Ask if it is ambiguous.

## Step 3: The event

```csharp
namespace <Namespace>;

public sealed record <EventName>(<Field> <Type>, ...) : IDomainEvent;
```

With no fields given, use `(Guid Id)` and say so in the report. Match the shape of existing events (record or class, primary constructor or properties), because the outbox serialises them with `System.Text.Json` and must be able to deserialise them.

## Step 4: The handler

```csharp
public sealed class <EventName>Handler(IApplicationDbContext dbContext)
    : IDomainEventHandler<<EventName>>
{
    public async Task HandleAsync(<EventName> domainEvent, CancellationToken cancellationToken)
    {
        // TODO: react to <EventName>.
        await Task.CompletedTask;
    }
}
```

Mirror an existing event handler's dependencies and logging.

## Step 5: DI

Add `builder.Services.AddScoped<<Namespace>.<EventName>Handler>();` to `<PROGRAM_CS>` per the `register-handler` skill, Step 4.

## Step 6: Dispatch branch

In `<OUTBOX_DISPATCHER>`, add the event namespace `using` if missing, then append a branch after the last existing one, copying the existing branches' exact shape. When there are no branches yet, copy the example in the dispatcher's own comment if it has one: the dispatcher `init-project` creates expects each branch to `return true`, and records a message no branch handled as an error. Otherwise use this shape:

```csharp
if (message.Type == nameof(<EventName>))
{
    var evt = JsonSerializer.Deserialize<<EventName>>(message.Payload)!;
    var handler = sp.GetRequiredService<<EventName>Handler>();
    await handler.HandleAsync(evt, ct);
}
```

## Step 7: Verify

`bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --changed-since HEAD`. The outbox and handler-DI rows must PASS.

## Step 8: Report

Links to the event, the handler, the DI line and the dispatch branch, plus the verify summary. Next steps: implement the handler; call `Raise(new <EventName>(...))` from the aggregate method that should trigger it; remember that `ExecuteUpdateAsync`/`ExecuteDeleteAsync` bypass `SaveChangesAsync` and would drop the event.

## Rules

- All four pieces in one turn, or none.
- The dispatch branch goes after the existing branches.
- Additive only: never modify existing events or handlers here.
- Never raise the event yourself; the caller decides where.
- Never commit, push or stage.
