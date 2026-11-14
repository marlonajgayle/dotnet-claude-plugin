namespace Fixture.Api.Domain;

public sealed record OrderCreated(Guid OrderId) : IDomainEvent;

public sealed record OrderCancelled(Guid OrderId) : IDomainEvent;
