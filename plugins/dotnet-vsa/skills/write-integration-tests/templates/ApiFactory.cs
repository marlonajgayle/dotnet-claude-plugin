using DvsaTemplate.Api.Infrastructure.Outbox;
using DvsaTemplate.Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Testcontainers.MsSql;

namespace DvsaTemplate.Api.IntegrationTests.Infrastructure;

/// <summary>
/// Runs the real API in memory against SQL Server in a container: the real pipeline, policies,
/// validators and EF Core configuration. One container serves every test in the collection.
/// Authentication is replaced by TestAuthHandler, so each test chooses its caller.
/// </summary>
public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly MsSqlContainer _database = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest").Build();

    public async Task InitializeAsync()
    {
        await _database.StartAsync();

        await using var scope = Services.CreateAsyncScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        if (dbContext.Database.GetMigrations().Any())
        {
            await dbContext.Database.MigrateAsync();
        }
        else
        {
            await dbContext.Database.EnsureCreatedAsync();
        }
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        await base.DisposeAsync();
        await _database.DisposeAsync();
    }

    /// <summary>A client with no caller: requests are anonymous.</summary>
    public HttpClient CreateAnonymousClient() => CreateClient();

    /// <summary>A client authenticated as <paramref name="userId"/> with the given roles.</summary>
    public HttpClient CreateClientAs(string userId, params string[] roles)
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Add(TestAuthHandler.UserHeader, userId);
        if (roles.Length > 0)
        {
            client.DefaultRequestHeaders.Add(TestAuthHandler.RolesHeader, string.Join(',', roles));
        }

        return client;
    }

    /// <summary>Dispatches pending outbox messages now, instead of waiting for the background timer.</summary>
    public Task<int> ProcessOutboxAsync() =>
        Services.GetRequiredService<OutboxProcessor>().ProcessBatchAsync(CancellationToken.None);

    /// <summary>Runs <paramref name="action"/> against a fresh DbContext, to arrange or assert state.</summary>
    public async Task<T> WithDbContextAsync<T>(Func<ApplicationDbContext, Task<T>> action)
    {
        await using var scope = Services.CreateAsyncScope();
        return await action(scope.ServiceProvider.GetRequiredService<ApplicationDbContext>());
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:Default", _database.GetConnectionString());
        builder.UseSetting("RateLimiting:ReadPerMinute", "100000");
        builder.UseSetting("RateLimiting:WritePerMinute", "100000");

        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication(TestAuthHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });

            // The outbox timer would race the tests; they call ProcessOutboxAsync instead.
            var hosted = services.Single(d => d.ServiceType == typeof(IHostedService) && d.ImplementationType == typeof(OutboxProcessor));
            services.Remove(hosted);
            services.AddSingleton<OutboxProcessor>();
        });
    }
}

[CollectionDefinition(Name)]
public sealed class ApiCollection : ICollectionFixture<ApiFactory>
{
    public const string Name = "Api";
}
