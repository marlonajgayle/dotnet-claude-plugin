namespace Fixture.Api.Features.Orders.ListOrders;

public static class ListOrdersEndpoint
{
    public static void Map(IEndpointRouteBuilder app) =>
        app.MapGet("/orders", () => Results.Ok())
            .AllowAnonymous()
            .DisableRateLimiting();
}
