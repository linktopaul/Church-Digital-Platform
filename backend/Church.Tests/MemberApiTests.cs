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
    public class MemberApiTests : IClassFixture<CustomWebApplicationFactory>
    {
        private readonly CustomWebApplicationFactory _factory;

        public MemberApiTests(CustomWebApplicationFactory factory)
        {
            _factory = factory;
        }

        private void SeedMember(Guid churchId, Member member)
        {
            using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            member.TenantId = churchId;
            db.Members.Add(member);
            db.SaveChanges();
        }

        private void SeedFamily(Guid churchId, Family family)
        {
            using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            family.TenantId = churchId;
            db.Families.Add(family);
            db.SaveChanges();
        }

        [Fact]
        public async Task Scenario1_SelfProfile_CanGetAndCanUpdate()
        {
            var churchId = Guid.NewGuid();
            var memberId = Guid.NewGuid();

            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-User-Id", memberId.ToString());
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // 1. Initial GET /api/v1/members/me auto-provisions profile with fail-closed private defaults
            var getRes = await client.GetAsync("/api/v1/members/me");
            Assert.Equal(HttpStatusCode.OK, getRes.StatusCode);
            var initialProfile = await getRes.Content.ReadFromJsonAsync<FullMemberProfileResponse>();
            Assert.NotNull(initialProfile);
            Assert.Equal(memberId, initialProfile.Id);
            Assert.Equal(churchId, initialProfile.TenantId);
            Assert.Equal(DirectoryVisibility.Private, initialProfile.DirectoryVisibility);
            Assert.False(initialProfile.ShowPhoneNumber);
            Assert.False(initialProfile.ShowEmail);
            Assert.False(initialProfile.ShowAddress);
            Assert.False(initialProfile.ShowBirthDayAndMonth);

            // 2. PUT /api/v1/members/me updates fields and opts into public visibility
            var updateReq = new UpdateMemberProfileRequest(
                FirstName: "John",
                LastName: "Wesley",
                PhoneNumber: "+15551234567",
                AvatarUrl: "https://example.com/avatar.png",
                DateOfBirth: new DateTime(1985, 6, 17, 0, 0, 0, DateTimeKind.Utc),
                AnniversaryDate: new DateTime(2010, 8, 20, 0, 0, 0, DateTimeKind.Utc),
                Address: "124 Grace Ave",
                DirectoryVisibility: DirectoryVisibility.PublicToMembers,
                ShowPhoneNumber: true,
                ShowEmail: true,
                ShowAddress: false,
                ShowBirthDayAndMonth: true
            );

            var putRes = await client.PutAsJsonAsync("/api/v1/members/me", updateReq);
            Assert.Equal(HttpStatusCode.OK, putRes.StatusCode);
            var updatedProfile = await putRes.Content.ReadFromJsonAsync<FullMemberProfileResponse>();
            Assert.NotNull(updatedProfile);
            Assert.Equal("John", updatedProfile.FirstName);
            Assert.Equal("Wesley", updatedProfile.LastName);
            Assert.Equal("+15551234567", updatedProfile.PhoneNumber);
            Assert.Equal("124 Grace Ave", updatedProfile.Address);
            Assert.Equal(DirectoryVisibility.PublicToMembers, updatedProfile.DirectoryVisibility);
            Assert.False(updatedProfile.ShowAddress);
            Assert.True(updatedProfile.ShowPhoneNumber);
        }

        [Fact]
        public async Task Scenario2_DirectoryPrivacy_RedactsHiddenContactFields()
        {
            var churchId = Guid.NewGuid();
            var memberAId = Guid.NewGuid();
            var memberBId = Guid.NewGuid();

            // Member A with private phone and address, but public email and birthday
            var memberA = new Member
            {
                Id = memberAId,
                TenantId = churchId,
                FirstName = "Alice",
                LastName = "Smith",
                Email = "alice@church.local",
                PhoneNumber = "+15559876543",
                Address = "456 Hidden Road",
                DateOfBirth = new DateTime(1992, 4, 15, 0, 0, 0, DateTimeKind.Utc),
                DirectoryVisibility = DirectoryVisibility.PublicToMembers,
                ShowPhoneNumber = false,
                ShowEmail = true,
                ShowAddress = false,
                ShowBirthDayAndMonth = true
            };
            SeedMember(churchId, memberA);

            // Member B views directory
            var clientB = _factory.CreateClient();
            clientB.DefaultRequestHeaders.Add("X-User-Role", "Member");
            clientB.DefaultRequestHeaders.Add("X-User-Id", memberBId.ToString());
            clientB.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // 1. Directory list
            var listRes = await clientB.GetAsync("/api/v1/members");
            Assert.Equal(HttpStatusCode.OK, listRes.StatusCode);
            var list = await listRes.Content.ReadFromJsonAsync<List<DirectoryMemberResponse>>();
            Assert.NotNull(list);
            var aliceInList = list.FirstOrDefault(m => m.Id == memberAId);
            Assert.NotNull(aliceInList);
            Assert.Equal("Alice Smith", aliceInList.FullName);
            Assert.Equal("alice@church.local", aliceInList.Email);
            Assert.Null(aliceInList.PhoneNumber); // REDACTED
            Assert.Null(aliceInList.Address);     // REDACTED
            Assert.Equal("April 15", aliceInList.BirthdayNotice); // Month & Day only, no year

            // 2. Single member view
            var detailRes = await clientB.GetAsync($"/api/v1/members/{memberAId}");
            Assert.Equal(HttpStatusCode.OK, detailRes.StatusCode);
            var aliceDetail = await detailRes.Content.ReadFromJsonAsync<DirectoryMemberResponse>();
            Assert.NotNull(aliceDetail);
            Assert.Null(aliceDetail.PhoneNumber); // REDACTED
            Assert.Null(aliceDetail.Address);     // REDACTED
            Assert.Equal("alice@church.local", aliceDetail.Email);
        }

        [Fact]
        public async Task Scenario3_DirectoryPrivacy_HidesPrivateAndLeadersOnlyProfiles()
        {
            var churchId = Guid.NewGuid();
            var privateMemberId = Guid.NewGuid();
            var regularCallerId = Guid.NewGuid();

            var privateMember = new Member
            {
                Id = privateMemberId,
                TenantId = churchId,
                FirstName = "Secret",
                LastName = "Believer",
                Email = "secret@church.local",
                DirectoryVisibility = DirectoryVisibility.Private
            };
            SeedMember(churchId, privateMember);

            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-User-Id", regularCallerId.ToString());
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // 1. Private member does not appear in directory list
            var listRes = await client.GetAsync("/api/v1/members");
            var list = await listRes.Content.ReadFromJsonAsync<List<DirectoryMemberResponse>>();
            Assert.NotNull(list);
            Assert.DoesNotContain(list, m => m.Id == privateMemberId);

            // 2. Direct lookup by ID returns 404
            var detailRes = await client.GetAsync($"/api/v1/members/{privateMemberId}");
            Assert.Equal(HttpStatusCode.NotFound, detailRes.StatusCode);
        }

        [Fact]
        public async Task Scenario4_PastorOrAdmin_ViewsDirectory_SeesAllProfilesUnredacted()
        {
            var churchId = Guid.NewGuid();
            var privateMemberId = Guid.NewGuid();
            var pastorId = Guid.NewGuid();

            var member = new Member
            {
                Id = privateMemberId,
                TenantId = churchId,
                FirstName = "Guarded",
                LastName = "Congregant",
                Email = "guarded@church.local",
                PhoneNumber = "+15550001111",
                Address = "789 Quiet Ct",
                DirectoryVisibility = DirectoryVisibility.LeadersOnly,
                ShowPhoneNumber = false,
                ShowEmail = false,
                ShowAddress = false
            };
            SeedMember(churchId, member);

            // Pastor requests directory
            var pastorClient = _factory.CreateClient();
            pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");
            pastorClient.DefaultRequestHeaders.Add("X-User-Id", pastorId.ToString());
            pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var detailRes = await pastorClient.GetAsync($"/api/v1/members/{privateMemberId}");
            Assert.Equal(HttpStatusCode.OK, detailRes.StatusCode);
            var detail = await detailRes.Content.ReadFromJsonAsync<DirectoryMemberResponse>();
            Assert.NotNull(detail);
            Assert.Equal("Guarded Congregant", detail.FullName);
            Assert.Equal("guarded@church.local", detail.Email);       // Unredacted for Pastor
            Assert.Equal("+15550001111", detail.PhoneNumber);         // Unredacted for Pastor
            Assert.Equal("789 Quiet Ct", detail.Address);             // Unredacted for Pastor
        }

        [Fact]
        public async Task Scenario5_FamilyEndpoints_CanCreateFamilyAndRetrieveMembers()
        {
            var churchId = Guid.NewGuid();
            var adminId = Guid.NewGuid();
            var headId = Guid.NewGuid();
            var spouseId = Guid.NewGuid();

            var adminClient = _factory.CreateClient();
            adminClient.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            adminClient.DefaultRequestHeaders.Add("X-User-Id", adminId.ToString());
            adminClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // 1. Create family
            var createRes = await adminClient.PostAsJsonAsync("/api/v1/members/families", new CreateFamilyRequest("The Taylors"));
            Assert.Equal(HttpStatusCode.Created, createRes.StatusCode);
            var family = await createRes.Content.ReadFromJsonAsync<FamilyResponse>();
            Assert.NotNull(family);
            Assert.Equal("The Taylors", family.FamilyName);

            // 2. Seed members linked to family
            var head = new Member
            {
                Id = headId,
                TenantId = churchId,
                FirstName = "Paul",
                LastName = "Taylor",
                Email = "paul.taylor@church.local",
                FamilyId = family.Id,
                FamilyRole = FamilyRole.HeadOfHousehold,
                DirectoryVisibility = DirectoryVisibility.PublicToMembers
            };
            SeedMember(churchId, head);

            var spouse = new Member
            {
                Id = spouseId,
                TenantId = churchId,
                FirstName = "Mary",
                LastName = "Taylor",
                Email = "mary.taylor@church.local",
                FamilyId = family.Id,
                FamilyRole = FamilyRole.Spouse,
                DirectoryVisibility = DirectoryVisibility.PublicToMembers
            };
            SeedMember(churchId, spouse);

            // 3. Retrieve family details
            var familyRes = await adminClient.GetAsync($"/api/v1/members/families/{family.Id}");
            Assert.Equal(HttpStatusCode.OK, familyRes.StatusCode);
            var familyDetail = await familyRes.Content.ReadFromJsonAsync<FamilyResponse>();
            Assert.NotNull(familyDetail);
            Assert.Equal(2, familyDetail.Members.Count);
            Assert.Equal("Paul Taylor", familyDetail.Members[0].FullName);
            Assert.Equal("Mary Taylor", familyDetail.Members[1].FullName);
        }

        [Fact]
        public async Task Scenario6_TenantIsolation_CannotSeeProfilesFromAnotherChurch()
        {
            var churchA = Guid.NewGuid();
            var churchB = Guid.NewGuid();

            var memberAId = Guid.NewGuid();
            var memberBId = Guid.NewGuid();

            SeedMember(churchA, new Member
            {
                Id = memberAId,
                TenantId = churchA,
                FirstName = "ChurchA",
                LastName = "Member",
                Email = "a@church.local",
                DirectoryVisibility = DirectoryVisibility.PublicToMembers
            });

            SeedMember(churchB, new Member
            {
                Id = memberBId,
                TenantId = churchB,
                FirstName = "ChurchB",
                LastName = "Member",
                Email = "b@church.local",
                DirectoryVisibility = DirectoryVisibility.PublicToMembers
            });

            var clientA = _factory.CreateClient();
            clientA.DefaultRequestHeaders.Add("X-User-Role", "Member");
            clientA.DefaultRequestHeaders.Add("X-User-Id", memberAId.ToString());
            clientA.DefaultRequestHeaders.Add("X-Tenant-Id", churchA.ToString());

            // Directory of Church A must only return Church A members
            var listRes = await clientA.GetAsync("/api/v1/members");
            var list = await listRes.Content.ReadFromJsonAsync<List<DirectoryMemberResponse>>();
            Assert.NotNull(list);
            Assert.Contains(list, m => m.Id == memberAId);
            Assert.DoesNotContain(list, m => m.Id == memberBId);

            // Direct ID lookup of Church B member from Church A context must return 404
            var lookupRes = await clientA.GetAsync($"/api/v1/members/{memberBId}");
            Assert.Equal(HttpStatusCode.NotFound, lookupRes.StatusCode);
        }

        [Fact]
        public async Task Scenario7_UnauthenticatedUser_Returns401Unauthorized()
        {
            var client = _factory.CreateClient();

            var meRes = await client.GetAsync("/api/v1/members/me");
            Assert.Equal(HttpStatusCode.Unauthorized, meRes.StatusCode);

            var dirRes = await client.GetAsync("/api/v1/members");
            Assert.Equal(HttpStatusCode.Unauthorized, dirRes.StatusCode);
        }

        [Fact]
        public async Task Scenario8_DateInputs_UnspecifiedKind_NormalizedToUtc()
        {
            var churchId = Guid.NewGuid();
            var memberId = Guid.NewGuid();

            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-User-Id", memberId.ToString());
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // Unspecified Kind dates simulate bare JSON date inputs without timezone (e.g. "1988-11-25")
            var unspecifiedBirth = new DateTime(1988, 11, 25, 0, 0, 0, DateTimeKind.Unspecified);
            var unspecifiedAnniv = new DateTime(2015, 6, 10, 0, 0, 0, DateTimeKind.Unspecified);

            var updateReq = new UpdateMemberProfileRequest(
                FirstName: "Timothy",
                LastName: "Keller",
                PhoneNumber: "+15554443333",
                AvatarUrl: null,
                DateOfBirth: unspecifiedBirth,
                AnniversaryDate: unspecifiedAnniv,
                Address: "100 Redeemer Way",
                DirectoryVisibility: DirectoryVisibility.PublicToMembers,
                ShowPhoneNumber: true,
                ShowEmail: true,
                ShowAddress: true,
                ShowBirthDayAndMonth: true
            );

            var putRes = await client.PutAsJsonAsync("/api/v1/members/me", updateReq);
            Assert.Equal(HttpStatusCode.OK, putRes.StatusCode);
            var updated = await putRes.Content.ReadFromJsonAsync<FullMemberProfileResponse>();
            Assert.NotNull(updated);
            Assert.NotNull(updated.DateOfBirth);
            Assert.Equal(DateTimeKind.Utc, updated.DateOfBirth.Value.Kind);
            Assert.NotNull(updated.AnniversaryDate);
            Assert.Equal(DateTimeKind.Utc, updated.AnniversaryDate.Value.Kind);
        }

        [Fact]
        public async Task Scenario9_FamilySecurity_NonLeaderCannotAssignToFamily_Returns403()
        {
            var churchId = Guid.NewGuid();
            var memberAId = Guid.NewGuid();
            var adminId = Guid.NewGuid();

            var family = new Family
            {
                Id = Guid.NewGuid(),
                TenantId = churchId,
                FamilyName = "The Johnsons"
            };
            SeedFamily(churchId, family);

            var memberA = new Member
            {
                Id = memberAId,
                TenantId = churchId,
                FirstName = "Bob",
                LastName = "Jones",
                Email = "bob@church.local",
                DirectoryVisibility = DirectoryVisibility.PublicToMembers
            };
            SeedMember(churchId, memberA);

            // Member A tries to attach themselves to The Johnsons without leader approval
            var memberClient = _factory.CreateClient();
            memberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");
            memberClient.DefaultRequestHeaders.Add("X-User-Id", memberAId.ToString());
            memberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var selfAssignRes = await memberClient.PutAsJsonAsync(
                $"/api/v1/members/{memberAId}/family",
                new AssignFamilyRequest(family.Id, FamilyRole.Spouse));
            Assert.Equal(HttpStatusCode.Forbidden, selfAssignRes.StatusCode);

            // Admin assigns Member A to family -> Success 200
            var adminClient = _factory.CreateClient();
            adminClient.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            adminClient.DefaultRequestHeaders.Add("X-User-Id", adminId.ToString());
            adminClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var adminAssignRes = await adminClient.PutAsJsonAsync(
                $"/api/v1/members/{memberAId}/family",
                new AssignFamilyRequest(family.Id, FamilyRole.Spouse));
            Assert.Equal(HttpStatusCode.OK, adminAssignRes.StatusCode);

            // Member A can disassociate themselves (FamilyId = null) -> Success 200
            var disassociateRes = await memberClient.PutAsJsonAsync(
                $"/api/v1/members/{memberAId}/family",
                new AssignFamilyRequest(null, FamilyRole.Individual));
            Assert.Equal(HttpStatusCode.OK, disassociateRes.StatusCode);
        }

        [Fact]
        public async Task Scenario10_FamilySecurity_HiddenFamily_Returns404ToUnrelatedMember()
        {
            var churchId = Guid.NewGuid();
            var unrelatedMemberId = Guid.NewGuid();
            var pastorId = Guid.NewGuid();
            var hiddenFamilyId = Guid.NewGuid();

            var family = new Family
            {
                Id = hiddenFamilyId,
                TenantId = churchId,
                FamilyName = "The Secret Family"
            };
            SeedFamily(churchId, family);

            // Seed members who all have DirectoryVisibility = Private
            var member1 = new Member
            {
                Id = Guid.NewGuid(),
                TenantId = churchId,
                FirstName = "Secret1",
                LastName = "Person",
                Email = "s1@church.local",
                FamilyId = hiddenFamilyId,
                FamilyRole = FamilyRole.HeadOfHousehold,
                DirectoryVisibility = DirectoryVisibility.Private
            };
            SeedMember(churchId, member1);

            var member2 = new Member
            {
                Id = Guid.NewGuid(),
                TenantId = churchId,
                FirstName = "Secret2",
                LastName = "Person",
                Email = "s2@church.local",
                FamilyId = hiddenFamilyId,
                FamilyRole = FamilyRole.Spouse,
                DirectoryVisibility = DirectoryVisibility.Private
            };
            SeedMember(churchId, member2);

            // Unrelated regular member tries to inspect this family
            var unrelatedClient = _factory.CreateClient();
            unrelatedClient.DefaultRequestHeaders.Add("X-User-Role", "Member");
            unrelatedClient.DefaultRequestHeaders.Add("X-User-Id", unrelatedMemberId.ToString());
            unrelatedClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var lookupRes = await unrelatedClient.GetAsync($"/api/v1/members/families/{hiddenFamilyId}");
            Assert.Equal(HttpStatusCode.NotFound, lookupRes.StatusCode);

            // Pastor inspects -> Success 200 with unredacted members
            var pastorClient = _factory.CreateClient();
            pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");
            pastorClient.DefaultRequestHeaders.Add("X-User-Id", pastorId.ToString());
            pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var pastorRes = await pastorClient.GetAsync($"/api/v1/members/families/{hiddenFamilyId}");
            Assert.Equal(HttpStatusCode.OK, pastorRes.StatusCode);
            var pastorFamily = await pastorRes.Content.ReadFromJsonAsync<FamilyResponse>();
            Assert.NotNull(pastorFamily);
            Assert.Equal("The Secret Family", pastorFamily.FamilyName);
            Assert.Equal(2, pastorFamily.Members.Count);
        }
    }
}
