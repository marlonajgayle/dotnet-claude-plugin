namespace Fixture.Api.Features.Orders.GetOrder;

public static class GetOrderEndpoint
{
    // anonymous: order status pages are public by design
    public static void Map(IEndpointRouteBuilder app) =>
        app.MapGet("/orders/{id:guid}", (Guid id) => Results.Ok())
            .AllowAnonymous()
            .RequireRateLimiting(RateLimitPolicies.Read);
}
