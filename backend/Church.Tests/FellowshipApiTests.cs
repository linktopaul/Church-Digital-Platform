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
    public class FellowshipApiTests : IClassFixture<CustomWebApplicationFactory>
    {
        private readonly CustomWebApplicationFactory _factory;

        public FellowshipApiTests(CustomWebApplicationFactory factory)
        {
            _factory = factory;
        }

        [Fact]
        public async Task AdminOrPastorOrLeader_CanCreateFellowshipSpaces()
        {
            var churchId = Guid.NewGuid();
            var leaderId = Guid.NewGuid();
            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            client.DefaultRequestHeaders.Add("X-User-Id", leaderId.ToString());
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // 1. Create Men's Fellowship space
            var mensFellowshipReq = new CreateFellowshipGroupRequest(
                Name: "Men of Faith",
                Description: "Brotherhood, prayer, and community outreach",
                GroupType: FellowshipGroupType.MensFellowship,
                LeaderId: leaderId,
                LeaderName: "Elder John",
                MeetingSchedule: "Every Saturday 7:00 AM",
                Location: "Main Chapel Hall",
                IsPrivate: false
            );

            var createRes = await client.PostAsJsonAsync("/api/v1/fellowships", mensFellowshipReq);
            Assert.Equal(HttpStatusCode.Created, createRes.StatusCode);
            var group = await createRes.Content.ReadFromJsonAsync<FellowshipGroupResponse>();
            Assert.NotNull(group);
            Assert.Equal("Men of Faith", group.Name);
            Assert.Equal(FellowshipGroupType.MensFellowship, group.GroupType);
            Assert.Equal(1, group.MemberCount); // Leader is automatically added as member

            // 2. Create Sunday School space
            var sundaySchoolReq = new CreateFellowshipGroupRequest(
                Name: "Sunday School - Primary",
                Description: "Biblical foundations for children ages 6-10",
                GroupType: FellowshipGroupType.SundaySchool,
                LeaderId: leaderId,
                LeaderName: "Sister Mary",
                MeetingSchedule: "Sunday 9:00 AM",
                Location: "Room 102",
                IsPrivate: false
            );
            var ssRes = await client.PostAsJsonAsync("/api/v1/fellowships", sundaySchoolReq);
            Assert.Equal(HttpStatusCode.Created, ssRes.StatusCode);

            // 3. Create House Prayer space
            var housePrayerReq = new CreateFellowshipGroupRequest(
                Name: "North District House Prayer",
                Description: "Weekly neighborhood fellowship and intercession",
                GroupType: FellowshipGroupType.HousePrayer,
                LeaderId: leaderId,
                LeaderName: "Brother David",
                MeetingSchedule: "Wednesday 7:30 PM",
                Location: "David's Residence",
                IsPrivate: false
            );
            var hpRes = await client.PostAsJsonAsync("/api/v1/fellowships", housePrayerReq);
            Assert.Equal(HttpStatusCode.Created, hpRes.StatusCode);

            // 4. Verify all 3 appear in group list
            var listRes = await client.GetAsync("/api/v1/fellowships");
            Assert.Equal(HttpStatusCode.OK, listRes.StatusCode);
            var list = await listRes.Content.ReadFromJsonAsync<List<FellowshipGroupResponse>>();
            Assert.NotNull(list);
            Assert.Contains(list, g => g.Name == "Men of Faith");
            Assert.Contains(list, g => g.Name == "Sunday School - Primary");
            Assert.Contains(list, g => g.Name == "North District House Prayer");

            // Filter by GroupType
            var filterRes = await client.GetAsync("/api/v1/fellowships?groupType=HousePrayer");
            Assert.Equal(HttpStatusCode.OK, filterRes.StatusCode);
            var filtered = await filterRes.Content.ReadFromJsonAsync<List<FellowshipGroupResponse>>();
            Assert.NotNull(filtered);
            Assert.All(filtered, g => Assert.Equal(FellowshipGroupType.HousePrayer, g.GroupType));
        }

        [Fact]
        public async Task RegularMember_CannotCreateFellowshipGroup_Returns403()
        {
            var churchId = Guid.NewGuid();
            var memberId = Guid.NewGuid();
            var client = _factory.CreateClient();
            client.DefaultRequestHeaders.Add("X-User-Role", "Member");
            client.DefaultRequestHeaders.Add("X-User-Id", memberId.ToString());
            client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            var payload = new CreateFellowshipGroupRequest(
                Name: "Unauthorized Space",
                Description: null,
                GroupType: FellowshipGroupType.MensFellowship,
                LeaderId: memberId,
                LeaderName: "Test Member",
                MeetingSchedule: null,
                Location: null,
                IsPrivate: false
            );

            var res = await client.PostAsJsonAsync("/api/v1/fellowships", payload);
            Assert.Equal(HttpStatusCode.Forbidden, res.StatusCode);
        }

        [Fact]
        public async Task Member_CanJoinLeaveAndPostInFellowshipGroup()
        {
            var churchId = Guid.NewGuid();
            var adminClient = _factory.CreateClient();
            adminClient.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            adminClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // Create group
            var createGroupRes = await adminClient.PostAsJsonAsync("/api/v1/fellowships", new CreateFellowshipGroupRequest(
                Name: "Grace Fellowship",
                Description: "Fellowship for all believers",
                GroupType: FellowshipGroupType.MensFellowship,
                LeaderId: Guid.NewGuid(),
                LeaderName: "Pastor Thomas",
                MeetingSchedule: "Fridays 6 PM",
                Location: "Youth Hall",
                IsPrivate: false
            ));
            var group = await createGroupRes.Content.ReadFromJsonAsync<FellowshipGroupResponse>();
            Assert.NotNull(group);

            // Member client
            var memberId = Guid.NewGuid();
            var memberClient = _factory.CreateClient();
            memberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");
            memberClient.DefaultRequestHeaders.Add("X-User-Id", memberId.ToString());
            memberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // Verify initial membership status for memberClient (not yet member)
            var initialListRes = await memberClient.GetAsync("/api/v1/fellowships");
            var initialList = await initialListRes.Content.ReadFromJsonAsync<List<FellowshipGroupResponse>>();
            var initialGroup = initialList?.FirstOrDefault(g => g.Id == group.Id);
            Assert.NotNull(initialGroup);
            Assert.False(initialGroup.IsUserMember);

            var initialDetailRes = await memberClient.GetAsync($"/api/v1/fellowships/{group.Id}");
            var initialDetail = await initialDetailRes.Content.ReadFromJsonAsync<FellowshipGroupDetailResponse>();
            Assert.NotNull(initialDetail);
            Assert.False(initialDetail.IsUserMember);

            // 1. Join Group
            var joinRes = await memberClient.PostAsJsonAsync($"/api/v1/fellowships/{group.Id}/join", new JoinFellowshipGroupRequest("Brother Timothy"));
            Assert.Equal(HttpStatusCode.Created, joinRes.StatusCode);
            var joinData = await joinRes.Content.ReadFromJsonAsync<FellowshipMemberResponse>();
            Assert.NotNull(joinData);
            Assert.Equal(memberId, joinData.MemberId);
            Assert.Equal("Brother Timothy", joinData.MemberName);

            // Verify membership restored in list and detail
            var joinedListRes = await memberClient.GetAsync("/api/v1/fellowships");
            var joinedList = await joinedListRes.Content.ReadFromJsonAsync<List<FellowshipGroupResponse>>();
            var joinedGroup = joinedList?.FirstOrDefault(g => g.Id == group.Id);
            Assert.NotNull(joinedGroup);
            Assert.True(joinedGroup.IsUserMember);

            var joinedDetailRes = await memberClient.GetAsync($"/api/v1/fellowships/{group.Id}");
            var joinedDetail = await joinedDetailRes.Content.ReadFromJsonAsync<FellowshipGroupDetailResponse>();
            Assert.NotNull(joinedDetail);
            Assert.True(joinedDetail.IsUserMember);

            // 2. Check Members list
            var membersRes = await memberClient.GetAsync($"/api/v1/fellowships/{group.Id}/members");
            Assert.Equal(HttpStatusCode.OK, membersRes.StatusCode);
            var members = await membersRes.Content.ReadFromJsonAsync<List<FellowshipMemberResponse>>();
            Assert.NotNull(members);
            Assert.Contains(members, m => m.MemberId == memberId);

            // 3. Post a message / discussion
            var postReq = new CreateFellowshipPostRequest(
                Title: "Weekly Bible Study Notes",
                Content: "Reflecting on Romans 12:1-2 for this upcoming meeting.",
                AuthorName: "Brother Timothy"
            );
            var postRes = await memberClient.PostAsJsonAsync($"/api/v1/fellowships/{group.Id}/posts", postReq);
            Assert.Equal(HttpStatusCode.Created, postRes.StatusCode);
            var postData = await postRes.Content.ReadFromJsonAsync<FellowshipPostResponse>();
            Assert.NotNull(postData);
            Assert.Equal("Weekly Bible Study Notes", postData.Title);
            Assert.Equal(memberId, postData.AuthorId);

            // 4. View Posts
            var getPostsRes = await memberClient.GetAsync($"/api/v1/fellowships/{group.Id}/posts");
            Assert.Equal(HttpStatusCode.OK, getPostsRes.StatusCode);
            var posts = await getPostsRes.Content.ReadFromJsonAsync<List<FellowshipPostResponse>>();
            Assert.NotNull(posts);
            Assert.Contains(posts, p => p.Id == postData.Id);

            // 5. Leave Group
            var leaveRes = await memberClient.PostAsync($"/api/v1/fellowships/{group.Id}/leave", null);
            Assert.Equal(HttpStatusCode.NoContent, leaveRes.StatusCode);

            // Verify left
            var updatedMembersRes = await memberClient.GetAsync($"/api/v1/fellowships/{group.Id}/members");
            var updatedMembers = await updatedMembersRes.Content.ReadFromJsonAsync<List<FellowshipMemberResponse>>();
            Assert.NotNull(updatedMembers);
            Assert.DoesNotContain(updatedMembers, m => m.MemberId == memberId);
        }

        [Fact]
        public async Task Privacy_PrivateGroupRestrictsAccessToNonMembers()
        {
            var churchId = Guid.NewGuid();
            var leaderId = Guid.NewGuid();
            var leaderClient = _factory.CreateClient();
            leaderClient.DefaultRequestHeaders.Add("X-User-Role", "FellowshipLeader");
            leaderClient.DefaultRequestHeaders.Add("X-User-Id", leaderId.ToString());
            leaderClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // Create private House Prayer group
            var groupRes = await leaderClient.PostAsJsonAsync("/api/v1/fellowships", new CreateFellowshipGroupRequest(
                Name: "Private Leaders Prayer Cell",
                Description: "Confidential prayer circle",
                GroupType: FellowshipGroupType.HousePrayer,
                LeaderId: leaderId,
                LeaderName: "Leader Peter",
                MeetingSchedule: "Thursdays 8 PM",
                Location: "Private Residence",
                IsPrivate: true
            ));
            var group = await groupRes.Content.ReadFromJsonAsync<FellowshipGroupResponse>();
            Assert.NotNull(group);

            // Unrelated member
            var nonMemberId = Guid.NewGuid();
            var nonMemberClient = _factory.CreateClient();
            nonMemberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");
            nonMemberClient.DefaultRequestHeaders.Add("X-User-Id", nonMemberId.ToString());
            nonMemberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // Non-member list does not see private group
            var listRes = await nonMemberClient.GetAsync("/api/v1/fellowships");
            var groups = await listRes.Content.ReadFromJsonAsync<List<FellowshipGroupResponse>>();
            Assert.NotNull(groups);
            Assert.DoesNotContain(groups, g => g.Id == group.Id);

            // Non-member GET detail -> 403 Forbidden
            var detailRes = await nonMemberClient.GetAsync($"/api/v1/fellowships/{group.Id}");
            Assert.Equal(HttpStatusCode.Forbidden, detailRes.StatusCode);

            // Non-member GET posts -> 403 Forbidden
            var postsRes = await nonMemberClient.GetAsync($"/api/v1/fellowships/{group.Id}/posts");
            Assert.Equal(HttpStatusCode.Forbidden, postsRes.StatusCode);

            // Non-member POST message -> 403 Forbidden
            var postAttemptRes = await nonMemberClient.PostAsJsonAsync($"/api/v1/fellowships/{group.Id}/posts", new CreateFellowshipPostRequest("Hello", "Attempt", "NonMember"));
            Assert.Equal(HttpStatusCode.Forbidden, postAttemptRes.StatusCode);

            // Finding (2): Non-member attempts to self-join private group knowing ID -> 403 Forbidden
            var joinAttemptRes = await nonMemberClient.PostAsJsonAsync($"/api/v1/fellowships/{group.Id}/join", new JoinFellowshipGroupRequest("Intruder"));
            Assert.Equal(HttpStatusCode.Forbidden, joinAttemptRes.StatusCode);

            // Non-member attempts to read member roster of private group -> 403 Forbidden
            var membersAttemptRes = await nonMemberClient.GetAsync($"/api/v1/fellowships/{group.Id}/members");
            Assert.Equal(HttpStatusCode.Forbidden, membersAttemptRes.StatusCode);
        }

        [Fact]
        public async Task FellowshipLeader_EditPermissions_EnforcesNonNullOwnershipAndAdminBypass()
        {
            var churchId = Guid.NewGuid();
            var leaderAId = Guid.NewGuid();
            var leaderBId = Guid.NewGuid();

            var adminClient = _factory.CreateClient();
            adminClient.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            adminClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // 1. Create a group with leaderA
            var groupA1Res = await adminClient.PostAsJsonAsync("/api/v1/fellowships", new CreateFellowshipGroupRequest(
                Name: "Leader A Group",
                Description: "Description A",
                GroupType: FellowshipGroupType.MensFellowship,
                LeaderId: leaderAId,
                LeaderName: "Leader A",
                MeetingSchedule: "Saturdays",
                Location: "Room 1",
                IsPrivate: false
            ));
            var groupA1 = await groupA1Res.Content.ReadFromJsonAsync<FellowshipGroupResponse>();
            Assert.NotNull(groupA1);

            // 2. Create a group with null LeaderId
            var groupNullLeaderRes = await adminClient.PostAsJsonAsync("/api/v1/fellowships", new CreateFellowshipGroupRequest(
                Name: "Unassigned Leader Group",
                Description: "No leader yet",
                GroupType: FellowshipGroupType.General,
                LeaderId: null,
                LeaderName: null,
                MeetingSchedule: "Fridays",
                Location: "Room 2",
                IsPrivate: false
            ));
            var groupNullLeader = await groupNullLeaderRes.Content.ReadFromJsonAsync<FellowshipGroupResponse>();
            Assert.NotNull(groupNullLeader);

            // Client for Leader A
            var clientLeaderA = _factory.CreateClient();
            clientLeaderA.DefaultRequestHeaders.Add("X-User-Role", "FellowshipLeader");
            clientLeaderA.DefaultRequestHeaders.Add("X-User-Id", leaderAId.ToString());
            clientLeaderA.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // Client for Leader B (non-owner)
            var clientLeaderB = _factory.CreateClient();
            clientLeaderB.DefaultRequestHeaders.Add("X-User-Role", "FellowshipLeader");
            clientLeaderB.DefaultRequestHeaders.Add("X-User-Id", leaderBId.ToString());
            clientLeaderB.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());

            // Test 1: Leader A can edit their own group
            var validEditRes = await clientLeaderA.PutAsJsonAsync($"/api/v1/fellowships/{groupA1.Id}", new UpdateFellowshipGroupRequest(
                Name: "Leader A Group (Updated)",
                Description: "Updated desc",
                GroupType: FellowshipGroupType.MensFellowship,
                LeaderId: leaderAId,
                LeaderName: "Leader A",
                MeetingSchedule: "Saturdays 8 AM",
                Location: "Room 1B",
                IsPrivate: false
            ));
            Assert.Equal(HttpStatusCode.OK, validEditRes.StatusCode);
            var updatedA = await validEditRes.Content.ReadFromJsonAsync<FellowshipGroupResponse>();
            Assert.Equal("Leader A Group (Updated)", updatedA!.Name);

            // Test 2: Leader B attempts to edit Leader A's group -> 403 Forbidden
            var nonOwnerEditRes = await clientLeaderB.PutAsJsonAsync($"/api/v1/fellowships/{groupA1.Id}", new UpdateFellowshipGroupRequest(
                Name: "Hijacked by Leader B",
                Description: "Hacked",
                GroupType: FellowshipGroupType.MensFellowship,
                LeaderId: leaderBId,
                LeaderName: "Leader B",
                MeetingSchedule: "Never",
                Location: "Nowhere",
                IsPrivate: false
            ));
            Assert.Equal(HttpStatusCode.Forbidden, nonOwnerEditRes.StatusCode);

            // Test 3: Leader A attempts to edit a group with null LeaderId -> 403 Forbidden
            var nullLeaderEditRes = await clientLeaderA.PutAsJsonAsync($"/api/v1/fellowships/{groupNullLeader.Id}", new UpdateFellowshipGroupRequest(
                Name: "Claiming Unassigned Group",
                Description: "Mine now",
                GroupType: FellowshipGroupType.General,
                LeaderId: leaderAId,
                LeaderName: "Leader A",
                MeetingSchedule: "Fridays",
                Location: "Room 2",
                IsPrivate: false
            ));
            Assert.Equal(HttpStatusCode.Forbidden, nullLeaderEditRes.StatusCode);

            // Test 4: Admin/Pastor can edit both group with null LeaderId and group owned by Leader A
            var adminEditNullRes = await adminClient.PutAsJsonAsync($"/api/v1/fellowships/{groupNullLeader.Id}", new UpdateFellowshipGroupRequest(
                Name: "Admin Assigned Group",
                Description: "Assigned by pastor",
                GroupType: FellowshipGroupType.General,
                LeaderId: leaderAId,
                LeaderName: "Leader A",
                MeetingSchedule: "Sundays",
                Location: "Sanctuary",
                IsPrivate: false
            ));
            Assert.Equal(HttpStatusCode.OK, adminEditNullRes.StatusCode);
        }

        [Fact]
        public async Task TenantIsolation_FellowshipGroupsAndPostsNeverExposedAcrossTenants()
        {
            var churchA = Guid.NewGuid();
            var churchB = Guid.NewGuid();

            var clientA = _factory.CreateClient();
            clientA.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            clientA.DefaultRequestHeaders.Add("X-Tenant-Id", churchA.ToString());

            var clientB = _factory.CreateClient();
            clientB.DefaultRequestHeaders.Add("X-User-Role", "Admin");
            clientB.DefaultRequestHeaders.Add("X-Tenant-Id", churchB.ToString());

            // Church A creates a group
            var groupARes = await clientA.PostAsJsonAsync("/api/v1/fellowships", new CreateFellowshipGroupRequest(
                Name: "Church A Men's Group",
                Description: "Secret group for Church A",
                GroupType: FellowshipGroupType.MensFellowship,
                LeaderId: null,
                LeaderName: "Church A Pastor",
                MeetingSchedule: "Sundays",
                Location: "Room A",
                IsPrivate: false
            ));
            var groupA = await groupARes.Content.ReadFromJsonAsync<FellowshipGroupResponse>();
            Assert.NotNull(groupA);

            // Church B queries all fellowships
            var churchBGroups = await clientB.GetFromJsonAsync<List<FellowshipGroupResponse>>("/api/v1/fellowships");
            Assert.NotNull(churchBGroups);
            Assert.DoesNotContain(churchBGroups, g => g.Id == groupA.Id);

            // Church B attempts direct GET -> 404 Not Found (due to global query filter)
            var getRes = await clientB.GetAsync($"/api/v1/fellowships/{groupA.Id}");
            Assert.Equal(HttpStatusCode.NotFound, getRes.StatusCode);

            // Church B attempts to join Church A's group -> 404 Not Found
            var joinRes = await clientB.PostAsJsonAsync($"/api/v1/fellowships/{groupA.Id}/join", new JoinFellowshipGroupRequest("Infiltrator"));
            Assert.Equal(HttpStatusCode.NotFound, joinRes.StatusCode);

            // Church B attempts to post to Church A's group -> 404 Not Found
            var postRes = await clientB.PostAsJsonAsync($"/api/v1/fellowships/{groupA.Id}/posts", new CreateFellowshipPostRequest("Leak", "Leak content", null));
            Assert.Equal(HttpStatusCode.NotFound, postRes.StatusCode);
        }
    }
}
