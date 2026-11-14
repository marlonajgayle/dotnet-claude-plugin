namespace Fixture.Api.Features.Orders.CancelOrder;

public static class CancelOrderEndpoint
{
    public static void Map(IEndpointRouteBuilder app) =>
        app.MapDelete("/orders/{id:guid}", (Guid id) => Results.NoContent());
}
