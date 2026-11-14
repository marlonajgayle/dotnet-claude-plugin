using DvsaTemplate.Api.Infrastructure.Authorization;

namespace DvsaTemplate.Api.Tests.Infrastructure;

/// <summary>A clock that stands still until a test moves it.</summary>
public sealed class TestClock(DateTimeOffset start) : TimeProvider
{
    private DateTimeOffset _now = start;

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan by) => _now = _now.Add(by);
}

/// <summary>The caller a handler sees. Each test chooses one; null is an anonymous caller.</summary>
public sealed class TestCurrentUser(string? userId) : ICurrentUser
{
    public string? UserId { get; } = userId;

    public bool IsAuthenticated => UserId is not null;

    public static TestCurrentUser New() => new($"user-{Guid.NewGuid():N}");
}
