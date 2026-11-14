using Microsoft.EntityFrameworkCore;
using E2eShop.Api.Domain.Notes;
using E2eShop.Api.Features.Notes.CreateNote;
using E2eShop.Api.Features.Notes.GetNote;
using E2eShop.Api.Tests.Infrastructure;

namespace E2eShop.Api.Tests.Features.Notes;

public sealed class NotesHandlerTests : IDisposable
{
    private readonly SqliteDbContextFactory _db = new();

    [Fact]
    public async Task CreateNote_Valid_SavesNoteWithAuditAndOutboxRow()
    {
        var user = TestCurrentUser.New();
        await using var arrange = _db.CreateContext();

        var result = await new CreateNoteHandler(arrange, user, _db.Clock)
            .HandleAsync(new CreateNoteCommand("Groceries"), CancellationToken.None);

        Assert.True(result.IsSuccess);
        await using var assert = _db.CreateContext();
        var note = await assert.Notes.AsNoTracking().SingleAsync(n => n.Id == result.Value);
        Assert.Equal(user.UserId, note.OwnerId);
        Assert.Equal(_db.Clock.GetUtcNow().UtcDateTime, note.CreatedOnUtc);
        var message = await assert.OutboxMessages.AsNoTracking().SingleAsync();
        Assert.Equal(nameof(NoteCreated), message.Type);
    }

    [Fact]
    public async Task GetNote_OtherUsersNote_ReturnsNotFound()
    {
        var id = await CreateAsync(TestCurrentUser.New(), "Private");
        await using var dbContext = _db.CreateContext();

        var result = await new GetNoteHandler(dbContext, TestCurrentUser.New()).HandleAsync(id, CancellationToken.None);

        Assert.True(result.IsFailure);
        Assert.Equal("Note.NotFound", result.Error.Code);
    }

    [Fact]
    public async Task GetNote_Own_ReturnsUtcDate()
    {
        var user = TestCurrentUser.New();
        var id = await CreateAsync(user, "Mine");
        await using var dbContext = _db.CreateContext();

        var result = await new GetNoteHandler(dbContext, user).HandleAsync(id, CancellationToken.None);

        Assert.True(result.IsSuccess);
        Assert.Equal(DateTimeKind.Utc, result.Value.CreatedOnUtc.Kind);
    }

    public void Dispose() => _db.Dispose();

    private async Task<Guid> CreateAsync(TestCurrentUser user, string title)
    {
        await using var dbContext = _db.CreateContext();
        var result = await new CreateNoteHandler(dbContext, user, _db.Clock)
            .HandleAsync(new CreateNoteCommand(title), CancellationToken.None);
        return result.Value;
    }
}
