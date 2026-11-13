---
name: add-entity
description: "Scaffold a domain entity for a vertical-slice .NET API: the entity class (deriving from the project's auditable/aggregate base), its {Name}Errors factory, an IEntityTypeConfiguration<T> with key, soft-delete default and filtered indexes, and the DbSet on the DbContext and its interface. Then hands off to ef-add-migration. Use before add-endpoint when the entity does not exist yet: add entity, new entity, new table, new aggregate, domain model for X."
argument-hint: "<Area>.<Name> [Prop:Type ...] [--aggregate]"
---

# Add Entity

`add-endpoint` assumes the entity exists. This is the step before it, and the place where `= new()` navigations and missing configurations usually slip in.

Arguments: `$ARGUMENTS`, for example `Orders.Refund OrderId:Guid Amount:decimal Reason:string? --aggregate`.

- `--aggregate`: derive from the aggregate-root base (the entity can `Raise` domain events). Otherwise derive from the auditable base.

## Step 0: Locate and learn the project's shape

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `API_DIR`, `DBCONTEXT` and `SLN`. Then read:

- The base types in SharedKernel (`BaseEntity<T>`, `AuditableEntity<T>`, `AggregateRoot<T>` or the project's equivalents): which carries `IsDeleted`, the audit fields and `Raise`.
- One existing entity in the same area (or the closest one), its `{Entity}Errors` class and its configuration. Mirror their structure exactly: constructors, factory methods, private setters, folder, namespace.
- `DBCONTEXT` and the `IApplicationDbContext` interface, to see how DbSets are declared.

## Step 1: Validate

- Empty: reply with the usage from `argument-hint` and stop.
- No type with this name exists (Grep `class <Name>\b`).
- Unknown property types: ask rather than guess.

## Step 2: Entity — `Domain/.../<Area>/<Name>.cs`

- Derive from the base chosen above, `Guid` id unless the area uses something else.
- Private setters; a static `Create(...)` factory (or the constructor style siblings use) that validates invariants and returns `Result<<Name>>` if siblings do.
- State changes go through methods (`Approve()`, `Cancel(reason)`), which call `Raise(new ...)` on an aggregate when other slices must react. Use `add-domain-event` for any new event.
- Navigations: `public Order Order { get; private set; } = null!;` for required, `Order?` for optional. **Never `= new()`**: EF would insert a blank related row (phantom row). Collections: `private readonly List<X> _items = [];` with an `IReadOnlyCollection<X>` view.
- `DateTime` properties hold UTC; `TimeSpan` only for durations under 24 hours (SQL `time` overflows).

## Step 3: Errors — `<Name>Errors.cs`

A static class beside the entity, mirroring a sibling:

```csharp
public static class RefundErrors
{
    public static Error NotFound(Guid id) => Error.NotFound("Refund.NotFound", $"Refund '{id}' was not found.");
}
```

Add only the errors the factory and methods actually return.

## Step 4: Configuration — `<Persistence>/Configurations/<Name>Configuration.cs`

```csharp
internal sealed class RefundConfiguration : IEntityTypeConfiguration<Refund>
{
    public void Configure(EntityTypeBuilder<Refund> builder)
    {
        builder.ToTable("Refunds");
        builder.HasKey(r => r.Id).IsClustered(false);
        builder.Property(r => r.Id).ValueGeneratedNever();
        builder.Property(r => r.Amount).HasPrecision(18, 2);
        builder.Property(r => r.Reason).HasMaxLength(500);
        builder.Property(r => r.IsDeleted).IsRequired().HasDefaultValue(false);
        builder.HasOne(r => r.Order).WithMany().HasForeignKey(r => r.OrderId).OnDelete(DeleteBehavior.NoAction);
        builder.HasIndex(r => r.OrderId).HasFilter("[IsDeleted] = 0");
    }
}
```

Copy the clustering, key generation, delete behaviour and index style the project already uses. Give every string a max length and every decimal a precision.

## Step 5: DbSet

Add `DbSet<<Name>> <Plural>` to the DbContext and to `IApplicationDbContext`, in the same style and alphabetical position as the others.

## Step 6: Build and verify

`bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --changed-since HEAD`. The phantom-nav row must be clean.

## Step 7: Migration

Hand off to `ef-add-migration Create<Name>Table`. Do not run `dotnet ef` directly from this skill.

## Step 8: Report

Links to the entity, errors, configuration and both DbSet lines; the verify summary; the migration result; next step `add-endpoint <verb> <Area>.<Name>`. State: uncommitted.
