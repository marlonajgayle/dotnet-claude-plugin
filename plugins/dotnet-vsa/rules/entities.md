---
paths:
  - "**/Domain/**/*.cs"
  - "**/Configurations/*Configuration.cs"
---

# Entities and EF Core configuration

**Entities**

- **Never initialise a navigation with `= new()`.** EF inserts a blank related row when the owner is added. Use `= null!` for a required navigation and a nullable type for an optional one. Collections are fine: `private readonly List<X> _items = [];` behind an `IReadOnlyCollection<X>`.
- Derive from the project's auditable or aggregate-root base type. Use private setters, and change state through methods, which call `Raise(...)` on an aggregate when other slices must react.
- Each entity has a `{Entity}Errors` class beside it. Add only the errors the code returns.
- `DateTime` properties hold UTC. Use `TimeSpan` only for durations under 24 hours (SQL `time` overflows).
- Soft delete with `MarkAsDeleted()`. Do not add a hard-delete path.

**Configurations (`IEntityTypeConfiguration<T>`)**

- Give every string a max length and every decimal a precision.
- `IsDeleted` is required with a default of `false`. Indexes on soft-deletable tables carry a filter (`HasFilter("[IsDeleted] = 0")`).
- Copy the key, clustering and delete-behaviour style of the existing configurations.
- A new entity also needs its `DbSet` on the DbContext and on `IApplicationDbContext`.

A model change needs a migration: use the `ef-add-migration` skill, which reviews the result for destructive operations. `add-entity` scaffolds the entity, errors, configuration and DbSet together.
