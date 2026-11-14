using E2eShop.Api.Domain.Notes;
using E2eShop.Api.Infrastructure.Authorization;
using E2eShop.Api.Infrastructure.Endpoints;
using E2eShop.Api.Infrastructure.Persistence;
using E2eShop.Api.Infrastructure.RateLimiting;

namespace E2eShop.Api.Features.Notes.DeleteNote;

public sealed class DeleteNoteHandler(IApplicationDbContext dbContext, ICurrentUser currentUser, TimeProvider timeProvider)
{
    public async Task<Result> HandleAsync(Guid id, CancellationToken cancellationToken)
    {
        var note = await dbContext.Notes
            .FirstOrDefaultAsync(n => n.Id == id && n.OwnerId == currentUser.UserId && !n.IsDeleted, cancellationToken);
        if (note is null)
        {
            return NoteErrors.NotFound(id);
        }

        note.MarkAsDeleted(currentUser.UserId, timeProvider.GetUtcNow().UtcDateTime);
        await dbContext.SaveChangesAsync(cancellationToken);
        return Result.Success();
    }
}

public sealed class DeleteNoteEndpoint : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app) =>
        app.MapDelete("/notes/{id:guid}", async (Guid id, DeleteNoteHandler handler, CancellationToken ct) =>
                (await handler.HandleAsync(id, ct)).ToHttpResult())
            .RequireAuthorization(AuthorizationPolicies.Admin)
            .RequireRateLimiting(RateLimitPolicies.Write);
}
