---
name: register-handler
description: "Wire a vertical-slice handler into DI so it resolves at runtime. Inserts the AddScoped<HandlerType>() line in Program.cs in its feature block, and for a domain-event handler also adds the outbox dispatch branch. Verifies with dotnet build. Use when a handler exists but is not registered, when the conventions hook reports handler-di FAIL, or when the user reports HTTP2_PROTOCOL_ERROR, 'Unable to resolve service for type ...Handler', 200 OK with no body, missing handler DI, wire up handler, register handler."
argument-hint: "<HandlerTypeName | path/to/Handler.cs>"
---

# Register Handler

A handler missing its `AddScoped<HandlerType>()` line fails only at runtime: the browser sees `net::ERR_HTTP2_PROTOCOL_ERROR` or an empty 200, and the build gives no signal. This skill closes that gap. The `check-cs-conventions` hook points here when it finds an unregistered handler.

Handler to register: `$ARGUMENTS`

## Step 0: Locate the project

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"` and use `API_DIR`, `PROGRAM_CS`, `OUTBOX_DISPATCHER` and `SLN` from its output in every step below. If `API_PROJECT` is empty, stop and say no ASP.NET Core project was found.

## Step 1: Parse arguments

- `<HandlerTypeName>` such as `CreateOrderHandler`, or a path to the handler file.
- Empty: reply `Usage: register-handler <HandlerTypeName|path/to/Handler.cs>` and stop.

## Step 2: Locate the handler

1. If the argument is a path, read it. Otherwise Glob `<API_DIR>/**/<HandlerTypeName>.cs`, falling back to Grep for `class <HandlerTypeName>` under `<API_DIR>`.
2. Zero matches: stop and suggest `add-endpoint`. Several matches: list them and ask which one.
3. Capture the namespace (`namespace ...;`), the class name, and whether it implements `IDomainEventHandler<TEvent>` (record `TEvent`).
4. If the class is not `sealed` or does not use a primary constructor, say so, but proceed.

## Step 3: Already registered?

Grep `<PROGRAM_CS>` (and any `*ServiceCollectionExtensions*.cs` under `<API_DIR>`) for `AddScoped<([\w.]+\.)?<HandlerTypeName>>`. If found, report the line and stop.

## Step 4: Insert the registration

Read `<PROGRAM_CS>`. Handler registrations are grouped by feature folder, one blank line between groups, sorted alphabetically by feature. Add:

```csharp
builder.Services.AddScoped<<Namespace>.<HandlerTypeName>>();
```

- At the end of the block for the handler's feature folder.
- For a new feature, as a new block at its alphabetical position with a blank line on each side.
- Match the file's existing form exactly: fully qualified name or a `using` plus the short name, and the same indentation.
- Use `Edit` with enough surrounding lines to make `old_string` unique. Leave any comment above the block untouched.

## Step 5: Domain-event handler: add the dispatch branch

If Step 2 found `IDomainEventHandler<TEvent>` and `<OUTBOX_DISPATCHER>` is set:

1. Read it. If it already has `nameof(<TEvent>)`, skip this step.
2. Add the event's namespace `using` if it is missing.
3. Append a branch after the last existing one, mirroring the existing branches exactly. The usual shape is:

   ```csharp
   if (message.Type == nameof(<TEvent>))
   {
       var evt = JsonSerializer.Deserialize<<TEvent>>(message.Payload)!;
       var handler = sp.GetRequiredService<<HandlerTypeName>>();
       await handler.HandleAsync(evt, ct);
   }
   ```

## Step 6: Build

`dotnet build <SLN> -nologo -v q -clp:ErrorsOnly`. If it fails, show the diagnostics with file:line. The usual cause is a namespace typo in the inserted line: re-read the handler and fix the line. Never delete code or roll back silently to make it compile.

## Step 7: Report

```markdown
## Registered: `<HandlerTypeName>`
- DI: [Program.cs:LN](<PROGRAM_CS>#LLN)
- Outbox: [<dispatcher>:LN](...) — dispatch branch for `<TEvent>`   (omit when not an event handler)
- Build: clean
State: uncommitted.
```

## Rules

- Handlers are always `AddScoped`, never `AddSingleton` or `AddTransient`: they take a scoped DbContext.
- Never register the same handler twice.
- Never edit the handler's own source in this skill.
- Never commit, push or stage.
