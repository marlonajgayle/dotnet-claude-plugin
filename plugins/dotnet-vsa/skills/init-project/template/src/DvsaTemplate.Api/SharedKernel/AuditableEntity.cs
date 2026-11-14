namespace DvsaTemplate.Api.SharedKernel;

/// <summary>
/// An entity with audit fields and soft delete. Handlers call the audit setters on every write and
/// MarkAsDeleted instead of removing rows; reads filter !IsDeleted.
/// </summary>
public abstract class AuditableEntity<TId> : BaseEntity<TId>
    where TId : notnull
{
    protected AuditableEntity(TId id)
        : base(id)
    {
    }

    // For EF Core.
    protected AuditableEntity()
    {
    }

    public DateTime CreatedOnUtc { get; private set; }

    public string? CreatedBy { get; private set; }

    public DateTime? ModifiedOnUtc { get; private set; }

    public string? ModifiedBy { get; private set; }

    public bool IsDeleted { get; private set; }

    public DateTime? DeletedOnUtc { get; private set; }

    public string? DeletedBy { get; private set; }

    public void SetCreatedAuditInfo(string? userId, DateTime utcNow)
    {
        CreatedBy = userId;
        CreatedOnUtc = utcNow;
    }

    public void SetModifiedAuditInfo(string? userId, DateTime utcNow)
    {
        ModifiedBy = userId;
        ModifiedOnUtc = utcNow;
    }

    public void MarkAsDeleted(string? userId, DateTime utcNow)
    {
        IsDeleted = true;
        DeletedBy = userId;
        DeletedOnUtc = utcNow;
        SetModifiedAuditInfo(userId, utcNow);
    }
}
