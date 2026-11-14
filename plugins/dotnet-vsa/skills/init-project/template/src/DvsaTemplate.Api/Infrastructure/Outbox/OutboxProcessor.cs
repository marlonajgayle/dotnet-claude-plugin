using DvsaTemplate.Api.Infrastructure.Persistence;

namespace DvsaTemplate.Api.Infrastructure.Outbox;

/// <summary>Dispatches stored domain events every few seconds, a batch at a time, in a fresh scope.</summary>
public sealed class OutboxProcessor(
    IServiceScopeFactory scopeFactory,
    TimeProvider timeProvider,
    ILogger<OutboxProcessor> logger) : BackgroundService
{
    private const int BatchSize = 20;
    private const int MaxAttempts = 5;
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(5);

    /// <summary>Processes one batch and returns how many messages it handled. Tests call it directly.</summary>
    public async Task<int> ProcessBatchAsync(CancellationToken cancellationToken)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        var messages = await dbContext.OutboxMessages
            .Where(message => message.ProcessedOnUtc == null && message.Attempts < MaxAttempts)
            .OrderBy(message => message.OccurredOnUtc)
            .Take(BatchSize)
            .ToListAsync(cancellationToken);

        foreach (var message in messages)
        {
            try
            {
                if (await OutboxDispatcher.DispatchAsync(message, scope.ServiceProvider, cancellationToken))
                {
                    message.MarkProcessed(timeProvider.GetUtcNow().UtcDateTime);
                }
                else
                {
                    message.MarkFailed($"No dispatch branch for '{message.Type}'. Add one to OutboxDispatcher (add-domain-event).");
                    logger.LogError("Outbox message {MessageId} has no dispatch branch for {Type}", message.Id, message.Type);
                }
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                message.MarkFailed(exception.Message);
                logger.LogError(exception, "Outbox message {MessageId} ({Type}) failed", message.Id, message.Type);
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return messages.Count;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval, timeProvider);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await ProcessBatchAsync(stoppingToken);
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                logger.LogError(exception, "Outbox batch failed");
            }
        }
    }
}
