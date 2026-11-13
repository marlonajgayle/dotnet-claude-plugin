---
name: add-background-job
description: "Scaffold a hosted BackgroundService for an ASP.NET Core API: an options class bound from configuration, an Add{Name} registration extension, a periodic loop with interval and jitter, a new DI scope per run via IServiceScopeFactory, Serilog/ILogger context, cancellation-safe shutdown, and a health check that reports a stalled job. Modelled on the project's existing processors (the outbox processor). Use when the user says: add background job, scheduled job, recurring task, hosted service, BackgroundService, worker, poll every N minutes."
argument-hint: "<Name> [--every <interval>]"
---

# Add Background Job

Arguments: `$ARGUMENTS`, for example `ExpireStaleCarts --every 15m`.

Hosted services look simple and fail quietly: a captured scoped DbContext, an exception that kills the loop forever, or a tight loop on shutdown. This skill writes the pattern the project's own processors already use.

## Step 0: Learn the existing pattern

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/discover.sh"`; use `API_DIR`, `PROGRAM_CS`, `OUTBOX_DISPATCHER`. Grep `<API_DIR>` for `: BackgroundService` and read the existing processors (the outbox processor at minimum), their options classes and their `Add...` extensions. Mirror their folder (for example `Infrastructure/BackgroundJobs/`), naming, logging and configuration section style.

## Step 1: Validate

- `Name` is PascalCase without a `Job`/`Processor` suffix (the skill adds `Processor`, or whatever siblings use).
- No existing type with that name.
- Default interval 5 minutes if `--every` is absent; say so in the report.

## Step 2: Files in `<jobs folder>/<Name>/`

`<Name>Options.cs`
```csharp
public sealed class <Name>Options
{
    public const string SectionName = "BackgroundJobs:<Name>";
    public bool Enabled { get; init; } = true;
    public TimeSpan Interval { get; init; } = TimeSpan.FromMinutes(5);
    public TimeSpan MaxJitter { get; init; } = TimeSpan.FromSeconds(30);
}
```

`<Name>Processor.cs`
```csharp
internal sealed class <Name>Processor(
    IServiceScopeFactory scopeFactory,
    IOptions<<Name>Options> options,
    <Name>Heartbeat heartbeat,
    ILogger<<Name>Processor> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!options.Value.Enabled) { logger.LogInformation("<Name> disabled"); return; }
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var scope = scopeFactory.CreateAsyncScope();     // new scope per run: never hold a DbContext across runs
                var db = scope.ServiceProvider.GetRequiredService<IApplicationDbContext>();
                using (logger.BeginScope(new Dictionary<string, object> { ["Job"] = "<Name>" }))
                {
                    await RunOnceAsync(db, stoppingToken);
                }
                heartbeat.Beat();
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex)
            {
                logger.LogError(ex, "<Name> run failed; retrying next interval");   // never let one failure end the loop
            }
            var jitter = TimeSpan.FromMilliseconds(Random.Shared.NextDouble() * options.Value.MaxJitter.TotalMilliseconds);
            try { await Task.Delay(options.Value.Interval + jitter, stoppingToken); }
            catch (OperationCanceledException) { break; }
        }
    }

    private static async Task RunOnceAsync(IApplicationDbContext db, CancellationToken ct)
    {
        // TODO: the job's work. Load, mutate through aggregate methods, SaveChangesAsync(ct)
        // so auditing and domain events run. Batch with Take(n). Filter !IsDeleted.
        await Task.CompletedTask;
    }
}
```

`<Name>Heartbeat.cs` (singleton recording the last successful run) and `<Name>HealthCheck.cs` (`IHealthCheck`: Healthy when the last beat is newer than 3 × Interval, Degraded otherwise, Healthy while disabled).

`<Name>Extensions.cs`
```csharp
public static IServiceCollection Add<Name>(this IServiceCollection services, IConfiguration configuration)
{
    services.Configure<<Name>Options>(configuration.GetSection(<Name>Options.SectionName));
    services.AddSingleton<<Name>Heartbeat>();
    services.AddHostedService<<Name>Processor>();
    services.AddHealthChecks().AddCheck<<Name>HealthCheck>("<name>-job", tags: ["jobs"]);
    return services;
}
```

## Step 3: Wire up

- `builder.Services.Add<Name>(builder.Configuration);` in `<PROGRAM_CS>`, next to the other job registrations.
- An `appsettings.json` section with non-secret defaults (`Enabled`, `Interval`). Nothing secret goes here; the `guard-config-secrets` hook blocks it.

## Step 4: Verify

`bash "${CLAUDE_SKILL_DIR}/../../scripts/verify-conventions.sh" --changed-since HEAD`. Then, if the user wants a runtime check: `run-api`, then confirm the health endpoint lists the job and the log shows a run.

## Report

Files, the registration line, the config section, the verify summary, and what is left: the body of `RunOnceAsync`, and `write-handler-tests` for it. If the job's work raises domain events, remind the user that `ExecuteUpdate`/`ExecuteDelete` would drop them.
