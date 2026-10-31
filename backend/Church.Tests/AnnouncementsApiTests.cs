using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Church.Tests
{
    public class CustomWebApplicationFactory : WebApplicationFactory<Program>
    {
        private readonly string _dbName = "TestDb_" + Guid.NewGuid().ToString();

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.ConfigureServices(services =>
            {
                // Remove all DbContext related registrations (options, context, provider services)
                var descriptors = services.Where(d =>
                    d.ServiceType == typeof(DbContextOptions<ApplicationDbContext>) ||
                    d.ServiceType == typeof(DbContextOptions) ||
                    d.ServiceType == typeof(ApplicationDbContext) ||
                    d.ServiceType.Namespace?.StartsWith("Microsoft.EntityFrameworkCore") == true ||
                    d.ServiceType.Namespace?.StartsWith("Npgsql.EntityFrameworkCore") == true
                ).ToList();

                foreach (var descriptor in descriptors)
                {
                    services.Remove(descriptor);
                }

                // Register In-Memory DbContext with its own internal service provider
                services.AddDbContext<ApplicationDbContext>(options =>
                {
                    options.UseInMemoryDatabase(_dbName);
                });
            });
        }
    }

    public class AnnouncementsApiTests : IClassFixture<CustomWebApplicationFactory>
    {
        private readonly CustomWebApplicationFactory _factory;
        private readonly Guid _tenantChurch1 = Guid.NewGuid();
        private readonly Guid _tenantChurch2 = Guid.NewGuid();

        public AnnouncementsApiTests(CustomWebApplicationFactory factory)
        {
            _factory = factory;
        }

        private void SeedAnnouncements(Guid churchId, List<Announcement> announcements)
        {
            using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            foreach (var announcement in announcements)
            {
                announcement.ChurchId = churchId;
                db.Announcements.Add(announcement);
            }
            db.SaveChanges();
        }

        [Fact]
        public async Task Scenario1_MemberViewsFeed_ReturnsReverseChronologicalListWithPriority()
        {
            // Given an authenticated church member
            var churchId = Guid.NewGuid();
            var authorId = Guid.NewGuid();

            var announcement1 = new Announcement
            {
                Id = Guid.NewGuid(),
                ChurchId = churchId,
                AuthorId = authorId,
                Title = "First Notice (Routine)",
                Content = "This is a routine notice.",
                Priority = AnnouncementPriority.Routine,
                PublishedAt = DateTime.UtcNow.AddHours(-2)
            };

            var announcement2 = new Announcement
            {
                Id = Guid.NewGuid(),
                ChurchId = churchId,
                AuthorId = authorId,
                Title = "Second Notice (Urgent)",
                Content = "This is an urgent announcement.",
                Priority = AnnouncementPriority.Urgent,
                PublishedAt = DateTime.UtcNow.AddHours(-1)
            };

            var announcement3 = new Announcement
            {
                Id = Guid.NewGuid(),
                ChurchId = churchId,
                AuthorId = authorId,
                Title = "Third Notice (Emergency)",
                Content = "This is an emergency announcement.",
                Priority = AnnouncementPriority.Emergency,
                PublishedAt = DateTime.UtcNow
            };

            SeedAnnouncements(churchId, new List<Announcement> { announcement1, announcement2, announcement3 });

            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // When the announcement list loads (GET /api/v1/announcements)
            var response = await client.GetAsync("/api/v1/announcements");
            var errorBody = await response.Content.ReadAsStringAsync();

            // Then notices appear in reverse-chronological order, flagged by priority
            Assert.True(response.IsSuccessStatusCode, $"Request failed with status {response.StatusCode} and body: {errorBody}");
            var feed = await response.Content.ReadFromJsonAsync<List<AnnouncementResponse>>();
            Assert.NotNull(feed);
            Assert.True(feed.Count >= 3);

            // Filter for the announcements of this test
            var testFeed = feed.Where(a => a.ChurchId == churchId).ToList();
            Assert.Equal(3, testFeed.Count);

            // Verify reverse-chronological order: announcement3 (most recent), then 2, then 1
            Assert.Equal(announcement3.Id, testFeed[0].Id);
            Assert.Equal(AnnouncementPriority.Emergency, testFeed[0].Priority);

            Assert.Equal(announcement2.Id, testFeed[1].Id);
            Assert.Equal(AnnouncementPriority.Urgent, testFeed[1].Priority);

            Assert.Equal(announcement1.Id, testFeed[2].Id);
            Assert.Equal(AnnouncementPriority.Routine, testFeed[2].Priority);
        }

        [Fact]
        public async Task Scenario2_StandardMember_PostAnnouncement_Returns403Forbidden()
        {
            // Given a standard church member
            var churchId = Guid.NewGuid();
            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var payload = new CreateAnnouncementRequest(
                Title: "Member unauthorized announcement",
                Content: "Trying to post without permissions.",
                Priority: AnnouncementPriority.Routine
            );

            // When they attempt to POST an announcement
            var response = await client.PostAsJsonAsync("/api/v1/announcements", payload);

            // Then the API returns 403 Forbidden
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }

        [Fact]
        public async Task Scenario2_AdminOrPastor_CanPublishAnnouncement_Returns201Created()
        {
            var churchId = Guid.NewGuid();

            // Test Pastor role
            var pastorClient = _factory.CreateClient();
            pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");
            pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var pastorPayload = new CreateAnnouncementRequest(
                Title: "Pastoral Weekly Update",
                Content: "Sunday service will begin at 9:00 AM.",
                Priority: AnnouncementPriority.Routine
            );

            var pastorResponse = await pastorClient.PostAsJsonAsync("/api/v1/announcements", pastorPayload);
            Assert.Equal(HttpStatusCode.Created, pastorResponse.StatusCode);
            var pastorCreated = await pastorResponse.Content.ReadFromJsonAsync<AnnouncementResponse>();
            Assert.NotNull(pastorCreated);
            Assert.Equal("Pastoral Weekly Update", pastorCreated.Title);
            Assert.Equal(AnnouncementPriority.Routine, pastorCreated.Priority);
            Assert.Equal(churchId, pastorCreated.ChurchId);

            // Test Admin role
            var adminClient = _factory.CreateClient();
            adminClient.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            adminClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var adminPayload = new CreateAnnouncementRequest(
                Title: "Severe Weather Cancellation",
                Content: "Evening gathering cancelled due to storm.",
                Priority: AnnouncementPriority.Emergency
            );

            var adminResponse = await adminClient.PostAsJsonAsync("/api/v1/announcements", adminPayload);
            Assert.Equal(HttpStatusCode.Created, adminResponse.StatusCode);
            var adminCreated = await adminResponse.Content.ReadFromJsonAsync<AnnouncementResponse>();
            Assert.NotNull(adminCreated);
            Assert.Equal("Severe Weather Cancellation", adminCreated.Title);
            Assert.Equal(AnnouncementPriority.Emergency, adminCreated.Priority);
            Assert.Equal(churchId, adminCreated.ChurchId);
        }

        [Fact]
        public async Task UnauthenticatedUser_Returns401Unauthorized()
        {
            var client = _factory.CreateClient();
            // No auth headers
            var getResponse = await client.GetAsync("/api/v1/announcements");
            Assert.Equal(HttpStatusCode.Unauthorized, getResponse.StatusCode);

            var postResponse = await client.PostAsJsonAsync("/api/v1/announcements", new CreateAnnouncementRequest("Test", "Content"));
            Assert.Equal(HttpStatusCode.Unauthorized, postResponse.StatusCode);
        }

        [Fact]
        public async Task TenantIsolation_AnnouncementsFilteredByChurchId()
        {
            var church1 = Guid.NewGuid();
            var church2 = Guid.NewGuid();

            SeedAnnouncements(church1, new List<Announcement>
            {
                new Announcement
                {
                    Id = Guid.NewGuid(),
                    ChurchId = church1,
                    AuthorId = Guid.NewGuid(),
                    Title = "Church 1 Notice",
                    Content = "Only for Church 1",
                    Priority = AnnouncementPriority.Routine,
                    PublishedAt = DateTime.UtcNow
                }
            });

            SeedAnnouncements(church2, new List<Announcement>
            {
                new Announcement
                {
                    Id = Guid.NewGuid(),
                    ChurchId = church2,
                    AuthorId = Guid.NewGuid(),
                    Title = "Church 2 Notice",
                    Content = "Only for Church 2",
                    Priority = AnnouncementPriority.Routine,
                    PublishedAt = DateTime.UtcNow
                }
            });

            var client1 = _factory.CreateClient();
            client1.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client1.DefaultRequestHeaders.Add("X-Tenant-Id", church1.ToString());

            var response1 = await client1.GetAsync("/api/v1/announcements");
            var announcements1 = await response1.Content.ReadFromJsonAsync<List<AnnouncementResponse>>();
            Assert.NotNull(announcements1);
            Assert.All(announcements1, a => Assert.Equal(church1, a.ChurchId));
            Assert.Contains(announcements1, a => a.Title == "Church 1 Notice");
            Assert.DoesNotContain(announcements1, a => a.Title == "Church 2 Notice");
        }
    }
}
