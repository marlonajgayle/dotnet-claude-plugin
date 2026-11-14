namespace Fixture.Api.Features.Orders.CreateOrder;

public static class CreateOrderEndpoint
{
    public static void Map(IEndpointRouteBuilder app) =>
        app.MapPost("/orders", (CreateOrderCommand command) => Results.Ok())
            .RequireAuthorization(AuthorizationPolicies.Customer)
            .RequireRateLimiting(RateLimitPolicies.Write);
}
