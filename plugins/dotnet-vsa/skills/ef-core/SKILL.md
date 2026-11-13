---
name: ef-core
description: "EF Core 10 reference for vertical-slice .NET APIs: DbContext setup, entity configuration, value converters, interceptors, migrations workflow, N+1 and cartesian explosion, ExecuteUpdate/ExecuteDelete pitfalls with the outbox, compiled queries, soft-delete query filters, DateTime kinds and TimeSpan columns. Load when touching persistence code or when the user mentions: EF Core, Entity Framework, DbContext, migration, LINQ query, N+1, Include, split query, value converter, interceptor, compiled query, query filter."
---

# EF Core: vertical-slice patterns and EF Core 10 reference

Before applying anything here, read the project's own DbContext and one entity configuration: run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"` and open `DBCONTEXT`. Where the project already does something differently and consistently, follow the project and mention the difference.

## 1. Conventions

1. Handlers depend on `IApplicationDbContext`, not the concrete context, so they can be swapped in tests.
2. Every read uses `AsNoTracking()`.
3. Every read filters `!x.IsDeleted`, unless the project uses a global query filter (§10).
4. Reads project to DTOs with `Select`, rather than `Include` plus mapping.
5. Handlers return `Result`/`Result<T>`; a missing row is `{Entity}Errors.NotFound(id)`, not an exception.
6. Every entity has an `IEntityTypeConfiguration<T>` (`internal sealed`, fluent only, explicit `ToTable`).
7. Writes go through aggregate methods and `SaveChangesAsync`, which is where auditing and the domain-event outbox run.
8. `CancellationToken` is passed to every async EF call.

Canonical read handler:

```csharp
public sealed class GetOrdersQueryHandler(IApplicationDbContext dbContext)
{
    public async Task<Result<List<OrderDto>>> HandleAsync(GetOrdersQuery query, CancellationToken ct)
    {
        var orders = await dbContext.Orders
            .AsNoTracking()
            .Where(o => !o.IsDeleted && o.CustomerId == query.CustomerId)
            .OrderByDescending(o => o.PlacedOn)
            .Take(query.PageSize)
            .Select(o => new OrderDto(o.Id, DateTime.SpecifyKind(o.PlacedOn, DateTimeKind.Utc), o.Total))
            .ToListAsync(ct);

        return Result<List<OrderDto>>.Success(orders);
    }
}
```

## 2. DbContext registration

- Scoped lifetime. No `AddDbContextPool` and no singleton context when the context takes scoped services such as a current-user accessor.
- `EnableRetryOnFailure` for cloud SQL; an explicit `CommandTimeout`; `MigrationsAssembly` pinned to the API assembly.
- `EnableSensitiveDataLogging()` only in the local environment branch; it logs parameter values. `EnableDetailedErrors()` never in Production.
- `LogTo(...)` with SQL output only locally.

## 3. Entity configuration

```csharp
internal sealed class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> builder)
    {
        builder.ToTable("Orders");
        builder.HasKey(o => o.Id).IsClustered(false);   // Guid keys: avoid clustered-index fragmentation
        builder.Property(o => o.Id).ValueGeneratedNever(); // ids are created in the domain
        builder.Property(o => o.Reference).IsRequired().HasMaxLength(32);
        builder.Property(o => o.IsDeleted).IsRequired().HasDefaultValue(false);
        builder.HasIndex(o => o.Reference).IsUnique().HasFilter("[IsDeleted] = 0");
        builder.HasOne(o => o.Customer).WithMany().HasForeignKey(o => o.CustomerId).OnDelete(DeleteBehavior.NoAction);
        builder.OwnsOne(o => o.ShippingAddress);
    }
}
```

- `OnDelete(NoAction)` where soft delete is the deletion model.
- Filtered indexes (`[IsDeleted] = 0`) so uniqueness ignores deleted rows.
- **Never `= new()` on a navigation property.** EF sees the new object as `Added` when the owner is added and inserts a blank related row (the "phantom row"), which usually fails a NOT NULL constraint and turns the request into a 500. Use `null!` for a required navigation and `T?` for an optional one. Collections initialised to `[]` or `new()` are fine.

## 4. DateTime and TimeSpan

- SQL Server returns `datetime2` as `DateTimeKind.Unspecified`. It serialises without a `Z`, and clients parse it as local time, so a UTC value appears shifted by the client's offset.
- Fix per projection with `DateTime.SpecifyKind(x, DateTimeKind.Utc)`, or once for the model:

  ```csharp
  protected override void ConfigureConventions(ModelConfigurationBuilder builder)
  {
      builder.Properties<DateTime>().HaveConversion<UtcDateTimeConverter>();
  }
  internal sealed class UtcDateTimeConverter() : ValueConverter<DateTime, DateTime>(
      v => v.Kind == DateTimeKind.Utc ? v : v.ToUniversalTime(),
      v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
  ```

  Check first that every write is already UTC (`fix-utc-kinds` does both).
- `TimeSpan` maps to SQL `time`, which stops below 24 hours. `TimeSpan.FromHours(24)` fails the whole `SaveChangesAsync`. Use `long` ticks or minutes for durations that can reach a day.

## 5. Value converters

Use one when a CLR type needs translating to a column (enum as string, strongly typed id, JSON, encryption). Encrypted-column caveats: you cannot filter or sort on the ciphertext; indexes on it are useless; key rotation needs a re-encryption migration; the converter needs the encryption service, so build it in a configuration class that receives the service.

## 6. Interceptors

`SaveChangesInterceptor` is the right home for auditing and outbox capture when they outgrow the `SaveChangesAsync` override. Register them scoped and attach with `.AddInterceptors(sp.GetRequiredService<...>())`. Trade-off: the behaviour is no longer visible in the DbContext file, so leave a comment there pointing at the interceptors.

## 7. Migrations

```bash
dotnet ef migrations add <Name> --project <API_PROJECT>
dotnet ef migrations script --idempotent --project <API_PROJECT> --output migration.sql
dotnet ef database update --project <API_PROJECT>      # local database only
```

Use the `ef-add-migration` skill: it reviews the generated file for destructive operations. Never edit a committed migration (a hook blocks it); add a new one. `Down` must reverse `Up`.

## 8. Query performance

- **N+1**: a query inside a `foreach` over query results. Project the related data in one query instead:
  `.Select(c => new CustomerOrdersDto(c.Id, c.Orders.Where(o => !o.IsDeleted).Select(o => new OrderDto(...)).ToList()))`
- **Cartesian explosion**: two or more collection `Include`s in one query; add `.AsSplitQuery()`.
- **Unbounded reads**: `ToListAsync()` on a growing table without `Take`.
- `AnyAsync(...)` instead of `CountAsync() > 0`.
- `query.ToQueryString()` shows the SQL for one query.
- `check-ef-performance` scans for all of these.

## 9. ExecuteUpdateAsync / ExecuteDeleteAsync

They issue one `UPDATE`/`DELETE` and skip the change tracker. Good for bulk maintenance on entities that raise no events (sweeping processed outbox rows, expiring stale records).

They also skip `SaveChangesAsync`, so **auditing and the domain-event outbox do not run**. On an aggregate that raises events, the events are silently lost: load, mutate through the aggregate, and save instead. They skip interceptors too, and run immediately even inside a transaction you opened; include `!x.IsDeleted` in the predicate yourself.

## 10. Global soft-delete filter

`builder.HasQueryFilter(x => !x.IsDeleted)` removes the repeated `Where`, but it is a project-wide decision: admin and audit views need `IgnoreQueryFilters()`; required navigations to a filtered entity silently drop rows; and the manual filters become redundant. Propose it; do not adopt it in passing.

## 11. Compiled queries

`EF.CompileAsyncQuery` helps only on genuinely hot paths and cannot take dynamic predicates. Measure before adopting.

## 12. EF Core 10 notes

- `ExecuteUpdate` covers more property types; recheck old workarounds.
- `OwnsOne(...).ToJson()` stores a value object as a JSON column on SQL Server 2022+ (not filterable without `JSON_VALUE`).
- Better `GroupBy` translation: retest queries that were moved to the client.
- Release notes: https://learn.microsoft.com/ef/core/what-is-new/ef-core-10.0/whatsnew

## Cheat sheet

| Situation | Reach for |
|---|---|
| New read | `AsNoTracking()` + `!IsDeleted` + `Select` to DTO + `SpecifyKind` on DateTimes |
| New write | load tracked, mutate via aggregate, `SaveChangesAsync(ct)` |
| Bulk change, no events | `ExecuteUpdateAsync` with `!IsDeleted` in the predicate |
| Several collection Includes | `.AsSplitQuery()` |
| New entity | `add-entity` (configuration, DbSet, migration) |
| New domain event | `add-domain-event` (event, handler, DI, dispatch branch) |
