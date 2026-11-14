namespace DvsaTemplate.Api.Infrastructure.Outbox;

/// <summary>
/// Routes a stored event to its handler. There is one branch per domain event, matched with
/// nameof, and a message with no branch is recorded as an error instead of vanishing. The
/// add-domain-event skill appends a branch for each new event, in this shape:
///
///   if (message.Type == nameof(&lt;EventName&gt;))
///   {
///       var domainEvent = JsonSerializer.Deserialize&lt;&lt;EventName&gt;&gt;(message.Payload)!;
///       await services.GetRequiredService&lt;&lt;EventName&gt;Handler&gt;().HandleAsync(domainEvent, cancellationToken);
///       return true;
///   }
/// </summary>
public static class OutboxDispatcher
{
    public static async Task<bool> DispatchAsync(
        OutboxMessage message, IServiceProvider services, CancellationToken cancellationToken)
    {
        // Dispatch branches go here, before the final return.

        await Task.CompletedTask;
        return false;
    }
}
