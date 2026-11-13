---
name: ef-add-migration
description: "Create an EF Core migration and review it before it touches a database. Generates with dotnet ef migrations add, then checks the generated Up/Down for destructive operations (DropColumn, DropTable, narrowing AlterColumn, RenameColumn, raw DELETE/TRUNCATE), irreversible Down, soft-delete columns and filtered indexes, cascade deletes, clustered Guid keys and TimeSpan columns. Applies to the local database only when asked. Use when the model changes: add migration, new migration, ef migration, schema change, dotnet ef migrations add."
argument-hint: "<PascalCaseName> [apply]"
---

# EF Add Migration

Arguments: `$ARGUMENTS`

The point of this skill is the review step. Never skip it.

## Step 0: Locate the project

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`. Use `API_PROJECT`, `API_DIR`, `MIGRATIONS_DIR`, `SLN` and `LOCAL_ENVIRONMENT`.

## Step 1: Validate the name

- Empty: reply `Usage: ef-add-migration <PascalCaseName> [apply]` and stop.
- Must match `^[A-Z][A-Za-z0-9]{5,}$` and start with an action (`Add`, `Create`, `Remove`, `Drop`, `Rename`, `Alter`, `Backfill`, `Seed`, `Index`). Reject `Update1`, `Fix`, `Migration` and ask for a better name.
- A migration with that name must not already exist in `MIGRATIONS_DIR`.

## Step 2: Pre-flight (in parallel)

- `git status --porcelain`: if unrelated changes are pending, ask before continuing (the snapshot change mixes badly with them).
- `dotnet ef --version`: if missing, suggest `dotnet tool install --global dotnet-ef` and stop. Do not install it yourself.
- `ls <MIGRATIONS_DIR>`: note the latest migration for the summary.

## Step 3: Build

`dotnet build <SLN> -nologo -v q -clp:ErrorsOnly`. On failure, show the diagnostics and stop. Do not pass `--no-build` to `dotnet ef` unless the user asks.

## Step 4: Generate

```bash
dotnet ef migrations add <Name> --project <API_PROJECT> --output-dir <MIGRATIONS_DIR relative to API_DIR>
```

EF's "may result in the loss of data" message is not a failure; Step 5 covers it. Capture the new `<timestamp>_<Name>.cs` path. The `guard-migrations` hook allows the snapshot to change while this new migration is uncommitted.

## Step 5: Review `Up` and `Down`

Read the new migration. Severity: **Critical** data loss is certain or `Down` corrupts state; **High** likely data loss or a convention break EF will not catch; **Medium** recoverable but worth knowing; **Low** nit; **Info** what shipped.

Destructive operations in `Up`:
- `DropColumn`: High. Recommend deprecate first (make it nullable, stop writing), drop in a later release.
- `DropTable`: High (Critical if the table holds production data).
- `RenameColumn` / `RenameTable`: High. Confirm the rename was intended, not a drop-and-add.
- `AlterColumn` that narrows (shorter `maxLength`, smaller precision, nullable to non-nullable without a default): High.
- `DropForeignKey` / `DropIndex` / `DropPrimaryKey`: Medium, or Low when recreated in the same migration.
- `migrationBuilder.Sql(...)` containing `DELETE`, `TRUNCATE` or `DROP`: Critical unless clearly scoped. Quote the first 200 characters. Seed data containing emails, user ids or anything secret-shaped: Critical (show REDACTED).

Conventions:
- New `CreateTable` with a `Guid` key: the entity configuration should use `HasKey(...).IsClustered(false)` (High if the project does this elsewhere and this one does not).
- Soft-deletable entity without `IsDeleted` (and `DeletedUtc`) columns: Medium. Auditable entity without its audit columns: Medium.
- New index on a soft-deletable table without `filter: "[IsDeleted] = 0"`: Low.
- `onDelete: ReferentialAction.Cascade`: Medium where the project's model is soft delete (`NoAction`).
- `TimeSpan` mapped to SQL `time`: Medium. It overflows at 24 hours and fails the whole `SaveChanges`.

`Down`:
- Empty, or throws: High. Genuinely irreversible backfills: Medium with a comment explaining why.
- Each destructive `Up` operation must be meaningfully reversed.

## Step 6: Summary

```markdown
## Migration generated: `<Name>`
**File**: [<timestamp>_<Name>.cs](...) · **Snapshot updated**: [<Context>ModelSnapshot.cs](...) · **Operations**: N
### Findings
- **[HIGH]** … — [file:LN](...)
- **[INFO]** Adds table `X` (N columns, N indexes)
### Next
- Preview SQL: `dotnet ef migrations script --idempotent --project <API_PROJECT> --from <previous> --to <Name>`
- Apply locally: `ef-add-migration <Name> apply`
- Discard: `ASPNETCORE_ENVIRONMENT=<LOCAL_ENVIRONMENT> dotnet ef migrations remove --project <API_PROJECT>` (only while it exists nowhere but this machine)
```

With nothing above Info, print `_No risks detected._` under Findings.

## Step 7: Apply (only with `apply`)

1. With any Critical or High finding, ask "Found N High/Critical risks. Apply anyway?" and wait.
2. Run `dotnet ef dbcontext info --project <API_PROJECT>` and confirm the target is local. If not, stop: never migrate a shared database from an agent session (the `guard-bash` hook blocks a non-local `--connection` too).
3. Save a preview: `dotnet ef migrations script --idempotent --from <previous> --to <Name> --output .claude/ef-migrations/<timestamp>_<Name>.sql`.
4. `dotnet ef database update <Name> --project <API_PROJECT>` and report the result verbatim.

## Rules

- Never edit a committed migration (the `guard-migrations` hook blocks it); add a new one.
- Never edit the generated migration in this skill; recommend changes and let the user decide.
- Never delete the model snapshot to "reset"; use `migrations remove`.
- Never invent the `--from` migration name; read it from the folder.
- Never commit, push or stage.
