using Microsoft.EntityFrameworkCore.Metadata.Builders;
using E2eShop.Api.Domain.Notes;

namespace E2eShop.Api.Infrastructure.Persistence.Configurations;

internal sealed class NoteConfiguration : IEntityTypeConfiguration<Note>
{
    public void Configure(EntityTypeBuilder<Note> builder)
    {
        builder.ToTable("Notes");
        builder.HasKey(note => note.Id);
        builder.Property(note => note.Id).ValueGeneratedNever();
        builder.Property(note => note.OwnerId).HasMaxLength(200).IsRequired();
        builder.Property(note => note.Title).HasMaxLength(200).IsRequired();
        builder.Property(note => note.CreatedBy).HasMaxLength(200);
        builder.Property(note => note.ModifiedBy).HasMaxLength(200);
        builder.Property(note => note.DeletedBy).HasMaxLength(200);
        builder.Property(note => note.IsDeleted).IsRequired().HasDefaultValue(false);
        builder.HasIndex(note => note.OwnerId).HasFilter("[IsDeleted] = 0");
    }
}
