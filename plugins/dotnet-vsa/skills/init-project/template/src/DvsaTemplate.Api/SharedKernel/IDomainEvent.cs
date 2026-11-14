namespace DvsaTemplate.Api.SharedKernel;

/// <summary>
/// A fact other slices react to. Each event needs a handler, its AddScoped registration in
/// Program.cs and a nameof branch in OutboxDispatcher (the add-domain-event skill adds all three).
/// </summary>
public interface IDomainEvent
{
}

public interface IDomainEventHandler<in TEvent>
    where TEvent : IDomainEvent
{
    Task HandleAsync(TEvent domainEvent, CancellationToken cancellationToken);
}
