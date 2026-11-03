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

namespace Church.Tests;

public class CelebrationsApiTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;

    public CelebrationsApiTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
    }

    private void SeedMember(Guid churchId, Member member)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        member.ChurchId = churchId;
        db.Members.Add(member);
        db.SaveChanges();
    }

    [Fact]
    public async Task TodayCelebrations_ReturnsMatchingBirthdaysAndAnniversaries_WithAgeRedactionForRegularMembers()
    {
        var churchId = Guid.NewGuid();
        var today = DateTime.UtcNow;

        var bdayMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "Grace",
            LastName = "Hopper",
            Email = "grace@church.local",
            PhoneNumber = "+15551234567",
            DateOfBirth = new DateTime(1985, today.Month, today.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.PublicToMembers,
            ShowBirthDayAndMonth = true,
            ShowPhoneNumber = true
        };

        var annivMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "David",
            LastName = "Livingstone",
            Email = "david@church.local",
            AnniversaryDate = new DateTime(2010, today.Month, today.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.PublicToMembers,
            ShowBirthDayAndMonth = true,
            ShowPhoneNumber = false
        };

        var otherMonthMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "Future",
            LastName = "Person",
            Email = "future@church.local",
            DateOfBirth = today.AddMonths(2),
            DirectoryVisibility = DirectoryVisibility.PublicToMembers,
            ShowBirthDayAndMonth = true
        };

        SeedMember(churchId, bdayMember);
        SeedMember(churchId, annivMember);
        SeedMember(churchId, otherMonthMember);

        // 1. Regular Member: receives celebrations, but birth year (exact age) is redacted (null)
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");
        client.DefaultRequestHeaders.Add("X-User-Id", Guid.NewGuid().ToString());

        var response = await client.GetAsync($"/api/v1/celebrations/today?date={today:yyyy-MM-dd}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var celebrations = await response.Content.ReadFromJsonAsync<List<CelebrationEventResponse>>();
        Assert.NotNull(celebrations);
        Assert.Contains(celebrations!, c => c.MemberName == "Grace Hopper" && c.Type == CelebrationType.Birthday);
        Assert.Contains(celebrations!, c => c.MemberName == "David Livingstone" && c.Type == CelebrationType.Anniversary);
        Assert.DoesNotContain(celebrations!, c => c.MemberName == "Future Person");

        var grace = celebrations!.First(c => c.MemberName == "Grace Hopper");
        Assert.True(grace.CanMessageDirectly);
        Assert.NotNull(grace.WhatsAppUrl);
        Assert.StartsWith("https://wa.me/15551234567?text=", grace.WhatsAppUrl!);
        // Birth year/age is protected and redacted for regular members
        Assert.Null(grace.Years);

        // 2. Pastor: receives celebrations WITH full pastoral age insight
        var pastorClient = _factory.CreateClient();
        pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");

        var pastorResp = await pastorClient.GetAsync($"/api/v1/celebrations/today?date={today:yyyy-MM-dd}");
        var pastorCelebrations = await pastorResp.Content.ReadFromJsonAsync<List<CelebrationEventResponse>>();
        var pastorGrace = pastorCelebrations!.First(c => c.MemberName == "Grace Hopper");
        Assert.NotNull(pastorGrace.Years);
        Assert.Equal(today.Year - 1985, pastorGrace.Years);
    }

    [Fact]
    public async Task PrivacyFilter_DirectoryVisibility_PrivateAndLeadersOnlyHiddenFromMembers_VisibleToPastors()
    {
        var churchId = Guid.NewGuid();
        var today = DateTime.UtcNow;

        var privateMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "Private",
            LastName = "Profile",
            Email = "private@church.local",
            DateOfBirth = new DateTime(1990, today.Month, today.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.Private,
            ShowBirthDayAndMonth = true // ShowBirthday enabled, but profile is Private
        };

        var leadersOnlyMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "LeadersOnly",
            LastName = "Profile",
            Email = "leaders@church.local",
            DateOfBirth = new DateTime(1988, today.Month, today.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.LeadersOnly,
            ShowBirthDayAndMonth = true // ShowBirthday enabled, but profile is LeadersOnly
        };

        var birthdayOptOutMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "OptOut",
            LastName = "Birthday",
            Email = "optout@church.local",
            DateOfBirth = new DateTime(1991, today.Month, today.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.PublicToMembers,
            ShowBirthDayAndMonth = false // Profile is Public, but opted out of birthday display
        };

        SeedMember(churchId, privateMember);
        SeedMember(churchId, leadersOnlyMember);
        SeedMember(churchId, birthdayOptOutMember);

        // 1. Regular Member: should NOT see any of the 3 restricted celebrations
        var memberClient = _factory.CreateClient();
        memberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        memberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var memberResponse = await memberClient.GetAsync($"/api/v1/celebrations/today?date={today:yyyy-MM-dd}");
        Assert.Equal(HttpStatusCode.OK, memberResponse.StatusCode);
        var memberCelebrations = await memberResponse.Content.ReadFromJsonAsync<List<CelebrationEventResponse>>();
        Assert.NotNull(memberCelebrations);
        Assert.DoesNotContain(memberCelebrations!, c => c.MemberName == "Private Profile");
        Assert.DoesNotContain(memberCelebrations!, c => c.MemberName == "LeadersOnly Profile");
        Assert.DoesNotContain(memberCelebrations!, c => c.MemberName == "OptOut Birthday");

        // 2. Pastor: CAN see all 3 celebrations for pastoral care
        var pastorClient = _factory.CreateClient();
        pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");

        var pastorResponse = await pastorClient.GetAsync($"/api/v1/celebrations/today?date={today:yyyy-MM-dd}");
        Assert.Equal(HttpStatusCode.OK, pastorResponse.StatusCode);
        var pastorCelebrations = await pastorResponse.Content.ReadFromJsonAsync<List<CelebrationEventResponse>>();
        Assert.NotNull(pastorCelebrations);
        Assert.Contains(pastorCelebrations!, c => c.MemberName == "Private Profile");
        Assert.Contains(pastorCelebrations!, c => c.MemberName == "LeadersOnly Profile");
        Assert.Contains(pastorCelebrations!, c => c.MemberName == "OptOut Birthday");
    }

    [Fact]
    public async Task PrivacyFilter_HiddenPhoneNumber_SuppressesWhatsAppDirectLinkForRegularMembers()
    {
        var churchId = Guid.NewGuid();
        var today = DateTime.UtcNow;

        var hiddenPhoneMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "Unlisted",
            LastName = "Phone",
            Email = "unlisted@church.local",
            PhoneNumber = "+15559876543",
            DateOfBirth = new DateTime(1992, today.Month, today.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.PublicToMembers,
            ShowBirthDayAndMonth = true,
            ShowPhoneNumber = false // Phone is private
        };

        SeedMember(churchId, hiddenPhoneMember);

        // 1. Regular Member sees celebration, but phone & WhatsApp link are masked
        var memberClient = _factory.CreateClient();
        memberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        memberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var memberResponse = await memberClient.GetAsync($"/api/v1/celebrations/today?date={today:yyyy-MM-dd}");
        var memberList = await memberResponse.Content.ReadFromJsonAsync<List<CelebrationEventResponse>>();
        var itemForMember = memberList!.First(c => c.MemberName == "Unlisted Phone");
        Assert.Null(itemForMember.PhoneNumber);
        Assert.Null(itemForMember.WhatsAppUrl);
        Assert.False(itemForMember.CanMessageDirectly);

        // 2. Pastor sees phone & WhatsApp link for pastoral communication
        var pastorClient = _factory.CreateClient();
        pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");

        var pastorResponse = await pastorClient.GetAsync($"/api/v1/celebrations/today?date={today:yyyy-MM-dd}");
        var pastorList = await pastorResponse.Content.ReadFromJsonAsync<List<CelebrationEventResponse>>();
        var itemForPastor = pastorList!.First(c => c.MemberName == "Unlisted Phone");
        Assert.NotNull(itemForPastor.PhoneNumber);
        Assert.NotNull(itemForPastor.WhatsAppUrl);
        Assert.True(itemForPastor.CanMessageDirectly);
    }

    [Fact]
    public async Task CrossTenantIsolation_CelebrationsNotExposedAcrossChurches()
    {
        var churchA = Guid.NewGuid();
        var churchB = Guid.NewGuid();
        var today = DateTime.UtcNow;

        var churchAMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchA,
            FirstName = "ChurchA",
            LastName = "Member",
            Email = "a@church.local",
            DateOfBirth = new DateTime(1995, today.Month, today.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.PublicToMembers,
            ShowBirthDayAndMonth = true
        };

        SeedMember(churchA, churchAMember);

        var clientB = _factory.CreateClient();
        clientB.DefaultRequestHeaders.Add("X-Tenant-Id", churchB.ToString());
        clientB.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var response = await clientB.GetAsync($"/api/v1/celebrations/today?date={today:yyyy-MM-dd}");
        var celebrations = await response.Content.ReadFromJsonAsync<List<CelebrationEventResponse>>();
        Assert.NotNull(celebrations);
        Assert.DoesNotContain(celebrations!, c => c.MemberName == "ChurchA Member");
    }

    [Fact]
    public async Task UpcomingCelebrations_ReturnsCelebrationsWithinDayWindow_AndEnforcesPrivacy()
    {
        var churchId = Guid.NewGuid();
        var today = DateTime.UtcNow.Date;

        var targetDay = today.AddDays(3);
        var farDay = today.AddDays(15);

        var nearMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "Near",
            LastName = "Celebration",
            Email = "near@church.local",
            DateOfBirth = new DateTime(1990, targetDay.Month, targetDay.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.PublicToMembers,
            ShowBirthDayAndMonth = true
        };

        var farMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "Far",
            LastName = "Celebration",
            Email = "far@church.local",
            DateOfBirth = new DateTime(1990, farDay.Month, farDay.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.PublicToMembers,
            ShowBirthDayAndMonth = true
        };

        var privateNearMember = new Member
        {
            Id = Guid.NewGuid(),
            ChurchId = churchId,
            FirstName = "PrivateNear",
            LastName = "Celebration",
            Email = "privatenear@church.local",
            DateOfBirth = new DateTime(1990, targetDay.Month, targetDay.Day, 0, 0, 0, DateTimeKind.Utc),
            DirectoryVisibility = DirectoryVisibility.Private,
            ShowBirthDayAndMonth = true
        };

        SeedMember(churchId, nearMember);
        SeedMember(churchId, farMember);
        SeedMember(churchId, privateNearMember);

        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var response7Days = await client.GetAsync($"/api/v1/celebrations/upcoming?days=7&startDate={today:yyyy-MM-dd}");
        var list7Days = await response7Days.Content.ReadFromJsonAsync<List<CelebrationEventResponse>>();
        Assert.NotNull(list7Days);
        Assert.Contains(list7Days!, c => c.MemberName == "Near Celebration");
        Assert.DoesNotContain(list7Days!, c => c.MemberName == "Far Celebration");
        Assert.DoesNotContain(list7Days!, c => c.MemberName == "PrivateNear Celebration");

        // Verify age redaction on upcoming birthday for regular members
        var near = list7Days!.First(c => c.MemberName == "Near Celebration");
        Assert.Null(near.Years);

        var response2Days = await client.GetAsync($"/api/v1/celebrations/upcoming?days=2&startDate={today:yyyy-MM-dd}");
        var list2Days = await response2Days.Content.ReadFromJsonAsync<List<CelebrationEventResponse>>();
        Assert.NotNull(list2Days);
        Assert.DoesNotContain(list2Days!, c => c.MemberName == "Near Celebration");
    }

    [Fact]
    public async Task BlessingTemplates_ReturnsApprovedScriptureTemplates()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", Guid.NewGuid().ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var response = await client.GetAsync("/api/v1/celebrations/templates");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var templates = await response.Content.ReadFromJsonAsync<List<BlessingTemplateResponse>>();
        Assert.NotNull(templates);
        Assert.Contains(templates!, t => t.Type == CelebrationType.Birthday);
        Assert.Contains(templates!, t => t.Type == CelebrationType.Anniversary);
    }

    [Fact]
    public async Task DailyScan_PastorCanTrigger_NonPastorForbidden()
    {
        var churchId = Guid.NewGuid();

        // 1. Regular Member should receive 403 Forbidden
        var memberClient = _factory.CreateClient();
        memberClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        memberClient.DefaultRequestHeaders.Add("X-User-Role", "Member");

        var forbiddenResponse = await memberClient.PostAsync("/api/v1/celebrations/scan-daily", null);
        Assert.Equal(HttpStatusCode.Forbidden, forbiddenResponse.StatusCode);

        // 2. Pastor can trigger daily scan
        var pastorClient = _factory.CreateClient();
        pastorClient.DefaultRequestHeaders.Add("X-Tenant-Id", churchId.ToString());
        pastorClient.DefaultRequestHeaders.Add("X-User-Role", "Pastor");

        var successResponse = await pastorClient.PostAsync("/api/v1/celebrations/scan-daily", null);
        Assert.Equal(HttpStatusCode.OK, successResponse.StatusCode);

        var result = await successResponse.Content.ReadFromJsonAsync<DailyScanResultResponse>();
        Assert.NotNull(result);
        Assert.Equal("Completed", result!.Status);
    }

    [Fact]
    public async Task UnauthenticatedRequests_AreRejectedWith401Unauthorized()
    {
        var client = _factory.CreateClient();

        var resToday = await client.GetAsync("/api/v1/celebrations/today");
        Assert.Equal(HttpStatusCode.Unauthorized, resToday.StatusCode);

        var resUpcoming = await client.GetAsync("/api/v1/celebrations/upcoming");
        Assert.Equal(HttpStatusCode.Unauthorized, resUpcoming.StatusCode);

        var resTemplates = await client.GetAsync("/api/v1/celebrations/templates");
        Assert.Equal(HttpStatusCode.Unauthorized, resTemplates.StatusCode);

        var resScan = await client.PostAsync("/api/v1/celebrations/scan-daily", null);
        Assert.Equal(HttpStatusCode.Unauthorized, resScan.StatusCode);
    }
}
