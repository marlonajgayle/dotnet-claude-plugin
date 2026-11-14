using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using E2eShop.Api.Features.Notes.GetNote;
using E2eShop.Api.IntegrationTests.Infrastructure;

namespace E2eShop.Api.IntegrationTests.Features.Notes;

[Collection(ApiCollection.Name)]
[Trait("Category", "Integration")]
public sealed class NotesEndpointTests(ApiFactory api)
{
    [Fact]
    public async Task CreateNote_Anonymous_Returns401()
    {
        var response = await api.CreateAnonymousClient().PostAsJsonAsync("/notes", new { Title = "x" });
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task CreateNote_EmptyTitle_Returns400WithFieldError()
    {
        var response = await api.CreateClientAs(NewUser()).PostAsJsonAsync("/notes", new { Title = "" });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("Title", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task CreateNote_ThenGet_ReturnsNoteWithUtcDate()
    {
        var client = api.CreateClientAs(NewUser());
        var id = await CreateNoteAsync(client, "Groceries");

        var note = await client.GetFromJsonAsync<NoteResponse>($"/notes/{id}");
        Assert.NotNull(note);
        Assert.Equal("Groceries", note.Title);
        Assert.Equal(DateTimeKind.Utc, note.CreatedOnUtc.Kind);
    }

    [Fact]
    public async Task GetNote_OtherUsersNote_Returns404()
    {
        var id = await CreateNoteAsync(api.CreateClientAs(NewUser()), "Private");

        var response = await api.CreateClientAs(NewUser()).GetAsync($"/notes/{id}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task DeleteNote_WithoutAdminRole_Returns403()
    {
        var user = NewUser();
        var id = await CreateNoteAsync(api.CreateClientAs(user), "Mine");

        var response = await api.CreateClientAs(user).DeleteAsync($"/notes/{id}");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task DeleteNote_AsAdminOwner_SoftDeletesAndHidesIt()
    {
        var user = NewUser();
        var client = api.CreateClientAs(user, "admin");
        var id = await CreateNoteAsync(client, "Old");

        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/notes/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/notes/{id}")).StatusCode);

        var row = await api.WithDbContextAsync(db => db.Notes.AsNoTracking().SingleAsync(n => n.Id == id));
        Assert.True(row.IsDeleted);
        Assert.Equal(user, row.DeletedBy);
    }

    [Fact]
    public async Task CreateNote_RaisesNoteCreated_WhichTheOutboxDispatches()
    {
        var client = api.CreateClientAs(NewUser());
        var id = await CreateNoteAsync(client, "Evented");

        await api.ProcessOutboxAsync();

        var message = await api.WithDbContextAsync(db =>
            db.OutboxMessages.AsNoTracking().SingleAsync(m => m.Type == "NoteCreated" && m.Payload.Contains(id.ToString())));
        Assert.NotNull(message.ProcessedOnUtc);
        Assert.Null(message.Error);
        Assert.Equal(1, (await client.GetFromJsonAsync<NoteResponse>($"/notes/{id}"))!.Views);
    }

    private static string NewUser() => $"user-{Guid.NewGuid():N}";

    private static async Task<Guid> CreateNoteAsync(HttpClient client, string title)
    {
        var response = await client.PostAsJsonAsync("/notes", new { Title = title });
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<Guid>();
    }
}
