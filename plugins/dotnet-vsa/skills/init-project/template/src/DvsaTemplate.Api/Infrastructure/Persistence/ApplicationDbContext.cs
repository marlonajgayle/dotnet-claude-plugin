using System.Text.Json;
using DvsaTemplate.Api.Infrastructure.Outbox;

namespace DvsaTemplate.Api.Infrastructure.Persistence;

public sealed class ApplicationDbContext(DbContextOptions<ApplicationDbContext> options, TimeProvider timeProvider)
    : DbContext(options), IApplicationDbContext
{
    public DbSet<OutboxMessage> OutboxMessages => Set<OutboxMessage>();

    /// <summary>
    /// Writes the domain events raised by tracked aggregates to the outbox, in the same transaction
    /// as the change. ExecuteUpdate and ExecuteDelete bypass this, so they drop events.
    /// </summary>
    public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        var utcNow = timeProvider.GetUtcNow().UtcDateTime;
        var aggregates = ChangeTracker.Entries<IHasDomainEvents>()
            .Select(entry => entry.Entity)
            .Where(entity => entity.DomainEvents.Count > 0)
            .ToList();

        foreach (var aggregate in aggregates)
        {
            foreach (var domainEvent in aggregate.DomainEvents)
            {
                var type = domainEvent.GetType();
                OutboxMessages.Add(new OutboxMessage(
                    Guid.CreateVersion7(), type.Name, JsonSerializer.Serialize(domainEvent, type), utcNow));
            }

            aggregate.ClearDomainEvents();
        }

        return await base.SaveChangesAsync(cancellationToken);
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(ApplicationDbContext).Assembly);

        foreach (var entityType in modelBuilder.Model.GetEntityTypes()
                     .Where(type => typeof(IHasDomainEvents).IsAssignableFrom(type.ClrType)))
        {
            modelBuilder.Entity(entityType.ClrType).Ignore(nameof(IHasDomainEvents.DomainEvents));
        }
    }
}
