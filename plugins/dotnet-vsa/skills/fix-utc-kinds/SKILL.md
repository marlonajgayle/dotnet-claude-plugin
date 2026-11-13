---
name: fix-utc-kinds
description: "Find every DTO that carries a DateTime read from the database without DateTimeKind.Utc (SQL returns Kind=Unspecified, which serialises without a Z, so clients show it shifted by their UTC offset), then either patch each projection with DateTime.SpecifyKind or add one model-wide EF value converter and remove the per-projection calls. Checks first that writes are UTC. Use when the user says: times are off by N hours, missing Z on dates, DateTime kind, UTC dates, fix-utc-kinds."
argument-hint: "[report | projections | converter]"
---

# Fix UTC Kinds

Mode: `$ARGUMENTS`. `report` (the default) lists the gap and changes nothing. `projections` patches each projection. `converter` adds the model-wide converter. Ask before patching if the user only said `fix-utc-kinds`.

## Step 0: Locate

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `API_DIR` and `DBCONTEXT`.

## Step 1: Enumerate the gap

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --no-build
```

The utc-kinds rows list each DTO record with a `DateTime` member and whether its slice stamps UTC. That is a folder-level heuristic, so confirm each one by reading the handler's `Select`:

- Stamped: `DateTime.SpecifyKind(x, DateTimeKind.Utc)`, an `AsUtc(...)` helper, or `.ToUniversalTime()` applied to a value known to be UTC.
- Not affected: values created in memory with `DateTime.UtcNow` (already `Kind=Utc`), and `DateTimeOffset`.
- Affected: any `DateTime` that comes from an entity property and reaches the DTO unchanged.

Also check for an existing model-wide converter (`ConfigureConventions` with a `DateTime` converter); if one exists, the remaining gap is somewhere else (raw SQL, Dapper, `FromSql`), so look there.

## Step 2: Check the writes

The fix assumes the stored values are UTC. Grep for `DateTime.Now`, `DateTime.Today` and `DateTimeKind.Local` under `<API_DIR>` (excluding tests). Every write path that stores local time must be fixed first, or stamping it as UTC will make it wrong in a new way. Report each one; in `projections` or `converter` mode, fix them first (`DateTime.UtcNow`, or convert from the user's time zone explicitly with `TimeZoneInfo.ConvertTimeToUtc`).

## Step 3a: `projections`

For each affected DTO, wrap the projected value: `DateTime.SpecifyKind(o.PlacedOn, DateTimeKind.Utc)`, and for nullable values `o.ShippedOn.HasValue ? DateTime.SpecifyKind(o.ShippedOn.Value, DateTimeKind.Utc) : null`. If the project has an `AsUtc` helper, use it instead. EF translates neither; they run on the materialised values, which is correct.

## Step 3b: `converter`

In the DbContext:

```csharp
protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
{
    configurationBuilder.Properties<DateTime>().HaveConversion<UtcDateTimeConverter>();
    configurationBuilder.Properties<DateTime?>().HaveConversion<NullableUtcDateTimeConverter>();
}
```

with the converters in the persistence folder (`ValueConverter<DateTime, DateTime>`: to the provider, `v.Kind == DateTimeKind.Utc ? v : v.ToUniversalTime()`; from the provider, `DateTime.SpecifyKind(v, DateTimeKind.Utc)`). This does not change the schema, but EF records value converters in the model snapshot, so run `ef-add-migration` and confirm the generated migration is empty (then remove it with the Local-environment prefix, or keep it if the project prefers). After the converter is in, the per-projection `SpecifyKind` calls are redundant; remove them only if the user wants the cleanup.

## Step 4: Verify

Run `verify-conventions.sh --changed-since HEAD`; the utc-kinds rows for the touched slices should pass. A real check is at runtime: `run-api`, call one affected endpoint, and confirm the JSON timestamps end in `Z`. Report what you observed.

## Report

Affected DTOs (fixed or listed), write paths that were not UTC, the mode applied, and the runtime observation or "runtime check pending".
