namespace Fixture.Api.Features.Orders.CreateOrder;

public sealed class CreateOrderHandler(AppDbContext db)
{
    public Task<Result<Guid>> HandleAsync(CreateOrderCommand command, CancellationToken ct) =>
        Task.FromResult(Result.Success(Guid.NewGuid()));
}
