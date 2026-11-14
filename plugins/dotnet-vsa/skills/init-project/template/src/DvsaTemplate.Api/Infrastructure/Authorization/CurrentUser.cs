using System.Security.Claims;

namespace DvsaTemplate.Api.Infrastructure.Authorization;

/// <summary>The caller. Handlers take the caller's id from here, never from the route or body.</summary>
public interface ICurrentUser
{
    string? UserId { get; }

    bool IsAuthenticated { get; }
}

public sealed class CurrentUser(IHttpContextAccessor httpContextAccessor) : ICurrentUser
{
    private ClaimsPrincipal? Principal => httpContextAccessor.HttpContext?.User;

    public string? UserId =>
        Principal?.FindFirstValue(ClaimTypes.NameIdentifier) ?? Principal?.FindFirstValue("sub");

    public bool IsAuthenticated => Principal?.Identity?.IsAuthenticated ?? false;
}
