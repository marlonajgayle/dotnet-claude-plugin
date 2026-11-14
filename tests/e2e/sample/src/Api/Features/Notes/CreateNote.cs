using FluentValidation;
using E2eShop.Api.Domain.Notes;
using E2eShop.Api.Infrastructure.Authorization;
using E2eShop.Api.Infrastructure.Endpoints;
using E2eShop.Api.Infrastructure.Persistence;
using E2eShop.Api.Infrastructure.RateLimiting;

namespace E2eShop.Api.Features.Notes.CreateNote;

public sealed record CreateNoteCommand(string Title);

public sealed class CreateNoteValidator : AbstractValidator<CreateNoteCommand>
{
    public CreateNoteValidator() => RuleFor(command => command.Title).NotEmpty().MaximumLength(200);
}

public sealed class CreateNoteHandler(IApplicationDbContext dbContext, ICurrentUser currentUser, TimeProvider timeProvider)
{
    public async Task<Result<Guid>> HandleAsync(CreateNoteCommand command, CancellationToken cancellationToken)
    {
        var note = Note.Create(currentUser.UserId!, command.Title);
        note.SetCreatedAuditInfo(currentUser.UserId, timeProvider.GetUtcNow().UtcDateTime);
        dbContext.Notes.Add(note);
        await dbContext.SaveChangesAsync(cancellationToken);
        return note.Id;
    }
}

public sealed class NoteCreatedHandler(IApplicationDbContext dbContext) : IDomainEventHandler<NoteCreated>
{
    public async Task HandleAsync(NoteCreated domainEvent, CancellationToken cancellationToken)
    {
        var note = await dbContext.Notes.FirstAsync(n => n.Id == domainEvent.NoteId, cancellationToken);
        note.RecordView();
        await dbContext.SaveChangesAsync(cancellationToken);
    }
}

public sealed class CreateNoteEndpoint : IEndpoint
{
    public void MapEndpoint(IEndpointRouteBuilder app) =>
        app.MapPost("/notes", async (CreateNoteCommand command, CreateNoteHandler handler, CancellationToken ct) =>
                (await handler.HandleAsync(command, ct)).ToHttpResult())
            .WithValidation<CreateNoteCommand>()
            .RequireAuthorization(AuthorizationPolicies.User)
            .RequireRateLimiting(RateLimitPolicies.Write);
}
