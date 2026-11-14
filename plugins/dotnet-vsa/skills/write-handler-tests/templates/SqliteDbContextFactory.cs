using DvsaTemplate.Api.Infrastructure.Persistence;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace DvsaTemplate.Api.Tests.Infrastructure;

/// <summary>
/// A real ApplicationDbContext over SQLite in memory, one database per instance. Relational
/// behaviour (keys, unique and filtered indexes, required columns) is close to SQL Server, and the
/// outbox is written by the real SaveChangesAsync. Create one per test, arrange with one context
/// and assert with a fresh one from <see cref="CreateContext"/>, so assertions read what was saved
/// rather than what is tracked.
/// </summary>
public sealed class SqliteDbContextFactory : IDisposable
{
    private readonly SqliteConnection _connection = new("DataSource=:memory:");

    public SqliteDbContextFactory()
    {
        // The in-memory database lives as long as this connection stays open.
        _connection.Open();
        using var dbContext = CreateContext();
        dbContext.Database.EnsureCreated();
    }

    /// <summary>The clock every context uses. Move it with <see cref="TestClock.Advance"/>.</summary>
    public TestClock Clock { get; } = new(new DateTimeOffset(2026, 1, 15, 9, 30, 0, TimeSpan.Zero));

    public ApplicationDbContext CreateContext() =>
        new(new DbContextOptionsBuilder<ApplicationDbContext>().UseSqlite(_connection).Options, Clock);

    public void Dispose() => _connection.Dispose();
}
