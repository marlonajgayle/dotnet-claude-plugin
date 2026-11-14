namespace E2eShop.Api.Domain.Notes;

public sealed class Note : AggregateRoot<Guid>
{
    private Note(Guid id, string ownerId, string title)
        : base(id)
    {
        OwnerId = ownerId;
        Title = title;
    }

    private Note()
    {
    }

    public string OwnerId { get; private set; } = null!;

    public string Title { get; private set; } = null!;

    public int Views { get; private set; }

    public static Note Create(string ownerId, string title)
    {
        var note = new Note(Guid.CreateVersion7(), ownerId, title);
        note.Raise(new NoteCreated(note.Id));
        return note;
    }

    public void RecordView() => Views++;
}

public sealed record NoteCreated(Guid NoteId) : IDomainEvent;

public static class NoteErrors
{
    public static Error NotFound(Guid id) => Error.NotFound("Note.NotFound", $"Note '{id}' was not found.");
}
