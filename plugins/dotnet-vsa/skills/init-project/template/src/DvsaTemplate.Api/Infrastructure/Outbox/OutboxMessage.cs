namespace DvsaTemplate.Api.Infrastructure.Outbox;

public sealed class OutboxMessage
{
    public OutboxMessage(Guid id, string type, string payload, DateTime occurredOnUtc)
    {
        Id = id;
        Type = type;
        Payload = payload;
        OccurredOnUtc = occurredOnUtc;
    }

    // For EF Core.
    private OutboxMessage()
    {
    }

    public Guid Id { get; private set; }

    /// <summary>The event's type name; OutboxDispatcher matches it with nameof.</summary>
    public string Type { get; private set; } = null!;

    public string Payload { get; private set; } = null!;

    public DateTime OccurredOnUtc { get; private set; }

    public DateTime? ProcessedOnUtc { get; private set; }

    public int Attempts { get; private set; }

    public string? Error { get; private set; }

    public void MarkProcessed(DateTime utcNow)
    {
        ProcessedOnUtc = utcNow;
        Error = null;
    }

    public void MarkFailed(string error)
    {
        Attempts++;
        Error = error.Length > 2000 ? error[..2000] : error;
    }
}
