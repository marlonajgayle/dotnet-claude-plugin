namespace DvsaTemplate.Api.Infrastructure.Authorization;

/// <summary>
/// Every endpoint names one of these: .RequireAuthorization(AuthorizationPolicies.User). A public
/// endpoint uses .AllowAnonymous() with a "// anonymous: reason" comment instead.
/// </summary>
public static class AuthorizationPolicies
{
    /// <summary>Any authenticated caller. Owner-scoped data still needs an ownership check in the handler.</summary>
    public const string User = "User";

    public const string Admin = "Admin";

    public static IServiceCollection AddAppAuthorization(this IServiceCollection services)
    {
        services.AddAuthorizationBuilder()
            .AddPolicy(User, policy => policy.RequireAuthenticatedUser())
            .AddPolicy(Admin, policy => policy.RequireAuthenticatedUser().RequireRole("admin"));

        return services;
    }
}
