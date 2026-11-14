namespace Fixture.Api.Domain;

public sealed class Order : BaseEntity
{
    public bool IsDeleted { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public List<OrderLine> Lines { get; } = new();
    public Customer Customer { get; set; } = new();
    public Customer? Referrer { get; set; }
}
