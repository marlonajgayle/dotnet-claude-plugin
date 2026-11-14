using DvsaTemplate.Api.Infrastructure.Outbox;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace DvsaTemplate.Api.Infrastructure.Persistence.Configurations;

internal sealed class OutboxMessageConfiguration : IEntityTypeConfiguration<OutboxMessage>
{
    public void Configure(EntityTypeBuilder<OutboxMessage> builder)
    {
        builder.ToTable("OutboxMessages");
        builder.HasKey(message => message.Id);
        builder.Property(message => message.Id).ValueGeneratedNever();
        builder.Property(message => message.Type).HasMaxLength(200).IsRequired();
        builder.Property(message => message.Payload).IsRequired();
        builder.Property(message => message.Error).HasMaxLength(2000);
        builder.HasIndex(message => message.OccurredOnUtc).HasFilter("[ProcessedOnUtc] IS NULL");
    }
}
