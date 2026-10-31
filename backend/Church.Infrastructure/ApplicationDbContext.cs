using Church.Core;
using Microsoft.EntityFrameworkCore;
using System;

namespace Church.Infrastructure
{
    public class ApplicationDbContext : DbContext
    {
        private readonly Guid _tenantId;

        public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options, ITenantService tenantService) : base(options)
        {
            _tenantId = tenantService.GetCurrentTenantId();
        }

        public DbSet<Tenant> Tenants { get; set; }
        public DbSet<Announcement> Announcements { get; set; }
        public DbSet<PrayerRequest> PrayerRequests { get; set; }
        public DbSet<Song> Songs { get; set; }
        public DbSet<Setlist> Setlists { get; set; }
        public DbSet<SetlistItem> SetlistItems { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // Configure Tenant entity
            modelBuilder.Entity<Tenant>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.Name).IsRequired().HasMaxLength(255);
                entity.Property(e => e.Slug).IsRequired().HasMaxLength(100);
                entity.HasIndex(e => e.Slug).IsUnique();
                entity.Property(e => e.CreatedAt).HasDefaultValueSql("CURRENT_TIMESTAMP");
            });

            // Configure Announcement entity
            modelBuilder.Entity<Announcement>(entity =>
            {
                entity.ToTable("Announcements");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.Id).HasColumnName("id");
                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();
                entity.Ignore(e => e.ChurchId);
                entity.Property(e => e.AuthorId).HasColumnName("author_id").IsRequired();
                entity.Property(e => e.Title).HasColumnName("title").IsRequired().HasMaxLength(255);
                entity.Property(e => e.Content).HasColumnName("content").IsRequired();
                entity.Property(e => e.Priority).HasColumnName("priority").HasConversion<string>().IsRequired();
                entity.Property(e => e.PublishedAt).HasColumnName("published_at").IsRequired();
                entity.Property(e => e.ExpiresAt).HasColumnName("expires_at");

                entity.HasIndex(e => e.TenantId);
                entity.HasIndex(e => e.PublishedAt);
            });

            // Configure PrayerRequest entity
            modelBuilder.Entity<PrayerRequest>(entity =>
            {
                entity.ToTable("PrayerRequests");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.Id).HasColumnName("id");
                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();
                entity.Ignore(e => e.ChurchId);
                entity.Property(e => e.MemberId).HasColumnName("member_id").IsRequired();
                entity.Property(e => e.Content).HasColumnName("content").IsRequired();
                entity.Property(e => e.Status).HasColumnName("status").HasConversion<string>().IsRequired();
                entity.Property(e => e.CreatedAt).HasColumnName("created_at").HasDefaultValueSql("CURRENT_TIMESTAMP");
                entity.Property(e => e.UpdatedAt).HasColumnName("updated_at").HasDefaultValueSql("CURRENT_TIMESTAMP");

                entity.HasIndex(e => e.TenantId);
                entity.HasIndex(e => e.MemberId);
            });

            // Configure Song entity
            modelBuilder.Entity<Song>(entity =>
            {
                entity.ToTable("Songs");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.Id).HasColumnName("id");
                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();
                entity.Ignore(e => e.ChurchId);
                entity.Property(e => e.Title).HasColumnName("title").IsRequired().HasMaxLength(255);
                entity.Property(e => e.Artist).HasColumnName("artist").HasMaxLength(255);
                entity.Property(e => e.DefaultKey).HasColumnName("default_key").HasMaxLength(10);
                entity.Property(e => e.TempoBpm).HasColumnName("tempo_bpm");
                entity.Property(e => e.Lyrics).HasColumnName("lyrics").IsRequired();
                entity.Property(e => e.Chords).HasColumnName("chords").IsRequired();
                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();

                entity.HasIndex(e => e.TenantId);
                entity.HasIndex(e => e.Title);
            });

            // Configure Setlist entity
            modelBuilder.Entity<Setlist>(entity =>
            {
                entity.ToTable("Setlists");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.Id).HasColumnName("id");
                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();
                entity.Ignore(e => e.ChurchId);
                entity.Property(e => e.Title).HasColumnName("title").IsRequired().HasMaxLength(255);
                entity.Property(e => e.ServiceDate).HasColumnName("service_date").IsRequired();
                entity.Property(e => e.Notes).HasColumnName("notes");
                entity.Property(e => e.CreatedAt).HasColumnName("created_at").IsRequired();

                entity.HasIndex(e => e.TenantId);
                entity.HasIndex(e => e.ServiceDate);

                entity.HasMany(e => e.Items)
                    .WithOne(i => i.Setlist!)
                    .HasForeignKey(i => i.SetlistId)
                    .OnDelete(DeleteBehavior.Cascade);
            });

            // Configure SetlistItem entity
            modelBuilder.Entity<SetlistItem>(entity =>
            {
                entity.ToTable("SetlistItems");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.Id).HasColumnName("id");
                entity.Property(e => e.TenantId).HasColumnName("church_id").IsRequired();
                entity.Ignore(e => e.ChurchId);
                entity.Property(e => e.SetlistId).HasColumnName("setlist_id").IsRequired();
                entity.Property(e => e.SongId).HasColumnName("song_id").IsRequired();
                entity.Property(e => e.Order).HasColumnName("order").IsRequired();
                entity.Property(e => e.KeyOverride).HasColumnName("key_override").HasMaxLength(10);
                entity.Property(e => e.Notes).HasColumnName("notes");

                entity.HasIndex(e => e.TenantId);
                entity.HasIndex(e => e.SetlistId);

                entity.HasOne(e => e.Song)
                    .WithMany()
                    .HasForeignKey(e => e.SongId)
                    .OnDelete(DeleteBehavior.Restrict);
            });

            // Apply multi-tenancy filter to all entities implementing IMultiTenantEntity
            foreach (var entityType in modelBuilder.Model.GetEntityTypes())
            {
                if (typeof(IMultiTenantEntity).IsAssignableFrom(entityType.ClrType))
                {
                    modelBuilder.Entity(entityType.ClrType).HasQueryFilter(
                        ConvertFilterExpression<IMultiTenantEntity>(e => e.TenantId == _tenantId, entityType.ClrType)
                    );
                }
            }
        }

        private static System.Linq.Expressions.LambdaExpression ConvertFilterExpression<TInterface>(
            System.Linq.Expressions.Expression<Func<TInterface, bool>> filterExpression, Type entityType)
        {
            var newParam = System.Linq.Expressions.Expression.Parameter(entityType);
            var newBody = ReplacingExpressionVisitor.Replace(filterExpression.Parameters[0], newParam, filterExpression.Body);
            return System.Linq.Expressions.Expression.Lambda(newBody, newParam);
        }
    }

    internal class ReplacingExpressionVisitor : System.Linq.Expressions.ExpressionVisitor
    {
        private readonly System.Linq.Expressions.Expression _oldValue;
        private readonly System.Linq.Expressions.Expression _newValue;

        public ReplacingExpressionVisitor(System.Linq.Expressions.Expression oldValue, System.Linq.Expressions.Expression newValue)
        {
            _oldValue = oldValue;
            _newValue = newValue;
        }

        public override System.Linq.Expressions.Expression Visit(System.Linq.Expressions.Expression node)
        {
            if (node == _oldValue)
                return _newValue;
            return base.Visit(node);
        }

        public static System.Linq.Expressions.Expression Replace(System.Linq.Expressions.Expression oldValue, System.Linq.Expressions.Expression newValue, System.Linq.Expressions.Expression expression)
        {
            return new ReplacingExpressionVisitor(oldValue, newValue).Visit(expression);
        }
    }
}
