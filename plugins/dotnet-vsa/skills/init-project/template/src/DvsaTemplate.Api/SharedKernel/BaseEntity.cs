namespace DvsaTemplate.Api.SharedKernel;

public abstract class BaseEntity<TId>
    where TId : notnull
{
    protected BaseEntity(TId id) => Id = id;

    // For EF Core.
    protected BaseEntity()
    {
    }

    public TId Id { get; private init; } = default!;
}
