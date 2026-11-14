using DvsaTemplate.Api.Infrastructure.Outbox;

namespace DvsaTemplate.Api.Infrastructure.Persistence;

/// <summary>What handlers inject. Add a DbSet here and on ApplicationDbContext for each entity.</summary>
public interface IApplicationDbContext
{
    DbSet<OutboxMessage> OutboxMessages { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
