---
paths:
  - "**/Migrations/*.cs"
---

# EF Core migrations

- **A committed migration is immutable.** Other databases may already have run it, and a hook blocks the edit. To change the schema, change the model and add a new migration.
- **Do not hand-edit the model snapshot.** It changes only through `dotnet ef migrations add` and `remove`.
- Create migrations with the `ef-add-migration` skill. It reviews the generated file for destructive operations (dropped or renamed tables and columns, type and nullability changes) before anything is applied.
- A new, uncommitted migration may be edited. `Down` must reverse `Up`.
- `dotnet ef migrations remove` and `dotnet ef database drop` are for local databases only, and need `ASPNETCORE_ENVIRONMENT` set to the project's local environment.
- Never run `dotnet ef database update` against a shared database. Produce a script with `dotnet ef migrations script --idempotent` and hand it to the user.
