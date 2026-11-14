#!/usr/bin/env bash
# Eval workspace: a small vertical-slice API in a git repo, on a feature branch, so prompts about
# "this project" have something real to point at. claude plugin eval runs it in the empty workspace
# only with --scaffold. Each case's workspace.sh is a copy of this file (tests/test-static.sh checks
# they match), because a case may only name a script inside its own directory.
set -eu
api=src/Shop.Api
mkdir -p "$api/Domain" "$api/Features/Orders/CreateOrder" "$api/Features/Orders/CancelOrder" "$api/Infrastructure/Outbox"
cat > Shop.slnx <<'X'
<Solution><Project Path="src/Shop.Api/Shop.Api.csproj" /></Solution>
X
cat > "$api/Shop.Api.csproj" <<'X'
<Project Sdk="Microsoft.NET.Sdk.Web"><PropertyGroup><TargetFramework>net10.0</TargetFramework><Nullable>enable</Nullable><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>
X
cat > "$api/Program.cs" <<'X'
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRateLimiter(_ => { });
// Orders
builder.Services.AddScoped<CreateOrderHandler>();
var app = builder.Build();
app.MapHealthChecks("/health");
app.Run();
X
cat > "$api/Domain/Order.cs" <<'X'
namespace Shop.Api.Domain;
public sealed class Order : AggregateRoot<Guid>
{
    public string CustomerId { get; private set; } = null!;
    public DateTime PlacedOnUtc { get; private set; }
    public bool IsDeleted { get; private set; }
}
public sealed record OrderCreated(Guid OrderId) : IDomainEvent;
public static class OrderErrors
{
    public static Error NotFound(Guid id) => Error.NotFound("Order.NotFound", $"Order '{id}' was not found.");
}
X
cat > "$api/Features/Orders/CreateOrder/CreateOrderHandler.cs" <<'X'
namespace Shop.Api.Features.Orders.CreateOrder;
public sealed record CreateOrderCommand(string CustomerId);
public sealed class CreateOrderHandler(IApplicationDbContext db)
{
    public async Task<Result<Guid>> HandleAsync(CreateOrderCommand command, CancellationToken ct) => Guid.NewGuid();
}
X
cat > "$api/Features/Orders/CreateOrder/CreateOrderEndpoint.cs" <<'X'
namespace Shop.Api.Features.Orders.CreateOrder;
public sealed class CreateOrderEndpoint : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app) =>
        app.MapPost("/orders", (CreateOrderCommand c, CreateOrderHandler h, CancellationToken ct) => h.HandleAsync(c, ct))
            .RequireAuthorization(AuthorizationPolicies.User).RequireRateLimiting(RateLimitPolicies.Write);
}
X
cat > "$api/Features/Orders/CancelOrder/CancelOrderHandler.cs" <<'X'
namespace Shop.Api.Features.Orders.CancelOrder;
public sealed record CancelOrderCommand(Guid OrderId);
public sealed class CancelOrderHandler(IApplicationDbContext db)
{
    public async Task<Result> HandleAsync(CancelOrderCommand command, CancellationToken ct) => Result.Success();
}
X
cat > "$api/Infrastructure/Outbox/OutboxProcessor.cs" <<'X'
namespace Shop.Api.Infrastructure.Outbox;
public static class OutboxDispatcher
{
    public static bool Dispatch(OutboxMessage message) => message.Type == nameof(OrderCreated);
}
X
git init -q
git symbolic-ref HEAD refs/heads/main
git add -A
git -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false commit -q -m "chore: initial"
git checkout -q -b feature/cancel-order
