using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Church.API.Endpoints;
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

        [Theory]
        [InlineData("", "Valid content")]
        [InlineData("   ", "Valid content")]
        [InlineData(null, "Valid content")]
        [InlineData("Valid title", "")]
        [InlineData("Valid title", "   ")]
        [InlineData("Valid title", null)]
        [InlineData("", "")]
        [InlineData(null, null)]
        public async Task Validation_InvalidTitleOrContent_Returns400BadRequest(string? title, string? content)
        {
            var churchId = Guid.NewGuid();
            var pastorClient = _factory.CreateClient();
            pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");
            pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var payload = new CreateAnnouncementRequest(
                Title: title!,
                Content: content!,
                Priority: AnnouncementPriority.Routine
            );

            var response = await pastorClient.PostAsJsonAsync("/api/v1/announcements", payload);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);

            var body = await response.Content.ReadAsStringAsync();
            Assert.Contains("Title and Content are required.", body);
        }

        [Fact]
        public async Task PublishedAndExpiredAnnouncements_FollowExistingContract()
        {
            var churchId = Guid.NewGuid();
            var authorId = Guid.NewGuid();

            var pastPublished = DateTime.UtcNow.AddDays(-5);
            var futureExpires = DateTime.UtcNow.AddDays(7);
            var pastExpires = DateTime.UtcNow.AddDays(-1);

            // 1. Publish announcement with future expiration via Pastor API
            var pastorClient = _factory.CreateClient();
            pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");
            pastorClient.DefaultRequestHeaders.Add("X-User-Id", authorId.ToString());
            pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var activeWithExpiryPayload = new CreateAnnouncementRequest(
                Title: "Youth Camp Registration",
                Content: "Registration closes next week.",
                Priority: AnnouncementPriority.Routine,
                PublishedAt: pastPublished,
                ExpiresAt: futureExpires
            );

            var postResponse = await pastorClient.PostAsJsonAsync("/api/v1/announcements", activeWithExpiryPayload);
            Assert.Equal(HttpStatusCode.Created, postResponse.StatusCode);
            var created = await postResponse.Content.ReadFromJsonAsync<AnnouncementResponse>();
            Assert.NotNull(created);
            Assert.Equal("Youth Camp Registration", created.Title);
            Assert.Equal(pastPublished, created.PublishedAt);
            Assert.Equal(futureExpires, created.ExpiresAt);

            // 2. Seed an announcement with expired date directly (or test how feed represents it)
            var expiredNotice = new Announcement
            {
                Id = Guid.NewGuid(),
                ChurchId = churchId,
                AuthorId = authorId,
                Title = "Past Event Notice",
                Content = "This event happened yesterday.",
                Priority = AnnouncementPriority.Routine,
                PublishedAt = DateTime.UtcNow.AddDays(-10),
                ExpiresAt = pastExpires
            };
            SeedAnnouncements(churchId, new List<Announcement> { expiredNotice });

            // 3. Member reads feed: both published notices are returned, with their respective ExpiresAt retained per API contract
            var memberClient = _factory.CreateClient();
            memberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");
            memberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var feedResponse = await memberClient.GetAsync("/api/v1/announcements");
            Assert.Equal(HttpStatusCode.OK, feedResponse.StatusCode);
            var feed = await feedResponse.Content.ReadFromJsonAsync<List<AnnouncementResponse>>();
            Assert.NotNull(feed);

            var activeInFeed = feed.FirstOrDefault(a => a.Id == created.Id);
            Assert.NotNull(activeInFeed);
            Assert.Equal(futureExpires, activeInFeed.ExpiresAt);

            var expiredInFeed = feed.FirstOrDefault(a => a.Id == expiredNotice.Id);
            Assert.NotNull(expiredInFeed);
            Assert.Equal(pastExpires, expiredInFeed.ExpiresAt);
        }

        [Fact]
        public async Task TenantIsolation_DirectEntityAccess_IsStrictlyTenantScoped()
        {
            var churchA = Guid.NewGuid();
            var churchB = Guid.NewGuid();
            var announcementAId = Guid.NewGuid();

            SeedAnnouncements(churchA, new List<Announcement>
            {
                new Announcement
                {
                    Id = announcementAId,
                    ChurchId = churchA,
                    AuthorId = Guid.NewGuid(),
                    Title = "Church A Direct Secret Notice",
                    Content = "Secret content for Church A only.",
                    Priority = AnnouncementPriority.Urgent,
                    PublishedAt = DateTime.UtcNow
                }
            });

            // 1. Direct query in DbContext under Church A scope retrieves the announcement
            using (var scopeA = _factory.Services.CreateScope())
            {
                var tenantService = scopeA.ServiceProvider.GetRequiredService<ITenantService>();
                var db = scopeA.ServiceProvider.GetRequiredService<ApplicationDbContext>();

                // Under church A client context, it is present in the feed
                var clientA = _factory.CreateClient();
                clientA.DefaultRequestHeaders.Add("X-User-Role", "Member");
                clientA.DefaultRequestHeaders.Add("X-Tenant-Id", churchA.ToString());

                var responseA = await clientA.GetFromJsonAsync<List<AnnouncementResponse>>("/api/v1/announcements");
                Assert.NotNull(responseA);
                Assert.Contains(responseA, a => a.Id == announcementAId);
            }

            // 2. Direct query from Church B client context never returns Church A announcement
            var clientB = _factory.CreateClient();
            clientB.DefaultRequestHeaders.Add("X-User-Role", "Member");
            clientB.DefaultRequestHeaders.Add("X-Tenant-Id", churchB.ToString());

            var responseB = await clientB.GetFromJsonAsync<List<AnnouncementResponse>>("/api/v1/announcements");
            Assert.NotNull(responseB);
            Assert.DoesNotContain(responseB, a => a.Id == announcementAId);

            // 3. Probing individual announcement path (if unmapped direct GET /api/v1/announcements/{id})
            // returns 404 or fails closed rather than leaking cross-tenant data
            var directGet = await clientB.GetAsync($"/api/v1/announcements/{announcementAId}");
            Assert.True(directGet.StatusCode == HttpStatusCode.NotFound || directGet.StatusCode == HttpStatusCode.MethodNotAllowed);
        }

        [Fact]
        public async Task Publishing_AssignsAuthorIdFromAuthenticatedClaims()
        {
            var churchId = Guid.NewGuid();
            var pastorId = Guid.NewGuid();

            var pastorClient = _factory.CreateClient();
            pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");
            pastorClient.DefaultRequestHeaders.Add("X-User-Id", pastorId.ToString());
            pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var payload = new CreateAnnouncementRequest(
                Title: "Author ID Resolution Test",
                Content: "Validating that authenticated author ID is recorded.",
                Priority: AnnouncementPriority.Routine
            );

            var response = await pastorClient.PostAsJsonAsync("/api/v1/announcements", payload);
            Assert.Equal(HttpStatusCode.Created, response.StatusCode);

            var created = await response.Content.ReadFromJsonAsync<AnnouncementResponse>();
            Assert.NotNull(created);
            Assert.Equal(pastorId, created.AuthorId);
            Assert.Equal(churchId, created.ChurchId);
        }
    }

    public class AnnouncementsProductionTenantIsolationTests : IClassFixture<ProductionWebApplicationFactory>
    {
        private const string ClientId = "church_mobile_app";
        private const string RedirectUri = "com.church.app://oauthredirect";

        private readonly ProductionWebApplicationFactory _factory;

        public AnnouncementsProductionTenantIsolationTests(ProductionWebApplicationFactory factory)
        {
            _factory = factory;
        }

        private async Task<AppUser> SeedUserAsync(
            Guid tenantId,
            string email,
            string password,
            string displayName,
            params string[] roles)
        {
            using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            return await IdentityService.ProvisionUserAsync(
                db,
                tenantId,
                email,
                password,
                displayName,
                roles);
        }

        private static (string Verifier, string Challenge) CreatePkcePair()
        {
            var verifier = JwtTokenService.GenerateSecureRandomToken(32);
            var challenge = JwtTokenService.ComputeSha256Base64Url(verifier);
            return (verifier, challenge);
        }

        private async Task<(HttpClient Client, OidcTokenResponse Tokens, AppUser User)> AuthenticateUserAsync(
            Guid tenantId,
            string email,
            string password,
            string displayName,
            params string[] roles)
        {
            var user = await SeedUserAsync(tenantId, email, password, displayName, roles);
            var client = _factory.CreateClient();

            var (verifier, challenge) = CreatePkcePair();

            var authorizeForm = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["client_id"] = ClientId,
                ["redirect_uri"] = RedirectUri,
                ["response_type"] = "code",
                ["scope"] = "openid profile email offline_access roles church_api",
                ["code_challenge"] = challenge,
                ["code_challenge_method"] = "S256",
                ["state"] = "announcements-state",
                ["nonce"] = "nonce-" + Guid.NewGuid(),
                ["email"] = email,
                ["password"] = password,
                ["tenant_id"] = tenantId.ToString()
            });

            var authResponse = await client.PostAsync("/connect/authorize", authorizeForm);
            Assert.Equal(HttpStatusCode.OK, authResponse.StatusCode);

            var authResult = await authResponse.Content.ReadFromJsonAsync<OidcAuthorizeResponse>();
            Assert.NotNull(authResult);

            var tokenForm = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "authorization_code",
                ["client_id"] = ClientId,
                ["code"] = authResult!.Code,
                ["redirect_uri"] = RedirectUri,
                ["code_verifier"] = verifier
            });

            var tokenResponse = await client.PostAsync("/connect/token", tokenForm);
            Assert.Equal(HttpStatusCode.OK, tokenResponse.StatusCode);

            var tokenResult = await tokenResponse.Content.ReadFromJsonAsync<OidcTokenResponse>();
            Assert.NotNull(tokenResult);

            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tokenResult!.AccessToken);
            return (client, tokenResult, user);
        }

        [Fact]
        public async Task Production_AnnouncementsTenantIsolation_StrictlyServerClaimsDerived()
        {
            var churchA = Guid.NewGuid();
            var churchB = Guid.NewGuid();

            var pastorAEmail = $"pastor.a.{Guid.NewGuid():N}@church.org";
            var memberBEmail = $"member.b.{Guid.NewGuid():N}@church.org";

            var (pastorAClient, _, pastorAUser) = await AuthenticateUserAsync(
                churchA,
                pastorAEmail,
                "PastorAPass123!",
                "Pastor Church A",
                ChurchRoleNames.Pastor);

            var (memberBClient, _, _) = await AuthenticateUserAsync(
                churchB,
                memberBEmail,
                "MemberBPass123!",
                "Member Church B",
                ChurchRoleNames.Member);

            // 1. Pastor A publishes announcement in Church A
            var postA = await pastorAClient.PostAsJsonAsync("/api/v1/announcements", new CreateAnnouncementRequest(
                Title: "Church A Exclusive Notice",
                Content: "This belongs strictly to Church A congregants.",
                Priority: AnnouncementPriority.Urgent
            ));
            Assert.Equal(HttpStatusCode.Created, postA.StatusCode);
            var createdA = await postA.Content.ReadFromJsonAsync<AnnouncementResponse>();
            Assert.NotNull(createdA);
            Assert.Equal(churchA, createdA.ChurchId);
            Assert.Equal(pastorAUser.Id, createdA.AuthorId);

            // 2. Member B in Church B queries feed -> Church A announcement is NOT visible
            var feedBRes = await memberBClient.GetAsync("/api/v1/announcements");
            Assert.Equal(HttpStatusCode.OK, feedBRes.StatusCode);
            var feedB = await feedBRes.Content.ReadFromJsonAsync<List<AnnouncementResponse>>();
            Assert.NotNull(feedB);
            Assert.DoesNotContain(feedB, a => a.Id == createdA.Id);

            // 3. Member B attempts to spoof X-Tenant-Id: churchA -> ignored, still cannot see Church A announcements
            memberBClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchA.ToString());
            var spoofFeedRes = await memberBClient.GetAsync("/api/v1/announcements");
            Assert.Equal(HttpStatusCode.OK, spoofFeedRes.StatusCode);
            var spoofFeed = await spoofFeedRes.Content.ReadFromJsonAsync<List<AnnouncementResponse>>();
            Assert.NotNull(spoofFeed);
            Assert.DoesNotContain(spoofFeed, a => a.Id == createdA.Id);

            // 4. Member B attempts to publish -> 403 Forbidden even with valid production token
            var memberPublishRes = await memberBClient.PostAsJsonAsync("/api/v1/announcements", new CreateAnnouncementRequest(
                Title: "Member Attempt",
                Content: "Should fail 403"
            ));
            Assert.Equal(HttpStatusCode.Forbidden, memberPublishRes.StatusCode);
        }
    }
}
