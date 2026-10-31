using System;
using System.Linq;
using Church.Core;
using Church.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace Church.Tests
{
    public class DummyMultiTenantEntity : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid TenantId { get; set; }
        public string Name { get; set; }
    }

    public class TestDbContext : ApplicationDbContext
    {
        public TestDbContext(DbContextOptions<ApplicationDbContext> options, ITenantService tenantService) : base(options, tenantService)
        {
        }

        public DbSet<DummyMultiTenantEntity> DummyEntities { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // Register dummy entity for testing purposes
            modelBuilder.Entity<DummyMultiTenantEntity>(entity =>
            {
                entity.HasKey(e => e.Id);
            });
        }
    }

    public class MockTenantService : ITenantService
    {
        public Guid CurrentTenantId { get; set; }

        public Guid GetCurrentTenantId()
        {
            return CurrentTenantId;
        }
    }

    public class DbContextTests
    {
        private readonly Guid _tenantId1 = Guid.NewGuid();
        private readonly Guid _tenantId2 = Guid.NewGuid();

        private TestDbContext GetDbContext(Guid tenantId)
        {
            var options = new DbContextOptionsBuilder<ApplicationDbContext>()
                .UseInMemoryDatabase(databaseName: "ChurchTestDatabase")
                .Options;

            var tenantService = new MockTenantService { CurrentTenantId = tenantId };
            return new TestDbContext(options, tenantService);
        }

        [Fact]
        public void TenantQueryFilter_FiltersCorrectly()
        {
            // Arrange: Create database and seed data from the perspective of Tenant 1
            using (var context = GetDbContext(_tenantId1))
            {
                context.Database.EnsureDeleted();
                context.Database.EnsureCreated();

                context.DummyEntities.Add(new DummyMultiTenantEntity { Id = Guid.NewGuid(), TenantId = _tenantId1, Name = "Tenant 1 Entity A" });
                context.DummyEntities.Add(new DummyMultiTenantEntity { Id = Guid.NewGuid(), TenantId = _tenantId1, Name = "Tenant 1 Entity B" });

                // Add an entity for Tenant 2 manually bypassing the query filter implicitly by tracking, but it will be filtered on subsequent queries
                context.DummyEntities.Add(new DummyMultiTenantEntity { Id = Guid.NewGuid(), TenantId = _tenantId2, Name = "Tenant 2 Entity C" });
                context.SaveChanges();
            }

            // Act & Assert: Query from perspective of Tenant 1
            using (var context = GetDbContext(_tenantId1))
            {
                var entities = context.DummyEntities.ToList();
                Assert.Equal(2, entities.Count);
                Assert.All(entities, e => Assert.Equal(_tenantId1, e.TenantId));
            }

            // Act & Assert: Query from perspective of Tenant 2
            using (var context = GetDbContext(_tenantId2))
            {
                var entities = context.DummyEntities.ToList();
                Assert.Single(entities);
                Assert.Equal(_tenantId2, entities.First().TenantId);
            }
        }

        [Fact]
        public void TenantModel_Creation()
        {
            var tenant = new Tenant
            {
                Id = Guid.NewGuid(),
                Name = "Test Church",
                Slug = "test-church",
                ContactEmail = "contact@testchurch.com",
                LogoUrl = "http://example.com/logo.png",
                CreatedAt = DateTime.UtcNow,
                Status = "Active"
            };

            Assert.NotNull(tenant);
            Assert.Equal("Test Church", tenant.Name);
            Assert.Equal("test-church", tenant.Slug);
        }
    }
}
