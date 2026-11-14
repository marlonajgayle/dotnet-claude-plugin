namespace Fixture.Api.Infrastructure.Outbox;

public sealed class OutboxProcessor
{
    public Task DispatchAsync(OutboxMessage message, CancellationToken ct)
    {
        switch (message.Type)
        {
            case nameof(OrderCreated):
                return Task.CompletedTask;
            default:
                return Task.CompletedTask;
        }
    }
}
