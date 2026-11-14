namespace Fixture.Api.Features.Orders.GetOrder;

public sealed record OrderResponse(Guid Id, DateTime CreatedAt);

public sealed class GetOrderHandler(AppDbContext db)
{
    public async Task<Result<OrderResponse>> HandleAsync(Guid id, CancellationToken ct)
    {
        var order = await db.Orders.AsNoTracking()
            .Where(o => o.Id == id && !o.IsDeleted)
            .Select(o => new OrderResponse(o.Id, DateTime.SpecifyKind(o.CreatedAt, DateTimeKind.Utc)))
            .FirstOrDefaultAsync(ct);
        return order is null ? OrderErrors.NotFound : order;
    }
}
