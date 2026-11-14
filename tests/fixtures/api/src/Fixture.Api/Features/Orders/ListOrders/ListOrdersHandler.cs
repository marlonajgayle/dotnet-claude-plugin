namespace Fixture.Api.Features.Orders.ListOrders;

public sealed record OrderListItemDto(Guid Id, DateTime CreatedAt);

public sealed class ListOrdersHandler(AppDbContext db)
{
    public Task<List<OrderListItemDto>> HandleAsync(CancellationToken ct) =>
        db.Orders.AsNoTracking()
            .Select(o => new OrderListItemDto(o.Id, o.CreatedAt))
            .ToListAsync(ct);
}
