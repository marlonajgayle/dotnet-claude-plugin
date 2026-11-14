using System.Security.Claims;
using System.Threading.RateLimiting;

namespace DvsaTemplate.Api.Infrastructure.RateLimiting;

/// <summary>
/// Every endpoint names one of these: .RequireRateLimiting(RateLimitPolicies.Read). Limits are per
/// caller (user id, else client IP) and come from the RateLimiting section of configuration.
/// </summary>
public static class RateLimitPolicies
{
    public const string Read = "read";

    public const string Write = "write";

    public static IServiceCollection AddAppRateLimiting(this IServiceCollection services, IConfiguration configuration)
    {
        var readPerMinute = configuration.GetValue("RateLimiting:ReadPerMinute", 120);
        var writePerMinute = configuration.GetValue("RateLimiting:WritePerMinute", 30);

        services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.AddPolicy(Read, context => PerCaller(context, readPerMinute));
            options.AddPolicy(Write, context => PerCaller(context, writePerMinute));
        });

        return services;
    }

    private static RateLimitPartition<string> PerCaller(HttpContext context, int permitsPerMinute) =>
        RateLimitPartition.GetFixedWindowLimiter(
            context.User.FindFirstValue(ClaimTypes.NameIdentifier)
                ?? context.Connection.RemoteIpAddress?.ToString()
                ?? "anonymous",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = permitsPerMinute,
                Window = TimeSpan.FromMinutes(1),
            });
}
