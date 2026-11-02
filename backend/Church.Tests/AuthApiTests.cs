using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Church.API.Endpoints;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Church.Tests;

public class ProductionWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly string _dbName = "ProdAuthTestDb_" + Guid.NewGuid();
    private static readonly string TestRsaPrivateKeyPem = CreateTestRsaPrivateKeyPem();

    private static string CreateTestRsaPrivateKeyPem()
    {
        using var rsa = RSA.Create(2048);
        return rsa.ExportRSAPrivateKeyPem();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Production");
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Authentication:AllowTestHeaderAuth"] = "false",
                ["Authentication:Issuer"] = "https://localhost",
                ["Authentication:Audience"] = "church_api",
                ["Authentication:RsaPrivateKeyPem"] = TestRsaPrivateKeyPem
            });
        });

        builder.ConfigureServices(services =>
        {
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

            services.AddDbContext<ApplicationDbContext>(options =>
            {
                options.UseInMemoryDatabase(_dbName);
            });
        });
    }
}

public class AuthApiTests : IClassFixture<ProductionWebApplicationFactory>
{
    private const string ClientId = "church_mobile_app";
    private const string RedirectUri = "com.church.app://oauthredirect";

    private readonly ProductionWebApplicationFactory _factory;

    public AuthApiTests(ProductionWebApplicationFactory factory)
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

    private async Task<OidcTokenResponse> AuthenticateWithPkceAsync(
        HttpClient client,
        Guid tenantId,
        string email,
        string password,
        string nonce = "test-nonce-123")
    {
        var (verifier, challenge) = CreatePkcePair();

        var authorizeForm = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["redirect_uri"] = RedirectUri,
            ["response_type"] = "code",
            ["scope"] = "openid profile email offline_access roles church_api",
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256",
            ["state"] = "state-xyz",
            ["nonce"] = nonce,
            ["email"] = email,
            ["password"] = password,
            ["tenant_id"] = tenantId.ToString()
        });

        var authResponse = await client.PostAsync("/connect/authorize", authorizeForm);
        Assert.Equal(HttpStatusCode.OK, authResponse.StatusCode);

        var authResult = await authResponse.Content.ReadFromJsonAsync<OidcAuthorizeResponse>();
        Assert.NotNull(authResult);
        Assert.False(string.IsNullOrWhiteSpace(authResult!.Code));
        Assert.Equal("state-xyz", authResult.State);

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
        return tokenResult!;
    }

    [Fact]
    public async Task DiscoveryAndJwksEndpoints_ReturnExpectedOidcConfiguration()
    {
        var client = _factory.CreateClient();

        var discoveryResponse = await client.GetAsync("/.well-known/openid-configuration");
        Assert.Equal(HttpStatusCode.OK, discoveryResponse.StatusCode);

        var discovery = await discoveryResponse.Content.ReadFromJsonAsync<OidcDiscoveryDocument>();
        Assert.NotNull(discovery);
        Assert.EndsWith("/connect/authorize", discovery!.AuthorizationEndpoint);
        Assert.EndsWith("/connect/token", discovery.TokenEndpoint);
        Assert.EndsWith("/connect/userinfo", discovery.UserInfoEndpoint);
        Assert.EndsWith("/connect/revoke", discovery.RevocationEndpoint);
        Assert.Contains("public", discovery.SubjectTypesSupported);
        Assert.Contains("RS256", discovery.IdTokenSigningAlgValuesSupported);
        Assert.Contains("S256", discovery.CodeChallengeMethodsSupported);
        Assert.Contains("authorization_code", discovery.GrantTypesSupported);
        Assert.Contains("refresh_token", discovery.GrantTypesSupported);
        Assert.DoesNotContain("password", discovery.GrantTypesSupported);

        var jwksResponse = await client.GetAsync("/.well-known/jwks.json");
        Assert.Equal(HttpStatusCode.OK, jwksResponse.StatusCode);
        var jwksJson = await jwksResponse.Content.ReadAsStringAsync();
        Assert.Contains("\"RS256\"", jwksJson);
    }

    [Fact]
    public async Task PkceAuthorizationCodeFlow_IssuesTokensAndPopulatesUserInfoAndMeEndpoints()
    {
        var tenantId = Guid.NewGuid();
        var seededUser = await SeedUserAsync(
            tenantId,
            "pastor.grace@church.org",
            "CorrectHorseBatteryStaple!1",
            "Pastor Grace",
            ChurchRoleNames.Pastor,
            ChurchRoleNames.Member);

        var client = _factory.CreateClient();
        var tokens = await AuthenticateWithPkceAsync(
            client,
            tenantId,
            "pastor.grace@church.org",
            "CorrectHorseBatteryStaple!1",
            nonce: "nonce-abc-999");

        Assert.False(string.IsNullOrWhiteSpace(tokens.AccessToken));
        Assert.False(string.IsNullOrWhiteSpace(tokens.IdToken));
        Assert.False(string.IsNullOrWhiteSpace(tokens.RefreshToken));
        Assert.Equal("Bearer", tokens.TokenType);

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tokens.AccessToken);

        var userInfoResponse = await client.GetAsync("/connect/userinfo");
        Assert.Equal(HttpStatusCode.OK, userInfoResponse.StatusCode);
        var userInfo = await userInfoResponse.Content.ReadFromJsonAsync<OidcUserInfoResponse>();
        Assert.NotNull(userInfo);
        Assert.Equal(seededUser.Id, userInfo!.Sub);
        Assert.Equal(seededUser.Id, userInfo.MemberId);
        Assert.Equal(tenantId, userInfo.TenantId);
        Assert.Equal(tenantId, userInfo.ChurchId);
        Assert.Equal("pastor.grace@church.org", userInfo.Email);
        Assert.Equal("Pastor Grace", userInfo.Name);
        Assert.Contains(ChurchRoleNames.Pastor, userInfo.Roles);
        Assert.Contains(ChurchRoleNames.Member, userInfo.Roles);

        var meResponse = await client.GetAsync("/api/v1/auth/me");
        Assert.Equal(HttpStatusCode.OK, meResponse.StatusCode);
        var me = await meResponse.Content.ReadFromJsonAsync<CurrentUserResponse>();
        Assert.NotNull(me);
        Assert.Equal(seededUser.Id, me!.MemberId);
        Assert.Equal(tenantId, me.TenantId);
        Assert.Equal("Pastor Grace", me.DisplayName);
        Assert.Contains(ChurchRoleNames.Pastor, me.Roles);
    }

    [Fact]
    public async Task PkceVerification_RejectsWrongVerifierAndReplayedAuthorizationCode()
    {
        var tenantId = Guid.NewGuid();
        await SeedUserAsync(
            tenantId,
            "member.pkce@church.org",
            "StrongPassword!234",
            "PKCE Member",
            ChurchRoleNames.Member);

        var client = _factory.CreateClient();
        var (verifier, challenge) = CreatePkcePair();

        var authorizeResponse = await client.PostAsync("/connect/authorize", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["redirect_uri"] = RedirectUri,
            ["response_type"] = "code",
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256",
            ["email"] = "member.pkce@church.org",
            ["password"] = "StrongPassword!234",
            ["tenant_id"] = tenantId.ToString()
        }));
        var authResult = await authorizeResponse.Content.ReadFromJsonAsync<OidcAuthorizeResponse>();
        Assert.NotNull(authResult);

        // 1. Wrong code_verifier is rejected with invalid_grant
        var wrongVerifierResponse = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = ClientId,
            ["code"] = authResult!.Code,
            ["redirect_uri"] = RedirectUri,
            ["code_verifier"] = "wrong-verifier-value-that-does-not-match-challenge"
        }));
        Assert.Equal(HttpStatusCode.BadRequest, wrongVerifierResponse.StatusCode);
        var wrongVerifierError = await wrongVerifierResponse.Content.ReadFromJsonAsync<OidcErrorResponse>();
        Assert.Equal("invalid_grant", wrongVerifierError?.Error);

        // 2. Exchange with the correct verifier succeeds once
        var validExchangeResponse = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = ClientId,
            ["code"] = authResult.Code,
            ["redirect_uri"] = RedirectUri,
            ["code_verifier"] = verifier
        }));
        Assert.Equal(HttpStatusCode.OK, validExchangeResponse.StatusCode);
        var firstTokens = await validExchangeResponse.Content.ReadFromJsonAsync<OidcTokenResponse>();
        Assert.NotNull(firstTokens);

        // 3. Replaying the same authorization code fails and revokes the issued refresh token
        var replayCodeResponse = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = ClientId,
            ["code"] = authResult.Code,
            ["redirect_uri"] = RedirectUri,
            ["code_verifier"] = verifier
        }));
        Assert.Equal(HttpStatusCode.BadRequest, replayCodeResponse.StatusCode);

        var refreshAfterCodeReplay = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["client_id"] = ClientId,
            ["refresh_token"] = firstTokens!.RefreshToken
        }));
        Assert.Equal(HttpStatusCode.BadRequest, refreshAfterCodeReplay.StatusCode);
    }

    [Fact]
    public async Task RefreshTokenRotation_RotatesSingleUseTokenAndRevokesFamilyOnReplay()
    {
        var tenantId = Guid.NewGuid();
        await SeedUserAsync(
            tenantId,
            "rotate.member@church.org",
            "RotatePass!567",
            "Rotate Member",
            ChurchRoleNames.Member);

        var client = _factory.CreateClient();
        var initialTokens = await AuthenticateWithPkceAsync(
            client,
            tenantId,
            "rotate.member@church.org",
            "RotatePass!567");

        // 1. Rotate refresh token once -> succeeds and returns a new refresh_token
        var refreshResponse1 = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["client_id"] = ClientId,
            ["refresh_token"] = initialTokens.RefreshToken
        }));
        Assert.Equal(HttpStatusCode.OK, refreshResponse1.StatusCode);
        var rotatedTokens = await refreshResponse1.Content.ReadFromJsonAsync<OidcTokenResponse>();
        Assert.NotNull(rotatedTokens);
        Assert.NotEqual(initialTokens.RefreshToken, rotatedTokens!.RefreshToken);

        // 2. Replaying the consumed initial refresh token fails with invalid_grant and revokes the rotated token
        var replayOldRefresh = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["client_id"] = ClientId,
            ["refresh_token"] = initialTokens.RefreshToken
        }));
        Assert.Equal(HttpStatusCode.BadRequest, replayOldRefresh.StatusCode);
        var replayError = await replayOldRefresh.Content.ReadFromJsonAsync<OidcErrorResponse>();
        Assert.Equal("invalid_grant", replayError?.Error);

        // 3. The rotated token is now also revoked due to replay detection
        var useRevokedRotated = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["client_id"] = ClientId,
            ["refresh_token"] = rotatedTokens.RefreshToken
        }));
        Assert.Equal(HttpStatusCode.BadRequest, useRevokedRotated.StatusCode);
    }

    [Fact]
    public async Task PasswordGrantAndPlainPkce_AreRejected()
    {
        var client = _factory.CreateClient();

        var passwordGrantResponse = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "password",
            ["client_id"] = ClientId,
            ["username"] = "user@church.org",
            ["password"] = "secret"
        }));
        Assert.Equal(HttpStatusCode.BadRequest, passwordGrantResponse.StatusCode);
        var error = await passwordGrantResponse.Content.ReadFromJsonAsync<OidcErrorResponse>();
        Assert.Equal("unsupported_grant_type", error?.Error);

        var plainPkceResponse = await client.PostAsync("/connect/authorize", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["redirect_uri"] = RedirectUri,
            ["response_type"] = "code",
            ["code_challenge"] = "plain-challenge",
            ["code_challenge_method"] = "plain"
        }));
        Assert.Equal(HttpStatusCode.BadRequest, plainPkceResponse.StatusCode);
    }

    [Fact]
    public async Task ProductionGuardrails_RejectTestHeadersMockTokensExpiredAndTamperedJwts()
    {
        var tenantA = Guid.NewGuid();
        var user = await SeedUserAsync(
            tenantA,
            "security.member@church.org",
            "SecPass!789",
            "Security Member",
            ChurchRoleNames.Member);

        var client = _factory.CreateClient();

        // 1. TestRole header is rejected in Production
        var testRoleReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/announcements");
        testRoleReq.Headers.Authorization = new AuthenticationHeaderValue("TestRole", "Admin");
        testRoleReq.Headers.Add("X-Tenant-Id", tenantA.ToString());
        var testRoleRes = await client.SendAsync(testRoleReq);
        Assert.Equal(HttpStatusCode.Unauthorized, testRoleRes.StatusCode);

        // 2. X-User-Role / X-User-Id header auth is rejected in Production
        var headerAuthReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/announcements");
        headerAuthReq.Headers.Add("X-User-Role", "Pastor");
        headerAuthReq.Headers.Add("X-User-Id", Guid.NewGuid().ToString());
        headerAuthReq.Headers.Add("X-Tenant-Id", tenantA.ToString());
        var headerAuthRes = await client.SendAsync(headerAuthReq);
        Assert.Equal(HttpStatusCode.Unauthorized, headerAuthRes.StatusCode);

        // 3. Mock Bearer token ("Bearer admin") is rejected in Production
        var mockBearerReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/announcements");
        mockBearerReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", "admin");
        mockBearerReq.Headers.Add("X-Tenant-Id", tenantA.ToString());
        var mockBearerRes = await client.SendAsync(mockBearerReq);
        Assert.Equal(HttpStatusCode.Unauthorized, mockBearerRes.StatusCode);

        // 4. Expired JWT is rejected with 401 Unauthorized
        using var scope = _factory.Services.CreateScope();
        var jwtService = scope.ServiceProvider.GetRequiredService<JwtTokenService>();
        var expiredToken = jwtService.CreateAccessToken(
            user,
            new[] { ChurchRoleNames.Member },
            ClientId,
            "openid church_api",
            "https://localhost",
            nowUtcOverride: DateTime.UtcNow.AddHours(-2));

        var expiredReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/me");
        expiredReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", expiredToken);
        var expiredRes = await client.SendAsync(expiredReq);
        Assert.Equal(HttpStatusCode.Unauthorized, expiredRes.StatusCode);

        // 5. JWT signed with an untrusted RSA key (tampered signature) is rejected with 401 Unauthorized
        using var rogueRsa = RSA.Create(2048);
        var rogueToken = jwtService.SignJwt(new Dictionary<string, object?>
        {
            ["iss"] = "https://localhost",
            ["aud"] = "church_api",
            ["sub"] = user.Id.ToString(),
            ["jti"] = Guid.NewGuid().ToString("N"),
            ["iat"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            ["nbf"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            ["exp"] = DateTimeOffset.UtcNow.AddMinutes(15).ToUnixTimeSeconds(),
            ["member_id"] = user.Id.ToString(),
            ["tenant_id"] = tenantA.ToString(),
            ["roles"] = new[] { ChurchRoleNames.Admin }
        }, signingKeyOverride: rogueRsa);

        var rogueReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/me");
        rogueReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", rogueToken);
        var rogueRes = await client.SendAsync(rogueReq);
        Assert.Equal(HttpStatusCode.Unauthorized, rogueRes.StatusCode);

        // 6. Outside Development/Testing, constructing JwtTokenService without a persistent RSA key fails closed
        var emptyProdConfig = new ConfigurationBuilder().AddInMemoryCollection().Build();
        var prodEnv = _factory.Services.GetRequiredService<IWebHostEnvironment>();
        Assert.Throws<InvalidOperationException>(() => new JwtTokenService(emptyProdConfig, prodEnv));
    }

    [Fact]
    public async Task TenantIsolation_IgnoresSpoofedXTenantIdHeaderAndEnforcesRolePolicies()
    {
        var tenantA = Guid.NewGuid();
        var tenantB = Guid.NewGuid();

        await SeedUserAsync(
            tenantA,
            "pastor.a@church.org",
            "PastorAPass!111",
            "Pastor A",
            ChurchRoleNames.Pastor);

        await SeedUserAsync(
            tenantA,
            "member.a@church.org",
            "MemberAPass!111",
            "Member A",
            ChurchRoleNames.Member);

        await SeedUserAsync(
            tenantB,
            "pastor.b@church.org",
            "PastorBPass!222",
            "Pastor B",
            ChurchRoleNames.Pastor);

        var client = _factory.CreateClient();

        var pastorATokens = await AuthenticateWithPkceAsync(client, tenantA, "pastor.a@church.org", "PastorAPass!111");
        var memberATokens = await AuthenticateWithPkceAsync(client, tenantA, "member.a@church.org", "MemberAPass!111");
        var pastorBTokens = await AuthenticateWithPkceAsync(client, tenantB, "pastor.b@church.org", "PastorBPass!222");

        // Pastor B publishes an announcement in Tenant B
        var postTenantB = new HttpRequestMessage(HttpMethod.Post, "/api/v1/announcements")
        {
            Content = JsonContent.Create(new CreateAnnouncementRequest(
                Title: "Tenant B Secret Notice",
                Content: "Only for Tenant B",
                Priority: AnnouncementPriority.Urgent))
        };
        postTenantB.Headers.Authorization = new AuthenticationHeaderValue("Bearer", pastorBTokens.AccessToken);
        var postBResponse = await client.SendAsync(postTenantB);
        Assert.Equal(HttpStatusCode.Created, postBResponse.StatusCode);

        // Pastor B can read back their own Tenant B announcement via real JWT (verifying tenant query filter resolves after authentication)
        var readTenantBReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/announcements");
        readTenantBReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", pastorBTokens.AccessToken);
        var readTenantBRes = await client.SendAsync(readTenantBReq);
        Assert.Equal(HttpStatusCode.OK, readTenantBRes.StatusCode);
        var announcementsForB = await readTenantBRes.Content.ReadFromJsonAsync<List<AnnouncementResponse>>();
        Assert.NotNull(announcementsForB);
        Assert.Single(announcementsForB!);
        Assert.Equal("Tenant B Secret Notice", announcementsForB![0].Title);

        // Pastor A sends a valid Tenant A JWT but attempts to spoof X-Tenant-Id: TenantB
        var spoofReadReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/announcements");
        spoofReadReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", pastorATokens.AccessToken);
        spoofReadReq.Headers.Add("X-Tenant-Id", tenantB.ToString());
        var spoofReadRes = await client.SendAsync(spoofReadReq);
        Assert.Equal(HttpStatusCode.OK, spoofReadRes.StatusCode);
        var announcementsForA = await spoofReadRes.Content.ReadFromJsonAsync<List<AnnouncementResponse>>();
        Assert.NotNull(announcementsForA);
        Assert.Empty(announcementsForA!);

        // Member A cannot access Pastor-only prayer queue (403 Forbidden)
        var memberPrayerQueueReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/prayer-requests");
        memberPrayerQueueReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", memberATokens.AccessToken);
        var memberPrayerQueueRes = await client.SendAsync(memberPrayerQueueReq);
        Assert.Equal(HttpStatusCode.Forbidden, memberPrayerQueueRes.StatusCode);

        // Sign-out immediately revokes ALL of Member A's access tokens and refresh tokens
        var memberASecondSession = await AuthenticateWithPkceAsync(client, tenantA, "member.a@church.org", "MemberAPass!111");

        var signOutReq = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/sign-out");
        signOutReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", memberATokens.AccessToken);
        var signOutRes = await client.SendAsync(signOutReq);
        Assert.Equal(HttpStatusCode.NoContent, signOutRes.StatusCode);

        var meAfterSignOutReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/me");
        meAfterSignOutReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", memberATokens.AccessToken);
        var meAfterSignOutRes = await client.SendAsync(meAfterSignOutReq);
        Assert.Equal(HttpStatusCode.Unauthorized, meAfterSignOutRes.StatusCode);

        // Even another valid access token issued earlier for Member A is rejected after sign-out
        var secondTokenAfterSignOutReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/me");
        secondTokenAfterSignOutReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", memberASecondSession.AccessToken);
        var secondTokenAfterSignOutRes = await client.SendAsync(secondTokenAfterSignOutReq);
        Assert.Equal(HttpStatusCode.Unauthorized, secondTokenAfterSignOutRes.StatusCode);

        // Simulate API process restart by clearing in-memory revocation caches; durable DB revocation still rejects both tokens
        using (var scope = _factory.Services.CreateScope())
        {
            var jwtService = scope.ServiceProvider.GetRequiredService<JwtTokenService>();
            jwtService.ClearInMemoryRevocationCacheForTesting();
        }

        var meAfterRestartReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/me");
        meAfterRestartReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", memberATokens.AccessToken);
        var meAfterRestartRes = await client.SendAsync(meAfterRestartReq);
        Assert.Equal(HttpStatusCode.Unauthorized, meAfterRestartRes.StatusCode);

        var secondAfterRestartReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/me");
        secondAfterRestartReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", memberASecondSession.AccessToken);
        var secondAfterRestartRes = await client.SendAsync(secondAfterRestartReq);
        Assert.Equal(HttpStatusCode.Unauthorized, secondAfterRestartRes.StatusCode);

        var refreshAfterSignOutRes = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["client_id"] = ClientId,
            ["refresh_token"] = memberATokens.RefreshToken
        }));
        Assert.Equal(HttpStatusCode.BadRequest, refreshAfterSignOutRes.StatusCode);
    }

    [Fact]
    public async Task InteractiveBrowserAuthorizeFlow_RendersHtmlLoginFormAndRedirectsWithCode()
    {
        var tenantId = Guid.NewGuid();
        await SeedUserAsync(
            tenantId,
            "interactive.user@church.org",
            "InteractivePass!123",
            "Interactive User",
            ChurchRoleNames.Member);

        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        var (verifier, challenge) = CreatePkcePair();
        var authorizeUrl = QueryHelpers.AddQueryString("/connect/authorize", new Dictionary<string, string?>
        {
            ["client_id"] = ClientId,
            ["redirect_uri"] = RedirectUri,
            ["response_type"] = "code",
            ["scope"] = "openid profile email offline_access roles church_api",
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256",
            ["state"] = "interactive-state-1"
        });

        // 1. Browser GET without credentials returns HTML login form preserving PKCE parameters
        var getLoginRes = await client.GetAsync(authorizeUrl);
        Assert.Equal(HttpStatusCode.OK, getLoginRes.StatusCode);
        Assert.Equal("text/html", getLoginRes.Content.Headers.ContentType?.MediaType);
        var loginHtml = await getLoginRes.Content.ReadAsStringAsync();
        Assert.Contains(challenge, loginHtml);
        Assert.Contains("interactive-state-1", loginHtml);

        // 2. Submitting the HTML form with response_mode=redirect returns 302 Redirect to redirect_uri with code and state
        var postFormRes = await client.PostAsync("/connect/authorize", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["redirect_uri"] = RedirectUri,
            ["response_type"] = "code",
            ["scope"] = "openid profile email offline_access roles church_api",
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = "S256",
            ["state"] = "interactive-state-1",
            ["response_mode"] = "redirect",
            ["email"] = "interactive.user@church.org",
            ["password"] = "InteractivePass!123",
            ["tenant_id"] = tenantId.ToString()
        }));

        Assert.Equal(HttpStatusCode.Redirect, postFormRes.StatusCode);
        var location = postFormRes.Headers.Location?.ToString();
        Assert.NotNull(location);
        Assert.StartsWith(RedirectUri, location!);

        var parsedQuery = QueryHelpers.ParseQuery(new Uri(location!).Query);
        var code = parsedQuery["code"].FirstOrDefault();
        Assert.False(string.IsNullOrWhiteSpace(code));
        Assert.Equal("interactive-state-1", parsedQuery["state"].FirstOrDefault());

        // 3. Exchange redirected code with PKCE verifier
        var tokenRes = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = ClientId,
            ["code"] = code!,
            ["redirect_uri"] = RedirectUri,
            ["code_verifier"] = verifier
        }));
        Assert.Equal(HttpStatusCode.OK, tokenRes.StatusCode);
    }

    [Fact]
    public async Task OutstandingAuthorizationCode_IsInvalidatedBySignOut_AndCannotBeRedeemed()
    {
        var tenantId = Guid.NewGuid();
        await SeedUserAsync(
            tenantId,
            "signout.pkce.user@church.org",
            "SignoutPass!123",
            "Signout PKCE User",
            ChurchRoleNames.Member);

        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        // 1. Authenticate to establish an active session
        var tokens = await AuthenticateWithPkceAsync(
            client,
            tenantId,
            "signout.pkce.user@church.org",
            "SignoutPass!123");

        // 2. Obtain an authorization code in a separate pending PKCE flow
        var (pendingVerifier, pendingChallenge) = CreatePkcePair();
        var pendingAuthRes = await client.PostAsync("/connect/authorize", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = ClientId,
            ["redirect_uri"] = RedirectUri,
            ["response_type"] = "code",
            ["scope"] = "openid profile email offline_access roles church_api",
            ["code_challenge"] = pendingChallenge,
            ["code_challenge_method"] = "S256",
            ["state"] = "pending-flow-state",
            ["email"] = "signout.pkce.user@church.org",
            ["password"] = "SignoutPass!123",
            ["tenant_id"] = tenantId.ToString()
        }));

        Assert.Equal(HttpStatusCode.OK, pendingAuthRes.StatusCode);
        var authJson = await pendingAuthRes.Content.ReadFromJsonAsync<JsonElement>();
        var pendingCode = authJson.GetProperty("code").GetString();
        Assert.False(string.IsNullOrWhiteSpace(pendingCode));

        // 3. User signs out using their active session token
        var signOutReq = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/sign-out");
        signOutReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokens.AccessToken);
        var signOutRes = await client.SendAsync(signOutReq);
        Assert.Equal(HttpStatusCode.NoContent, signOutRes.StatusCode);

        // 4. Redeeming the unconsumed pending authorization code must be rejected
        var redeemRes = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = ClientId,
            ["code"] = pendingCode!,
            ["redirect_uri"] = RedirectUri,
            ["code_verifier"] = pendingVerifier
        }));

        Assert.Equal(HttpStatusCode.BadRequest, redeemRes.StatusCode);
        var errorJson = await redeemRes.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("invalid_grant", errorJson.GetProperty("error").GetString());
    }
}