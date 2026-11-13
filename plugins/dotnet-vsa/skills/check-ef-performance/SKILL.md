---
name: check-ef-performance
description: "Read-only EF Core performance audit: N+1 queries, missing indexes, unbounded queries, cartesian explosion, tracking on read paths, missing !IsDeleted, ExecuteUpdate/ExecuteDelete on event-raising aggregates, missing CancellationToken, CountAsync() > 0. Writes a severity-rated report to .claude/ef-performance/<timestamp>.md. No edits, no dotnet, no database. Use when the user says: check ef performance, EF performance audit, N+1 check, slow query review."
argument-hint: "[full]"
---

# EF Performance Check

Read-only static audit. Do not edit source, run `dotnet` or touch a database. The only file you write is the report.

Scope from `$ARGUMENTS`: empty means `.cs` files changed against `origin/main` (falling back to the full scan when that is empty or you are on `main`); `full` means every `.cs` under the API project except `bin/`, `obj/` and `Migrations/`.

Severity: **Critical** silent data loss or a guaranteed problem at scale; **High** measurable cost or convention miss; **Medium** best-practice violation; **Low** defence in depth; **Info** observation or skipped check.

Every finding cites a clickable `[file.cs:LN](path#LLN)`. Never fabricate: if a heuristic is inconclusive, say so under Coverage Notes.

## Phase 0: Discovery

1. Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `API_DIR`, `DBCONTEXT`.
2. Resolve the file set for the scope.
3. **Index map**: read every `*Configuration.cs` implementing `IEntityTypeConfiguration<T>`. Record each entity's `HasIndex` properties and its `HasForeignKey` properties (EF indexes those by convention).
4. **Soft-deletable set**: entities deriving from the base type that declares `IsDeleted`.
5. **Event-raising set**: entities deriving from `AggregateRoot<>`, plus any entity calling `Raise(new `.
6. **High-volume set**: infer from names and domain (orders, transactions, logs, outbox, users, messages, appointments); mark the rest low-volume. List both in the report.
7. `mkdir -p .claude/ef-performance`; the report is `.claude/ef-performance/<YYYY-MM-DD-HHMM>.md`. Say in one line what scope you are scanning and where the report will go.

## Checks

1. **Tracking on read paths**: query handlers (`Get|List|Find|Search|Query` in the file name) whose EF chain ends in `ToListAsync`/`FirstOrDefaultAsync`/`SingleOrDefaultAsync`/`ToArrayAsync` without `AsNoTracking()`: High.
2. **Missing `!IsDeleted`**: a chain over a soft-deletable DbSet with none of `!x.IsDeleted`, `IsDeleted == false`, `IgnoreQueryFilters(`: High. Skip if the project has a global `HasQueryFilter` on `IsDeleted`.
3. **N+1**: a `foreach` over a variable assigned from an EF terminator whose body awaits another DbContext query: Critical. A `Select` that calls a method touching the DbContext: Critical.
4. **Cartesian explosion**: one chain with two or more `Include`s on collection navigations (plural names, or `ICollection<>`/`List<>` properties on the entity) and no `AsSplitQuery()`: High.
5. **Unbounded queries**: `ToListAsync`/`ToArrayAsync` with no `Take`/`Skip` and no paging wrapper. Medium on high-volume sets, Low otherwise.
6. **Missing indexes**: single-property `Where`/`OrderBy` on a property that is not the key, not an FK and not in the index map: Medium. Skip `IsDeleted` and audit dates. The remediation shows both `builder.HasIndex(x => x.Prop)` (with `.HasFilter("[IsDeleted] = 0")` on soft-deletable entities) and `ef-add-migration Add<Entity><Prop>Index`.
7. **Project traps**
   - 7a `ExecuteUpdateAsync`/`ExecuteDeleteAsync` on an event-raising entity: Critical (bypasses `SaveChangesAsync`, so outbox events are dropped). Remediation: load, mutate through the aggregate, save.
   - 7b An async handler without a `CancellationToken` parameter, or an EF `*Async(` call that does not pass it: Medium.
   - 7c `CountAsync(...) > 0`, `Count() > 0` or `== 0`: Medium; use `AnyAsync`.

## Report

```markdown
# EF Performance Audit — <timestamp>
**Scope**: <branch diff (N files) | full> · **Branch**: <branch>
**Index map from**: N configurations · **Soft-deletable**: … · **Event-raising**: … · **High-volume**: …

## Executive summary
Critical N · High N · Medium N · Low N · Info N
### Top risks
1. **[CRITICAL]** … — [file:LN](...)

## Check 1: Tracking overhead
### [SEVERITY] <Handler>
- **Location** · **What** · **Why it matters** · **Remediation** (exact code)
… Checks 2–7 in the same format. A check with no findings says `_No findings._` so it is visible that it ran.

## Coverage notes
Files scanned, configurations parsed, skipped checks and why, heuristic limits.
```

## Chat summary

Counts per severity, the top three findings with links, and the report path. Put remediation in the report, not in chat.
