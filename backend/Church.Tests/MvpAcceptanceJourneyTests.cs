using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using System.Threading.Tasks;
using Church.API.Endpoints;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Church.Tests;

/// <summary>
/// MVP Acceptance Integration Suite for Issue #59:
/// Verifies the end-to-end invite-to-confidential-prayer journey across identity and mobile backend.
/// Uses ProductionWebApplicationFactory to guarantee:
/// - Fails closed: AllowTestHeaderAuth is disabled; role and tenant headers are strictly ignored.
/// - RSA RS256 token verification with OpenIddict Authorization Code + PKCE S256.
/// - EF Core multi-tenant query filter isolation and pastor-only authorization.
/// </summary>
public class MvpAcceptanceJourneyTests : IClassFixture<ProductionWebApplicationFactory>
{
    private const string ClientId = "church_mobile_app";
    private const string RedirectUri = "com.church.app://oauthredirect";

    private readonly ProductionWebApplicationFactory _factory;

    public MvpAcceptanceJourneyTests(ProductionWebApplicationFactory factory)
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
            ["state"] = "state-mvp-journey",
            ["nonce"] = "nonce-mvp-" + Guid.NewGuid(),
            ["email"] = email,
            ["password"] = password,
            ["tenant_id"] = tenantId.ToString()
        });

        var authResponse = await client.PostAsync("/connect/authorize", authorizeForm);
        Assert.Equal(HttpStatusCode.OK, authResponse.StatusCode);

        var authResult = await authResponse.Content.ReadFromJsonAsync<OidcAuthorizeResponse>();
        Assert.NotNull(authResult);
        Assert.False(string.IsNullOrWhiteSpace(authResult!.Code));

        var tokenForm = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = ClientId,
            ["code"] = authResult.Code,
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
    public async Task InviteOnlyRegistration_PublicSelfRegistration_IsRejected()
    {
        var client = _factory.CreateClient();

        // 1. Verify unauthenticated public registration routes are non-existent (fail closed)
        var registerAttempt1 = await client.PostAsJsonAsync("/api/v1/auth/register", new { email = "stranger@public.com" });
        Assert.Equal(HttpStatusCode.NotFound, registerAttempt1.StatusCode);

        var registerAttempt2 = await client.PostAsJsonAsync("/api/v1/users/register", new { email = "stranger@public.com" });
        Assert.Equal(HttpStatusCode.NotFound, registerAttempt2.StatusCode);

        // 2. Verify unprovisioned user attempting PKCE authorization code exchange is rejected
        var (verifier, challenge) = CreatePkcePair();
        var authorizeForm = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["redirect_uri"] = RedirectUri,
            ["response_type"] = "code",
            ["scope"] = "openid profile email offline_access roles church_api",
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256",
            ["email"] = "unprovisioned.attacker@external.com",
            ["password"] = "InvalidCredentials!999",
            ["tenant_id"] = Guid.NewGuid().ToString()
        });

        var authResponse = await client.PostAsync("/connect/authorize", authorizeForm);
        Assert.Equal(HttpStatusCode.Unauthorized, authResponse.StatusCode);

        // 3. Verify tampered redirect_uri is rejected
        var tamperedForm = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["redirect_uri"] = "https://malicious.site/callback",
            ["response_type"] = "code",
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256"
        });
        var tamperedResponse = await client.PostAsync("/connect/authorize", tamperedForm);
        Assert.Equal(HttpStatusCode.BadRequest, tamperedResponse.StatusCode);
    }

    [Fact]
    public async Task PkceAuthorizationCodeFlow_DerivesTenantAndRoleFromValidatedServerClaims()
    {
        var churchId = Guid.NewGuid();
        var email = $"member.journey.{Guid.NewGuid():N}@church.org";

        var (client, tokens, user) = await AuthenticateUserAsync(
            churchId,
            email,
            "SecurePass123!",
            "Verified Journey Member",
            ChurchRoleNames.Member);

        // Attempt client header spoofing: pass forged X-Tenant-Id and X-User-Role
        var forgedTenantId = Guid.NewGuid();
        client.DefaultRequestHeaders.Add("X-Tenant-Id", forgedTenantId.ToString());
        client.DefaultRequestHeaders.Add("X-User-Role", ChurchRoleNames.Pastor);

        // Verify /connect/userinfo derives tenant and role strictly from verified JWT
        var userInfoResponse = await client.GetAsync("/connect/userinfo");
        Assert.Equal(HttpStatusCode.OK, userInfoResponse.StatusCode);
        var userInfo = await userInfoResponse.Content.ReadFromJsonAsync<OidcUserInfoResponse>();
        Assert.NotNull(userInfo);
        Assert.Equal(user.Id, userInfo!.Sub);
        Assert.Equal(churchId, userInfo.TenantId);
        Assert.NotEqual(forgedTenantId, userInfo.TenantId);
        Assert.Contains(ChurchRoleNames.Member, userInfo.Roles);
        Assert.DoesNotContain(ChurchRoleNames.Pastor, userInfo.Roles);

        // Verify /api/v1/auth/me also derives strictly from validated server claims
        var meResponse = await client.GetAsync("/api/v1/auth/me");
        Assert.Equal(HttpStatusCode.OK, meResponse.StatusCode);
        var me = await meResponse.Content.ReadFromJsonAsync<CurrentUserResponse>();
        Assert.NotNull(me);
        Assert.Equal(churchId, me!.TenantId);
        Assert.Equal(user.Id, me.MemberId);
        Assert.DoesNotContain(ChurchRoleNames.Pastor, me.Roles);
    }

    [Fact]
    public async Task MemberSubmitsConfidentialPrayer_AndCanReloadPersistedRecord()
    {
        var churchId = Guid.NewGuid();
        var email = $"prayer.member.{Guid.NewGuid():N}@church.org";

        var (client, _, user) = await AuthenticateUserAsync(
            churchId,
            email,
            "PrayerPass123!",
            "Prayer Submitter",
            ChurchRoleNames.Member);

        // Submit confidential prayer request
        var payload = new CreatePrayerRequestRequest("Please uphold my family during upcoming medical treatment.");
        var postResponse = await client.PostAsJsonAsync("/api/v1/prayer-requests", payload);
        Assert.Equal(HttpStatusCode.Created, postResponse.StatusCode);

        var created = await postResponse.Content.ReadFromJsonAsync<PrayerRequestResponse>();
        Assert.NotNull(created);
        Assert.NotEqual(Guid.Empty, created!.Id);
        Assert.Equal(churchId, created.ChurchId);
        Assert.Equal(user.Id, created.MemberId);
        Assert.Equal("Please uphold my family during upcoming medical treatment.", created.Content);
        Assert.Equal(PrayerRequestStatus.Submitted, created.Status);

        // Reload own requests via /api/v1/prayer-requests/my
        var getMyResponse = await client.GetAsync("/api/v1/prayer-requests/my");
        Assert.Equal(HttpStatusCode.OK, getMyResponse.StatusCode);

        var myRequests = await getMyResponse.Content.ReadFromJsonAsync<List<PrayerRequestResponse>>();
        Assert.NotNull(myRequests);
        Assert.Contains(myRequests!, r => r.Id == created.Id && r.Content == created.Content);
    }

    [Fact]
    public async Task PastorInSameChurch_CanViewPastoralFeed_AndTransitionStatus()
    {
        var churchId = Guid.NewGuid();

        // 1. Member submits prayer
        var memberEmail = $"member.pastoral.{Guid.NewGuid():N}@church.org";
        var (memberClient, _, memberUser) = await AuthenticateUserAsync(
            churchId,
            memberEmail,
            "MemberPass123!",
            "Congregant",
            ChurchRoleNames.Member);

        var submitResponse = await memberClient.PostAsJsonAsync(
            "/api/v1/prayer-requests",
            new CreatePrayerRequestRequest("Prayers for peace and strength during grief."));
        Assert.Equal(HttpStatusCode.Created, submitResponse.StatusCode);
        var createdPrayer = await submitResponse.Content.ReadFromJsonAsync<PrayerRequestResponse>();
        Assert.NotNull(createdPrayer);

        // 2. Pastor signs in and views pastoral feed
        var pastorEmail = $"pastor.care.{Guid.NewGuid():N}@church.org";
        var (pastorClient, _, _) = await AuthenticateUserAsync(
            churchId,
            pastorEmail,
            "PastorPass123!",
            "Senior Pastor",
            ChurchRoleNames.Pastor);

        var allRequestsResponse = await pastorClient.GetAsync("/api/v1/prayer-requests");
        Assert.Equal(HttpStatusCode.OK, allRequestsResponse.StatusCode);
        var allRequests = await allRequestsResponse.Content.ReadFromJsonAsync<List<PrayerRequestResponse>>();
        Assert.NotNull(allRequests);
        Assert.Contains(allRequests!, r => r.Id == createdPrayer!.Id);

        // 3. Pastor transitions status to Praying
        var patchPrayingResponse = await pastorClient.PatchAsJsonAsync(
            $"/api/v1/prayer-requests/{createdPrayer!.Id}/status",
            new UpdatePrayerRequestStatusRequest(PrayerRequestStatus.Praying));
        Assert.Equal(HttpStatusCode.OK, patchPrayingResponse.StatusCode);
        var prayingResult = await patchPrayingResponse.Content.ReadFromJsonAsync<PrayerRequestResponse>();
        Assert.NotNull(prayingResult);
        Assert.Equal(PrayerRequestStatus.Praying, prayingResult!.Status);

        // 4. Pastor transitions status to Answered
        var patchAnsweredResponse = await pastorClient.PatchAsJsonAsync(
            $"/api/v1/prayer-requests/{createdPrayer.Id}/status",
            new UpdatePrayerRequestStatusRequest(PrayerRequestStatus.Answered));
        Assert.Equal(HttpStatusCode.OK, patchAnsweredResponse.StatusCode);
        var answeredResult = await patchAnsweredResponse.Content.ReadFromJsonAsync<PrayerRequestResponse>();
        Assert.NotNull(answeredResult);
        Assert.Equal(PrayerRequestStatus.Answered, answeredResult!.Status);

        // 5. Member verifies status is updated in own list
        var memberReloadResponse = await memberClient.GetAsync("/api/v1/prayer-requests/my");
        Assert.Equal(HttpStatusCode.OK, memberReloadResponse.StatusCode);
        var reloadedList = await memberReloadResponse.Content.ReadFromJsonAsync<List<PrayerRequestResponse>>();
        var memberPrayer = reloadedList!.First(r => r.Id == createdPrayer.Id);
        Assert.Equal(PrayerRequestStatus.Answered, memberPrayer.Status);
    }

    [Fact]
    public async Task AnotherMemberInSameChurch_CannotAccessOrModifyConfidentialPrayer()
    {
        var churchId = Guid.NewGuid();

        // 1. Member 1 creates confidential prayer
        var (member1Client, _, _) = await AuthenticateUserAsync(
            churchId,
            $"member1.{Guid.NewGuid():N}@church.org",
            "PassWord!111",
            "Member One",
            ChurchRoleNames.Member);

        var postRes = await member1Client.PostAsJsonAsync(
            "/api/v1/prayer-requests",
            new CreatePrayerRequestRequest("Private counseling prayer request."));
        Assert.Equal(HttpStatusCode.Created, postRes.StatusCode);
        var createdPrayer = await postRes.Content.ReadFromJsonAsync<PrayerRequestResponse>();
        Assert.NotNull(createdPrayer);

        // 2. Member 2 in the same church signs in
        var (member2Client, _, _) = await AuthenticateUserAsync(
            churchId,
            $"member2.{Guid.NewGuid():N}@church.org",
            "PassWord!222",
            "Member Two",
            ChurchRoleNames.Member);

        // Member 2 cannot access pastoral feed (403 Forbidden)
        var allRequestsResponse = await member2Client.GetAsync("/api/v1/prayer-requests");
        Assert.Equal(HttpStatusCode.Forbidden, allRequestsResponse.StatusCode);

        // Member 2 does not see Member 1's request in own feed
        var myRequestsResponse = await member2Client.GetAsync("/api/v1/prayer-requests/my");
        Assert.Equal(HttpStatusCode.OK, myRequestsResponse.StatusCode);
        var member2Requests = await myRequestsResponse.Content.ReadFromJsonAsync<List<PrayerRequestResponse>>();
        Assert.NotNull(member2Requests);
        Assert.DoesNotContain(member2Requests!, r => r.Id == createdPrayer!.Id);

        // Member 2 cannot patch status of Member 1's request (403 Forbidden)
        var patchResponse = await member2Client.PatchAsJsonAsync(
            $"/api/v1/prayer-requests/{createdPrayer!.Id}/status",
            new UpdatePrayerRequestStatusRequest(PrayerRequestStatus.Praying));
        Assert.Equal(HttpStatusCode.Forbidden, patchResponse.StatusCode);
    }

    [Fact]
    public async Task CrossTenantIsolation_PastorInAnotherChurch_CannotAccessOrModifyPrayer_DirectIdReturns404()
    {
        var churchAId = Guid.NewGuid();
        var churchBId = Guid.NewGuid();

        // 1. Member in Church A creates prayer
        var (memberAClient, _, _) = await AuthenticateUserAsync(
            churchAId,
            $"churchA.member.{Guid.NewGuid():N}@church.org",
            "Pass12345!",
            "Church A Member",
            ChurchRoleNames.Member);

        var postRes = await memberAClient.PostAsJsonAsync(
            "/api/v1/prayer-requests",
            new CreatePrayerRequestRequest("Church A confidential prayer item."));
        Assert.Equal(HttpStatusCode.Created, postRes.StatusCode);
        var churchAPrayer = await postRes.Content.ReadFromJsonAsync<PrayerRequestResponse>();
        Assert.NotNull(churchAPrayer);

        // 2. Pastor in Church B signs in
        var (pastorBClient, _, _) = await AuthenticateUserAsync(
            churchBId,
            $"churchB.pastor.{Guid.NewGuid():N}@church.org",
            "Pass12345!",
            "Church B Pastor",
            ChurchRoleNames.Pastor);

        // Church B pastoral feed must NOT contain Church A's prayer
        var churchBFeedResponse = await pastorBClient.GetAsync("/api/v1/prayer-requests");
        Assert.Equal(HttpStatusCode.OK, churchBFeedResponse.StatusCode);
        var churchBFeed = await churchBFeedResponse.Content.ReadFromJsonAsync<List<PrayerRequestResponse>>();
        Assert.NotNull(churchBFeed);
        Assert.DoesNotContain(churchBFeed!, r => r.Id == churchAPrayer!.Id);

        // Direct-ID status update attempt by Church B pastor on Church A prayer must fail with 404 Not Found
        var crossTenantPatch = await pastorBClient.PatchAsJsonAsync(
            $"/api/v1/prayer-requests/{churchAPrayer!.Id}/status",
            new UpdatePrayerRequestStatusRequest(PrayerRequestStatus.Praying));
        Assert.Equal(HttpStatusCode.NotFound, crossTenantPatch.StatusCode);
    }

    [Fact]
    public async Task SessionRevocation_InvalidatesRefreshToken_AndPreventsReuse()
    {
        var churchId = Guid.NewGuid();
        var (client, tokens, _) = await AuthenticateUserAsync(
            churchId,
            $"revoke.user.{Guid.NewGuid():N}@church.org",
            "RevokePass123!",
            "Revocation Tester",
            ChurchRoleNames.Member);

        Assert.False(string.IsNullOrWhiteSpace(tokens.RefreshToken));

        // Revoke the refresh token via /connect/revoke
        var revokeResponse = await client.PostAsync("/connect/revoke", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["token"] = tokens.RefreshToken!
        }));
        Assert.Equal(HttpStatusCode.OK, revokeResponse.StatusCode);

        // Attempt to exchange revoked refresh token must be rejected with 400 Bad Request (invalid_grant)
        var refreshAttempt = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["client_id"] = ClientId,
            ["refresh_token"] = tokens.RefreshToken!
        }));
        Assert.Equal(HttpStatusCode.BadRequest, refreshAttempt.StatusCode);
        var errorObj = await refreshAttempt.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("invalid_grant", errorObj.GetProperty("error").GetString());
    }

    [Fact]
    public async Task UnauthenticatedRequests_AreRejectedWith401Unauthorized()
    {
        var anonymousClient = _factory.CreateClient();

        var postRes = await anonymousClient.PostAsJsonAsync(
            "/api/v1/prayer-requests",
            new CreatePrayerRequestRequest("Unauthenticated prayer"));
        Assert.Equal(HttpStatusCode.Unauthorized, postRes.StatusCode);

        var getFeedRes = await anonymousClient.GetAsync("/api/v1/prayer-requests");
        Assert.Equal(HttpStatusCode.Unauthorized, getFeedRes.StatusCode);

        var getMyRes = await anonymousClient.GetAsync("/api/v1/prayer-requests/my");
        Assert.Equal(HttpStatusCode.Unauthorized, getMyRes.StatusCode);

        var patchRes = await anonymousClient.PatchAsJsonAsync(
            $"/api/v1/prayer-requests/{Guid.NewGuid()}/status",
            new UpdatePrayerRequestStatusRequest(PrayerRequestStatus.Praying));
        Assert.Equal(HttpStatusCode.Unauthorized, patchRes.StatusCode);
    }
}
