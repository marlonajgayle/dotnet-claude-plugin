using E2eShop.Api.Domain.Notes;
using E2eShop.Api.Infrastructure.Authorization;
using E2eShop.Api.Infrastructure.Endpoints;
using E2eShop.Api.Infrastructure.Persistence;
using E2eShop.Api.Infrastructure.RateLimiting;

namespace E2eShop.Api.Features.Notes.GetNote;

public sealed record NoteResponse(Guid Id, string Title, int Views, DateTime CreatedOnUtc);

public sealed class GetNoteHandler(IApplicationDbContext dbContext, ICurrentUser currentUser)
{
    public async Task<Result<NoteResponse>> HandleAsync(Guid id, CancellationToken cancellationToken)
    {
        var note = await dbContext.Notes.AsNoTracking()
            .Where(n => n.Id == id && n.OwnerId == currentUser.UserId && !n.IsDeleted)
            .Select(n => new NoteResponse(n.Id, n.Title, n.Views, DateTime.SpecifyKind(n.CreatedOnUtc, DateTimeKind.Utc)))
            .FirstOrDefaultAsync(cancellationToken);
        return note is null ? NoteErrors.NotFound(id) : note;
    }
}

public sealed class GetNoteEndpoint : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app) =>
        app.MapGet("/notes/{id:guid}", async (Guid id, GetNoteHandler handler, CancellationToken ct) =>
                (await handler.HandleAsync(id, ct)).ToHttpResult())
            .RequireAuthorization(AuthorizationPolicies.User)
            .RequireRateLimiting(RateLimitPolicies.Read);
}
