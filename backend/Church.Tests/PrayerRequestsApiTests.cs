using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Church.Tests
{
    public class PrayerRequestsApiTests : IClassFixture<CustomWebApplicationFactory>
    {
        private readonly CustomWebApplicationFactory _factory;

        public PrayerRequestsApiTests(CustomWebApplicationFactory factory)
        {
            _factory = factory;
        }

        private void SeedPrayerRequests(Guid churchId, List<PrayerRequest> prayerRequests)
        {
            using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            foreach (var request in prayerRequests)
            {
                request.ChurchId = churchId;
                db.PrayerRequests.Add(request);
            }
            db.SaveChanges();
        }

        [Fact]
        public async Task Members_CanSubmitPrayerRequest_And_ViewOwnRequests()
        {
            var churchId = Guid.NewGuid();
            var memberId = Guid.NewGuid();

            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
            client.DefaultRequestHeaders.Add("X-User-Id", memberId.ToString());

            // Submit
            var payload = new CreatePrayerRequestRequest("Please pray for my upcoming surgery.");
            var postResponse = await client.PostAsJsonAsync("/api/v1/prayer-requests", payload);
            Assert.Equal(HttpStatusCode.Created, postResponse.StatusCode);
            var created = await postResponse.Content.ReadFromJsonAsync<PrayerRequestResponse>();
            Assert.NotNull(created);
            Assert.Equal(churchId, created.ChurchId);
            Assert.Equal(memberId, created.MemberId);
            Assert.Equal("Please pray for my upcoming surgery.", created.Content);
            Assert.Equal(PrayerRequestStatus.Submitted, created.Status);

            // View own
            var getResponse = await client.GetAsync("/api/v1/prayer-requests/my");
            Assert.True(getResponse.IsSuccessStatusCode);
            var myRequests = await getResponse.Content.ReadFromJsonAsync<List<PrayerRequestResponse>>();
            Assert.NotNull(myRequests);
            Assert.Single(myRequests);
            Assert.Equal(created.Id, myRequests[0].Id);
        }

        [Fact]
        public async Task AdminsAndMembers_CannotViewOrUpdateAllRequests_Returns403()
        {
            var churchId = Guid.NewGuid();

            // Test Admin
            var adminClient = _factory.CreateClient();
            adminClient.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            adminClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var getResponseAdmin = await adminClient.GetAsync("/api/v1/prayer-requests");
            Assert.Equal(HttpStatusCode.Forbidden, getResponseAdmin.StatusCode);

            var patchResponseAdmin = await adminClient.PatchAsJsonAsync($"/api/v1/prayer-requests/{Guid.NewGuid()}/status", new UpdatePrayerRequestStatusRequest(PrayerRequestStatus.Praying));
            Assert.Equal(HttpStatusCode.Forbidden, patchResponseAdmin.StatusCode);

            // Test Member
            var memberClient = _factory.CreateClient();
            memberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");
            memberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var getResponseMember = await memberClient.GetAsync("/api/v1/prayer-requests");
            Assert.Equal(HttpStatusCode.Forbidden, getResponseMember.StatusCode);

            var patchResponseMember = await memberClient.PatchAsJsonAsync($"/api/v1/prayer-requests/{Guid.NewGuid()}/status", new UpdatePrayerRequestStatusRequest(PrayerRequestStatus.Praying));
            Assert.Equal(HttpStatusCode.Forbidden, patchResponseMember.StatusCode);
        }

        [Fact]
        public async Task Pastor_CanViewAllRequests_AndUpdateStatus()
        {
            var churchId = Guid.NewGuid();
            var memberId = Guid.NewGuid();
            var requestId = Guid.NewGuid();

            SeedPrayerRequests(churchId, new List<PrayerRequest>
            {
                new PrayerRequest
                {
                    Id = requestId,
                    ChurchId = churchId,
                    MemberId = memberId,
                    Content = "Pray for peace.",
                    Status = PrayerRequestStatus.Submitted,
                    CreatedAt = DateTime.UtcNow
                }
            });

            var pastorClient = _factory.CreateClient();
            pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");
            pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // View all
            var getResponse = await pastorClient.GetAsync("/api/v1/prayer-requests");
            Assert.True(getResponse.IsSuccessStatusCode);
            var allRequests = await getResponse.Content.ReadFromJsonAsync<List<PrayerRequestResponse>>();
            Assert.NotNull(allRequests);
            Assert.Contains(allRequests, r => r.Id == requestId);

            // Update status
            var patchResponse = await pastorClient.PatchAsJsonAsync($"/api/v1/prayer-requests/{requestId}/status", new UpdatePrayerRequestStatusRequest(PrayerRequestStatus.Praying));
            Assert.True(patchResponse.IsSuccessStatusCode);

            var updated = await patchResponse.Content.ReadFromJsonAsync<PrayerRequestResponse>();
            Assert.NotNull(updated);
            Assert.Equal(PrayerRequestStatus.Praying, updated.Status);
        }
    }
}
