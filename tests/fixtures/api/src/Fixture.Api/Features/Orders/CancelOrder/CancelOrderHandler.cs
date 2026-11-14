namespace Fixture.Api.Features.Orders.CancelOrder;

public sealed class CancelOrderHandler(AppDbContext db)
{
    public Task<Result> HandleAsync(Guid id, CancellationToken ct) =>
        Task.FromResult(Result.Success());
}
