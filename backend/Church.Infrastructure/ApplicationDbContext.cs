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
