using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Net;
using Church.API.Models;
using Church.Core;
using Church.Infrastructure;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace Church.API.Endpoints;

public sealed class JwtTokenService : IDisposable
{
    private readonly RSA _rsa;
    private readonly IConfiguration _configuration;
    private readonly ConcurrentDictionary<string, DateTime> _revokedAccessTokenJtis = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<Guid, long> _revokedUsersBeforeUnixMs = new();
    private readonly ConcurrentDictionary<string, byte> _issuedIssuers = new(StringComparer.OrdinalIgnoreCase);
    public SemaphoreSlim GrantSynchronizationLock { get; } = new(1, 1);

    public string KeyId { get; } = "church-oidc-rs256-key-1";

    public JwtTokenService(IConfiguration configuration, IHostEnvironment? environment = null)
    {
        _configuration = configuration;
        _rsa = RSA.Create(2048);

        var pem = _configuration["Authentication:RsaPrivateKeyPem"];
        if (string.IsNullOrWhiteSpace(pem))
        {
            var keyFilePath = _configuration["Authentication:RsaPrivateKeyPath"];
            if (!string.IsNullOrWhiteSpace(keyFilePath) && File.Exists(keyFilePath))
            {
                pem = File.ReadAllText(keyFilePath);
            }
        }

        if (!string.IsNullOrWhiteSpace(pem))
        {
            _rsa.ImportFromPem(pem);
        }
        else if (environment != null && !environment.IsDevelopment() && !environment.IsEnvironment("Testing"))
        {
            throw new InvalidOperationException(
                "A persistent RSA signing key must be configured via Authentication:RsaPrivateKeyPem or Authentication:RsaPrivateKeyPath outside Development and Testing environments.");
        }
    }

    public string GetIssuer(HttpContext? httpContext = null)
    {
        var configured = _configuration["Authentication:Issuer"];
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return configured.TrimEnd('/');
        }

        if (httpContext != null && httpContext.Request.Host.HasValue)
        {
            var scheme = string.IsNullOrWhiteSpace(httpContext.Request.Scheme) ? "https" : httpContext.Request.Scheme;
            return $"{scheme}://{httpContext.Request.Host.Value}".TrimEnd('/');
        }

        return "https://localhost";
    }

    public string Audience => _configuration["Authentication:Audience"] ?? "church_api";

    public int AccessTokenLifetimeSeconds =>
        Math.Max(60, _configuration.GetValue<int?>("Authentication:AccessTokenLifetimeSeconds") ?? 900);

    public int RefreshTokenLifetimeDays =>
        Math.Max(1, _configuration.GetValue<int?>("Authentication:RefreshTokenLifetimeDays") ?? 14);

    public bool IsAllowedClientId(string? clientId)
    {
        if (string.IsNullOrWhiteSpace(clientId))
        {
            return false;
        }

        var configured = _configuration.GetSection("Authentication:AllowedClientIds").Get<string[]>();
        var allowed = configured is { Length: > 0 }
            ? configured
            : new[] { "church_mobile_app" };

        return allowed.Contains(clientId.Trim(), StringComparer.Ordinal);
    }

    public bool IsAllowedRedirectUri(string? redirectUri)
    {
        if (string.IsNullOrWhiteSpace(redirectUri))
        {
            return false;
        }

        var configured = _configuration.GetSection("Authentication:AllowedRedirectUris").Get<string[]>();
        var allowed = configured is { Length: > 0 }
            ? configured
            : new[]
            {
                "com.church.app://oauthredirect",
                "http://localhost/callback",
                "https://localhost/callback"
            };

        return allowed.Contains(redirectUri.Trim(), StringComparer.Ordinal);
    }

    public object GetJwksDocument()
    {
        var parameters = _rsa.ExportParameters(false);
        return new
        {
            keys = new[]
            {
                new
                {
                    kty = "RSA",
                    use = "sig",
                    alg = "RS256",
                    kid = KeyId,
                    n = WebEncoders.Base64UrlEncode(parameters.Modulus!),
                    e = WebEncoders.Base64UrlEncode(parameters.Exponent!)
                }
            }
        };
    }

    public string CreateAccessToken(
        AppUser user,
        IReadOnlyList<string> roles,
        string clientId,
        string scope,
        string issuer,
        DateTime? nowUtcOverride = null)
    {
        var now = nowUtcOverride ?? DateTime.UtcNow;
        var nowOffset = new DateTimeOffset(now);
        var iat = nowOffset.ToUnixTimeSeconds();
        var iatMs = nowOffset.ToUnixTimeMilliseconds();
        var exp = nowOffset.AddSeconds(AccessTokenLifetimeSeconds).ToUnixTimeSeconds();
        var normalizedIssuer = issuer.TrimEnd('/');
        _issuedIssuers[normalizedIssuer] = 1;
        var jti = Guid.NewGuid().ToString("N");

        var payload = new Dictionary<string, object?>
        {
            ["iss"] = normalizedIssuer,
            ["aud"] = Audience,
            ["sub"] = user.Id.ToString(),
            ["jti"] = jti,
            ["iat"] = iat,
            ["iat_ms"] = iatMs,
            ["nbf"] = iat,
            ["exp"] = exp,
            ["member_id"] = user.Id.ToString(),
            ["tenant_id"] = user.TenantId.ToString(),
            ["church_id"] = user.TenantId.ToString(),
            ["email"] = user.Email,
            ["name"] = user.DisplayName,
            ["roles"] = roles,
            ["client_id"] = clientId,
            ["scope"] = scope
        };

        return SignJwt(payload);
    }

    public string CreateIdToken(
        AppUser user,
        IReadOnlyList<string> roles,
        string clientId,
        string? nonce,
        string issuer,
        DateTime? nowUtcOverride = null)
    {
        var now = nowUtcOverride ?? DateTime.UtcNow;
        var iat = new DateTimeOffset(now).ToUnixTimeSeconds();
        var exp = new DateTimeOffset(now.AddSeconds(AccessTokenLifetimeSeconds)).ToUnixTimeSeconds();

        var payload = new Dictionary<string, object?>
        {
            ["iss"] = issuer,
            ["aud"] = clientId,
            ["sub"] = user.Id.ToString(),
            ["jti"] = Guid.NewGuid().ToString("N"),
            ["iat"] = iat,
            ["nbf"] = iat,
            ["exp"] = exp,
            ["member_id"] = user.Id.ToString(),
            ["tenant_id"] = user.TenantId.ToString(),
            ["church_id"] = user.TenantId.ToString(),
            ["email"] = user.Email,
            ["name"] = user.DisplayName,
            ["roles"] = roles
        };

        if (!string.IsNullOrWhiteSpace(nonce))
        {
            payload["nonce"] = nonce;
        }

        return SignJwt(payload);
    }

    public string SignJwt(IDictionary<string, object?> payload, RSA? signingKeyOverride = null)
    {
        var header = new Dictionary<string, object>
        {
            ["alg"] = "RS256",
            ["typ"] = "JWT",
            ["kid"] = KeyId
        };

        var headerSegment = WebEncoders.Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(header));
        var payloadSegment = WebEncoders.Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(payload));
        var signingInput = Encoding.ASCII.GetBytes($"{headerSegment}.{payloadSegment}");
        var key = signingKeyOverride ?? _rsa;
        var signature = key.SignData(signingInput, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        var signatureSegment = WebEncoders.Base64UrlEncode(signature);

        return $"{headerSegment}.{payloadSegment}.{signatureSegment}";
    }

    public void RevokeAccessTokenJti(string jti, DateTime expiresAtUtc)
    {
        if (!string.IsNullOrWhiteSpace(jti))
        {
            _revokedAccessTokenJtis[jti] = expiresAtUtc;
        }
    }

    public void RevokeAllUserTokens(Guid userId)
    {
        if (userId != Guid.Empty)
        {
            _revokedUsersBeforeUnixMs[userId] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        }
    }

    public bool TryRevokeAccessToken(string token)
    {
        if (!TryValidateAccessToken(token, out var principal, out _))
        {
            return false;
        }

        var jti = principal?.FindFirst("jti")?.Value;
        if (string.IsNullOrWhiteSpace(jti))
        {
            return false;
        }

        RevokeAccessTokenJti(jti, DateTime.UtcNow.AddHours(1));
        return true;
    }

    public bool TryValidateAccessToken(
        string token,
        out ClaimsPrincipal? principal,
        out string? error,
        string? expectedIssuer = null)
    {
        principal = null;
        error = null;

        if (string.IsNullOrWhiteSpace(token))
        {
            error = "Missing bearer token.";
            return false;
        }

        var parts = token.Split('.');
        if (parts.Length != 3)
        {
            error = "Malformed JWT token.";
            return false;
        }

        byte[] headerBytes;
        byte[] payloadBytes;
        byte[] signatureBytes;
        try
        {
            headerBytes = WebEncoders.Base64UrlDecode(parts[0]);
            payloadBytes = WebEncoders.Base64UrlDecode(parts[1]);
            signatureBytes = WebEncoders.Base64UrlDecode(parts[2]);
        }
        catch
        {
            error = "Invalid base64url encoding in JWT.";
            return false;
        }

        try
        {
            using var headerDoc = JsonDocument.Parse(headerBytes);
            var alg = headerDoc.RootElement.TryGetProperty("alg", out var algProp)
                ? algProp.GetString()
                : null;
            if (!string.Equals(alg, "RS256", StringComparison.Ordinal))
            {
                error = "Unsupported JWT signing algorithm.";
                return false;
            }
        }
        catch
        {
            error = "Malformed JWT header.";
            return false;
        }

        var signingInput = Encoding.ASCII.GetBytes($"{parts[0]}.{parts[1]}");
        if (!_rsa.VerifyData(signingInput, signatureBytes, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
        {
            error = "Invalid JWT signature.";
            return false;
        }

        try
        {
            using var payloadDoc = JsonDocument.Parse(payloadBytes);
            var root = payloadDoc.RootElement;

            var issuer = root.TryGetProperty("iss", out var issProp) ? issProp.GetString() : null;
            var configuredIssuer = _configuration["Authentication:Issuer"]?.TrimEnd('/');
            var validIssuers = new HashSet<string>(_issuedIssuers.Keys, StringComparer.OrdinalIgnoreCase)
            {
                "https://localhost",
                "http://localhost"
            };
            if (!string.IsNullOrWhiteSpace(configuredIssuer))
            {
                validIssuers.Add(configuredIssuer);
            }
            if (!string.IsNullOrWhiteSpace(expectedIssuer))
            {
                validIssuers.Add(expectedIssuer.TrimEnd('/'));
            }

            if (string.IsNullOrWhiteSpace(issuer) || !validIssuers.Contains(issuer.TrimEnd('/')))
            {
                error = "Invalid token issuer.";
                return false;
            }

            var audience = root.TryGetProperty("aud", out var audProp) ? audProp.GetString() : null;
            if (!string.Equals(audience, Audience, StringComparison.Ordinal))
            {
                error = "Invalid token audience.";
                return false;
            }

            var nowUnix = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            if (!root.TryGetProperty("exp", out var expProp) || !expProp.TryGetInt64(out var expUnix) || expUnix <= nowUnix)
            {
                error = "Token has expired.";
                return false;
            }

            if (root.TryGetProperty("nbf", out var nbfProp) && nbfProp.TryGetInt64(out var nbfUnix) && nbfUnix > nowUnix + 30)
            {
                error = "Token is not yet valid.";
                return false;
            }

            var jti = root.TryGetProperty("jti", out var jtiProp) ? jtiProp.GetString() : null;
            if (string.IsNullOrWhiteSpace(jti) || _revokedAccessTokenJtis.ContainsKey(jti))
            {
                error = "Token has been revoked.";
                return false;
            }

            var subStr = root.TryGetProperty("sub", out var subProp) ? subProp.GetString() : null;
            var memberIdStr = root.TryGetProperty("member_id", out var memberProp) ? memberProp.GetString() : subStr;
            if (!Guid.TryParse(memberIdStr, out var memberId) || memberId == Guid.Empty)
            {
                error = "Token is missing a valid member_id/sub claim.";
                return false;
            }

            long tokenIssuedAtMs = 0;
            if (root.TryGetProperty("iat_ms", out var iatMsProp) && iatMsProp.TryGetInt64(out var parsedIatMs))
            {
                tokenIssuedAtMs = parsedIatMs;
            }
            else if (root.TryGetProperty("iat", out var iatProp) && iatProp.TryGetInt64(out var parsedIatSec))
            {
                tokenIssuedAtMs = parsedIatSec * 1000L;
            }

            if (_revokedUsersBeforeUnixMs.TryGetValue(memberId, out var revokedBeforeMs) &&
                tokenIssuedAtMs <= revokedBeforeMs)
            {
                error = "User session has been revoked.";
                return false;
            }

            var tenantIdStr = root.TryGetProperty("tenant_id", out var tenantProp)
                ? tenantProp.GetString()
                : (root.TryGetProperty("church_id", out var churchProp) ? churchProp.GetString() : null);

            if (!Guid.TryParse(tenantIdStr, out var tenantId) || tenantId == Guid.Empty)
            {
                error = "Token is missing a valid tenant_id claim.";
                return false;
            }

            var email = root.TryGetProperty("email", out var emailProp) ? emailProp.GetString() ?? string.Empty : string.Empty;
            var name = root.TryGetProperty("name", out var nameProp) ? nameProp.GetString() ?? string.Empty : string.Empty;

            var claims = new List<Claim>
            {
                new("auth_mode", "jwt"),
                new("jti", jti),
                new("iat_ms", tokenIssuedAtMs.ToString()),
                new(ClaimTypes.NameIdentifier, memberId.ToString()),
                new("sub", memberId.ToString()),
                new("member_id", memberId.ToString()),
                new("tenant_id", tenantId.ToString()),
                new("church_id", tenantId.ToString())
            };

            if (!string.IsNullOrWhiteSpace(email))
            {
                claims.Add(new Claim(ClaimTypes.Email, email));
                claims.Add(new Claim("email", email));
            }

            if (!string.IsNullOrWhiteSpace(name))
            {
                claims.Add(new Claim(ClaimTypes.Name, name));
                claims.Add(new Claim("name", name));
            }

            if (root.TryGetProperty("roles", out var rolesProp) && rolesProp.ValueKind == JsonValueKind.Array)
            {
                foreach (var roleElement in rolesProp.EnumerateArray())
                {
                    var roleValue = roleElement.GetString()?.Trim();
                    if (!string.IsNullOrWhiteSpace(roleValue))
                    {
                        claims.Add(new Claim(ClaimTypes.Role, roleValue));
                        claims.Add(new Claim("roles", roleValue));
                    }
                }
            }

            var identity = new ClaimsIdentity(claims, "HeaderOrBearer", ClaimTypes.Name, ClaimTypes.Role);
            principal = new ClaimsPrincipal(identity);
            return true;
        }
        catch
        {
            error = "Failed to parse JWT payload.";
            return false;
        }
    }

    public static string ComputeSha256Base64Url(string input)
    {
        var bytes = SHA256.HashData(Encoding.ASCII.GetBytes(input));
        return WebEncoders.Base64UrlEncode(bytes);
    }

    public static string GenerateSecureRandomToken(int byteLength = 32)
    {
        var bytes = RandomNumberGenerator.GetBytes(byteLength);
        return WebEncoders.Base64UrlEncode(bytes);
    }

    public async Task<bool> IsPrincipalRevokedInStoreAsync(
        ApplicationDbContext db,
        ClaimsPrincipal principal,
        CancellationToken cancellationToken = default)
    {
        var jti = principal.FindFirst("jti")?.Value;
        var memberIdStr = principal.FindFirst("member_id")?.Value ??
                          principal.FindFirst("sub")?.Value ??
                          principal.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (!Guid.TryParse(memberIdStr, out var memberId) || memberId == Guid.Empty)
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(jti))
        {
            if (_revokedAccessTokenJtis.ContainsKey(jti))
            {
                return true;
            }

            var jtiMarkerHash = ComputeSha256Base64Url($"revoked-jti:{jti}");
            var jtiRevokedInDb = await db.OidcRefreshTokens
                .IgnoreQueryFilters()
                .AsNoTracking()
                .AnyAsync(t => t.TokenHash == jtiMarkerHash && t.RevokedAt != null, cancellationToken);
            if (jtiRevokedInDb)
            {
                _revokedAccessTokenJtis[jti] = DateTime.UtcNow.AddHours(1);
                return true;
            }
        }

        long tokenIssuedAtMs = 0;
        var iatMsClaim = principal.FindFirst("iat_ms")?.Value;
        _ = long.TryParse(iatMsClaim, out tokenIssuedAtMs);

        return await IsUserRevokedAtAsync(db, memberId, tokenIssuedAtMs, cancellationToken);
    }

    public async Task<bool> IsUserRevokedAtAsync(
        ApplicationDbContext db,
        Guid memberId,
        long timestampMs,
        CancellationToken cancellationToken = default)
    {
        if (memberId == Guid.Empty)
        {
            return false;
        }

        if (_revokedUsersBeforeUnixMs.TryGetValue(memberId, out var memWatermark) &&
            timestampMs <= memWatermark)
        {
            return true;
        }

        var userCutoffMarkers = await db.OidcRefreshTokens
            .IgnoreQueryFilters()
            .AsNoTracking()
            .Where(t => t.UserId == memberId && t.Scope == "revoked_user" && t.ReplacedByTokenHash != null)
            .Select(t => t.ReplacedByTokenHash!)
            .ToListAsync(cancellationToken);

        long maxPersistedCutoffMs = 0;
        foreach (var marker in userCutoffMarkers)
        {
            if (long.TryParse(marker, out var parsedCutoff) && parsedCutoff > maxPersistedCutoffMs)
            {
                maxPersistedCutoffMs = parsedCutoff;
            }
        }

        if (maxPersistedCutoffMs > 0)
        {
            _revokedUsersBeforeUnixMs[memberId] = maxPersistedCutoffMs;
            if (timestampMs <= maxPersistedCutoffMs)
            {
                return true;
            }
        }

        return false;
    }

    public void ClearInMemoryRevocationCacheForTesting()
    {
        _revokedAccessTokenJtis.Clear();
        _revokedUsersBeforeUnixMs.Clear();
    }

    public void Dispose()
    {
        _rsa.Dispose();
    }
}

public static class IdentityService
{
    private static readonly PasswordHasher<AppUser> PasswordHasher = new();

    public static string HashPassword(AppUser user, string password) =>
        PasswordHasher.HashPassword(user, password);

    public static bool VerifyPassword(AppUser user, string password)
    {
        if (string.IsNullOrWhiteSpace(user.PasswordHash) || string.IsNullOrEmpty(password))
        {
            return false;
        }

        var result = PasswordHasher.VerifyHashedPassword(user, user.PasswordHash, password);
        return result == PasswordVerificationResult.Success ||
               result == PasswordVerificationResult.SuccessRehashNeeded;
    }

    public static async Task<AppUser> ProvisionUserAsync(
        ApplicationDbContext db,
        Guid tenantId,
        string email,
        string password,
        string displayName,
        IEnumerable<string> roles,
        Guid? userId = null)
    {
        var normalizedEmail = email.Trim().ToUpperInvariant();
        var user = await db.AppUsers
            .IgnoreQueryFilters()
            .Include(u => u.UserRoles)
            .FirstOrDefaultAsync(u => u.TenantId == tenantId && u.NormalizedEmail == normalizedEmail);

        if (user == null)
        {
            user = new AppUser
            {
                Id = userId ?? Guid.NewGuid(),
                TenantId = tenantId,
                Email = email.Trim(),
                NormalizedEmail = normalizedEmail,
                DisplayName = displayName.Trim(),
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            };
            user.PasswordHash = HashPassword(user, password);
            db.AppUsers.Add(user);
        }
        else
        {
            user.Email = email.Trim();
            user.DisplayName = displayName.Trim();
            user.IsActive = true;
            user.PasswordHash = HashPassword(user, password);
        }

        var distinctRoles = roles
            .Where(r => !string.IsNullOrWhiteSpace(r))
            .Select(r => r.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (distinctRoles.Count == 0)
        {
            distinctRoles.Add(ChurchRoleNames.Member);
        }

        foreach (var roleName in distinctRoles)
        {
            var normalizedRoleName = roleName.ToUpperInvariant();
            var role = await db.AppRoles
                .IgnoreQueryFilters()
                .FirstOrDefaultAsync(r => r.TenantId == tenantId && r.NormalizedName == normalizedRoleName);

            if (role == null)
            {
                role = new AppRole
                {
                    Id = Guid.NewGuid(),
                    TenantId = tenantId,
                    Name = roleName,
                    NormalizedName = normalizedRoleName
                };
                db.AppRoles.Add(role);
            }

            if (!user.UserRoles.Any(ur => ur.RoleId == role.Id))
            {
                db.AppUserRoles.Add(new AppUserRole
                {
                    Id = Guid.NewGuid(),
                    TenantId = tenantId,
                    UserId = user.Id,
                    RoleId = role.Id
                });
            }
        }

        await db.SaveChangesAsync();
        return user;
    }
}

public static class AuthEndpoints
{
    private static readonly string[] SupportedScopes =
    {
        "openid",
        "profile",
        "email",
        "offline_access",
        "roles",
        "church_api"
    };

    public static void MapAuthEndpoints(this WebApplication app)
    {
        // 1. OIDC Discovery Document
        app.MapGet("/.well-known/openid-configuration", (HttpContext httpContext, JwtTokenService jwtService) =>
        {
            var issuer = jwtService.GetIssuer(httpContext);
            var doc = new OidcDiscoveryDocument(
                Issuer: issuer,
                AuthorizationEndpoint: $"{issuer}/connect/authorize",
                TokenEndpoint: $"{issuer}/connect/token",
                UserInfoEndpoint: $"{issuer}/connect/userinfo",
                RevocationEndpoint: $"{issuer}/connect/revoke",
                JwksUri: $"{issuer}/.well-known/jwks.json",
                ResponseTypesSupported: new[] { "code" },
                SubjectTypesSupported: new[] { "public" },
                IdTokenSigningAlgValuesSupported: new[] { "RS256" },
                GrantTypesSupported: new[] { "authorization_code", "refresh_token" },
                CodeChallengeMethodsSupported: new[] { "S256" },
                ScopesSupported: SupportedScopes,
                TokenEndpointAuthMethodsSupported: new[] { "none" }
            );
            return Results.Ok(doc);
        }).AllowAnonymous();

        // 2. JSON Web Key Set (JWKS)
        app.MapGet("/.well-known/jwks.json", (JwtTokenService jwtService) =>
            Results.Ok(jwtService.GetJwksDocument())).AllowAnonymous();

        // 3. OIDC Authorization Endpoint (Authorization Code + PKCE S256)
        app.MapMethods("/connect/authorize", new[] { "GET", "POST" }, async (
            HttpContext httpContext,
            ApplicationDbContext db,
            JwtTokenService jwtService) =>
        {
            var req = await ReadAuthorizeRequestAsync(httpContext);

            if (!string.Equals(req.ResponseType, "code", StringComparison.Ordinal))
            {
                return Results.BadRequest(new OidcErrorResponse(
                    "unsupported_response_type",
                    "Only response_type=code is supported."));
            }

            if (!jwtService.IsAllowedClientId(req.ClientId))
            {
                return Results.BadRequest(new OidcErrorResponse(
                    "unauthorized_client",
                    "Unknown or unauthorized client_id."));
            }

            if (!jwtService.IsAllowedRedirectUri(req.RedirectUri))
            {
                return Results.BadRequest(new OidcErrorResponse(
                    "invalid_request",
                    "Invalid or unregistered redirect_uri."));
            }

            if (string.IsNullOrWhiteSpace(req.CodeChallenge) ||
                !string.Equals(req.CodeChallengeMethod, "S256", StringComparison.Ordinal))
            {
                return Results.BadRequest(new OidcErrorResponse(
                    "invalid_request",
                    "PKCE with code_challenge and code_challenge_method=S256 is required."));
            }

            AppUser? authenticatedUser = null;

            if (!string.IsNullOrWhiteSpace(req.Email) && !string.IsNullOrEmpty(req.Password))
            {
                var normalizedEmail = req.Email.Trim().ToUpperInvariant();
                var query = db.AppUsers
                    .IgnoreQueryFilters()
                    .Where(u => u.NormalizedEmail == normalizedEmail && u.IsActive);

                if (req.TenantId.HasValue && req.TenantId.Value != Guid.Empty)
                {
                    var requestedTenantId = req.TenantId.Value;
                    query = query.Where(u => u.TenantId == requestedTenantId);
                }

                var candidates = await query.Take(2).ToListAsync();
                if (candidates.Count > 1)
                {
                    return Results.BadRequest(new OidcErrorResponse(
                        "invalid_request",
                        "Multiple church tenants match this email; specify tenant_id."));
                }

                var candidate = candidates.FirstOrDefault();
                if (candidate == null || !IdentityService.VerifyPassword(candidate, req.Password))
                {
                    return Results.Json(
                        new OidcErrorResponse("access_denied", "Invalid credentials."),
                        statusCode: StatusCodes.Status401Unauthorized);
                }

                authenticatedUser = candidate;
            }
            else if (httpContext.User.Identity?.IsAuthenticated == true)
            {
                var userIdStr = httpContext.User.FindFirst(ClaimTypes.NameIdentifier)?.Value ??
                                httpContext.User.FindFirst("sub")?.Value;
                var tenantIdStr = httpContext.User.FindFirst("tenant_id")?.Value ??
                                  httpContext.User.FindFirst("church_id")?.Value;
                if (Guid.TryParse(userIdStr, out var userId) && Guid.TryParse(tenantIdStr, out var tenantId))
                {
                    authenticatedUser = await db.AppUsers
                        .IgnoreQueryFilters()
                        .FirstOrDefaultAsync(u => u.Id == userId && u.TenantId == tenantId && u.IsActive);
                }
            }

            if (authenticatedUser == null)
            {
                if (HttpMethods.IsGet(httpContext.Request.Method) &&
                    !string.Equals(req.ResponseMode, "json", StringComparison.OrdinalIgnoreCase))
                {
                    var loginHtml = BuildInteractiveAuthorizeLoginHtml(req);
                    return Results.Content(loginHtml, "text/html; charset=utf-8");
                }

                return Results.Json(
                    new OidcErrorResponse("access_denied", "User authentication is required."),
                    statusCode: StatusCodes.Status401Unauthorized);
            }

            var rawCode = JwtTokenService.GenerateSecureRandomToken(32);
            var codeHash = JwtTokenService.ComputeSha256Base64Url(rawCode);
            var normalizedScope = string.IsNullOrWhiteSpace(req.Scope)
                ? "openid profile email offline_access roles church_api"
                : req.Scope.Trim();

            var authCode = new OidcAuthorizationCode
            {
                Id = Guid.NewGuid(),
                TenantId = authenticatedUser.TenantId,
                UserId = authenticatedUser.Id,
                CodeHash = codeHash,
                ClientId = req.ClientId!.Trim(),
                RedirectUri = req.RedirectUri!.Trim(),
                CodeChallenge = req.CodeChallenge.Trim(),
                CodeChallengeMethod = "S256",
                Scope = normalizedScope,
                Nonce = string.IsNullOrWhiteSpace(req.Nonce) ? null : req.Nonce.Trim(),
                CreatedAt = DateTime.UtcNow,
                ExpiresAt = DateTime.UtcNow.AddMinutes(5)
            };

            db.OidcAuthorizationCodes.Add(authCode);
            await db.SaveChangesAsync();

            var redirectParams = new Dictionary<string, string?> { ["code"] = rawCode };
            if (!string.IsNullOrWhiteSpace(req.State))
            {
                redirectParams["state"] = req.State;
            }

            var redirectUriWithCode = QueryHelpers.AddQueryString(req.RedirectUri!.Trim(), redirectParams);
            httpContext.Response.Headers.Location = redirectUriWithCode;

            if (string.Equals(req.ResponseMode, "redirect", StringComparison.OrdinalIgnoreCase))
            {
                return Results.Redirect(redirectUriWithCode);
            }

            return Results.Ok(new OidcAuthorizeResponse(
                Code: rawCode,
                State: req.State,
                RedirectUri: redirectUriWithCode));
        }).AllowAnonymous();

        // 4. OIDC Token Endpoint (authorization_code with PKCE S256 & refresh_token rotation)
        app.MapPost("/connect/token", async (
            HttpContext httpContext,
            ApplicationDbContext db,
            JwtTokenService jwtService) =>
        {
            var req = await ReadTokenRequestAsync(httpContext);

            if (string.Equals(req.GrantType, "password", StringComparison.OrdinalIgnoreCase))
            {
                return Results.BadRequest(new OidcErrorResponse(
                    "unsupported_grant_type",
                    "Resource Owner Password Credentials (ROPC) is disabled. Use authorization_code with PKCE."));
            }

            if (!jwtService.IsAllowedClientId(req.ClientId))
            {
                return Results.BadRequest(new OidcErrorResponse(
                    "invalid_client",
                    "Unknown or unauthorized client_id."));
            }

            var clientId = req.ClientId!.Trim();
            var issuer = jwtService.GetIssuer(httpContext);

            if (string.Equals(req.GrantType, "authorization_code", StringComparison.Ordinal))
            {
                if (string.IsNullOrWhiteSpace(req.Code) ||
                    string.IsNullOrWhiteSpace(req.RedirectUri) ||
                    string.IsNullOrWhiteSpace(req.CodeVerifier))
                {
                    return Results.BadRequest(new OidcErrorResponse(
                        "invalid_request",
                        "code, redirect_uri, and code_verifier are required for authorization_code grant."));
                }

                await jwtService.GrantSynchronizationLock.WaitAsync(httpContext.RequestAborted);
                try
                {
                    var codeHash = JwtTokenService.ComputeSha256Base64Url(req.Code.Trim());
                    var authCode = await db.OidcAuthorizationCodes
                        .IgnoreQueryFilters()
                        .FirstOrDefaultAsync(c => c.CodeHash == codeHash);

                    if (authCode == null)
                    {
                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "Authorization code is invalid."));
                    }

                    if (authCode.ConsumedAt.HasValue)
                    {
                        // Replay of a consumed authorization code: revoke all tokens issued from this code
                        var tokensToRevoke = await db.OidcRefreshTokens
                            .IgnoreQueryFilters()
                            .Where(t => t.AuthorizationCodeId == authCode.Id && t.RevokedAt == null)
                            .ToListAsync();
                        foreach (var token in tokensToRevoke)
                        {
                            token.RevokedAt = DateTime.UtcNow;
                        }
                        await db.SaveChangesAsync();

                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "Authorization code has already been used."));
                    }

                    if (authCode.ExpiresAt <= DateTime.UtcNow ||
                        !string.Equals(authCode.ClientId, clientId, StringComparison.Ordinal) ||
                        !string.Equals(authCode.RedirectUri, req.RedirectUri.Trim(), StringComparison.Ordinal))
                    {
                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "Authorization code is expired or mismatched."));
                    }

                    // Verify PKCE S256 code_verifier
                    var computedChallenge = JwtTokenService.ComputeSha256Base64Url(req.CodeVerifier.Trim());
                    var expectedBytes = Encoding.ASCII.GetBytes(authCode.CodeChallenge);
                    var computedBytes = Encoding.ASCII.GetBytes(computedChallenge);
                    if (!CryptographicOperations.FixedTimeEquals(expectedBytes, computedBytes))
                    {
                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "PKCE code_verifier verification failed."));
                    }

                    var codeCreatedMs = new DateTimeOffset(authCode.CreatedAt).ToUnixTimeMilliseconds();
                    if (await jwtService.IsUserRevokedAtAsync(db, authCode.UserId, codeCreatedMs, httpContext.RequestAborted))
                    {
                        authCode.ConsumedAt = DateTime.UtcNow;
                        await db.SaveChangesAsync();
                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "Authorization code is invalid due to a subsequent sign-out."));
                    }

                    var user = await db.AppUsers
                        .IgnoreQueryFilters()
                        .FirstOrDefaultAsync(u => u.Id == authCode.UserId && u.TenantId == authCode.TenantId && u.IsActive);

                    if (user == null)
                    {
                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "User account is inactive or no longer exists."));
                    }

                    authCode.ConsumedAt = DateTime.UtcNow;

                    var roles = await LoadUserRolesAsync(db, user.Id, user.TenantId);
                    var rawRefreshToken = JwtTokenService.GenerateSecureRandomToken(32);
                    var refreshTokenHash = JwtTokenService.ComputeSha256Base64Url(rawRefreshToken);

                    db.OidcRefreshTokens.Add(new OidcRefreshToken
                    {
                        Id = Guid.NewGuid(),
                        TenantId = user.TenantId,
                        UserId = user.Id,
                        AuthorizationCodeId = authCode.Id,
                        TokenHash = refreshTokenHash,
                        ClientId = clientId,
                        Scope = authCode.Scope,
                        CreatedAt = DateTime.UtcNow,
                        ExpiresAt = DateTime.UtcNow.AddDays(jwtService.RefreshTokenLifetimeDays)
                    });

                    await db.SaveChangesAsync();

                    var accessToken = jwtService.CreateAccessToken(user, roles, clientId, authCode.Scope, issuer);
                    var idToken = jwtService.CreateIdToken(user, roles, clientId, authCode.Nonce, issuer);

                    return Results.Ok(new OidcTokenResponse(
                        AccessToken: accessToken,
                        IdToken: idToken,
                        RefreshToken: rawRefreshToken,
                        TokenType: "Bearer",
                        ExpiresIn: jwtService.AccessTokenLifetimeSeconds,
                        Scope: authCode.Scope
                    ));
                }
                finally
                {
                    jwtService.GrantSynchronizationLock.Release();
                }
            }

            if (string.Equals(req.GrantType, "refresh_token", StringComparison.Ordinal))
            {
                if (string.IsNullOrWhiteSpace(req.RefreshToken))
                {
                    return Results.BadRequest(new OidcErrorResponse(
                        "invalid_request",
                        "refresh_token is required."));
                }

                await jwtService.GrantSynchronizationLock.WaitAsync(httpContext.RequestAborted);
                try
                {
                    var tokenHash = JwtTokenService.ComputeSha256Base64Url(req.RefreshToken.Trim());
                    var storedToken = await db.OidcRefreshTokens
                        .IgnoreQueryFilters()
                        .FirstOrDefaultAsync(t => t.TokenHash == tokenHash);

                    if (storedToken == null || !string.Equals(storedToken.ClientId, clientId, StringComparison.Ordinal))
                    {
                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "Refresh token is invalid."));
                    }

                    if (storedToken.ConsumedAt.HasValue)
                    {
                        // Replay of a rotated refresh token: revoke all active tokens for this user + client
                        var activeUserTokens = await db.OidcRefreshTokens
                            .IgnoreQueryFilters()
                            .Where(t => t.UserId == storedToken.UserId &&
                                        t.TenantId == storedToken.TenantId &&
                                        t.ClientId == clientId &&
                                        t.RevokedAt == null)
                            .ToListAsync();
                        foreach (var activeToken in activeUserTokens)
                        {
                            activeToken.RevokedAt = DateTime.UtcNow;
                        }
                        await db.SaveChangesAsync();

                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "Refresh token has already been rotated."));
                    }

                    if (storedToken.RevokedAt.HasValue || storedToken.ExpiresAt <= DateTime.UtcNow)
                    {
                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "Refresh token is expired or revoked."));
                    }

                    var tokenCreatedMs = new DateTimeOffset(storedToken.CreatedAt).ToUnixTimeMilliseconds();
                    if (await jwtService.IsUserRevokedAtAsync(db, storedToken.UserId, tokenCreatedMs, httpContext.RequestAborted))
                    {
                        storedToken.RevokedAt = DateTime.UtcNow;
                        await db.SaveChangesAsync();
                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "Refresh token is invalid due to a subsequent sign-out."));
                    }

                    var user = await db.AppUsers
                        .IgnoreQueryFilters()
                        .FirstOrDefaultAsync(u => u.Id == storedToken.UserId && u.TenantId == storedToken.TenantId && u.IsActive);

                    if (user == null)
                    {
                        return Results.BadRequest(new OidcErrorResponse(
                            "invalid_grant",
                            "User account is inactive or no longer exists."));
                    }

                    var newRawRefreshToken = JwtTokenService.GenerateSecureRandomToken(32);
                    var newRefreshTokenHash = JwtTokenService.ComputeSha256Base64Url(newRawRefreshToken);

                    storedToken.ConsumedAt = DateTime.UtcNow;
                    storedToken.ReplacedByTokenHash = newRefreshTokenHash;

                    db.OidcRefreshTokens.Add(new OidcRefreshToken
                    {
                        Id = Guid.NewGuid(),
                        TenantId = user.TenantId,
                        UserId = user.Id,
                        AuthorizationCodeId = storedToken.AuthorizationCodeId,
                        TokenHash = newRefreshTokenHash,
                        ClientId = clientId,
                        Scope = storedToken.Scope,
                        CreatedAt = DateTime.UtcNow,
                        ExpiresAt = DateTime.UtcNow.AddDays(jwtService.RefreshTokenLifetimeDays)
                    });

                    await db.SaveChangesAsync();

                    var roles = await LoadUserRolesAsync(db, user.Id, user.TenantId);
                    var accessToken = jwtService.CreateAccessToken(user, roles, clientId, storedToken.Scope, issuer);
                    var idToken = jwtService.CreateIdToken(user, roles, clientId, null, issuer);

                    return Results.Ok(new OidcTokenResponse(
                        AccessToken: accessToken,
                        IdToken: idToken,
                        RefreshToken: newRawRefreshToken,
                        TokenType: "Bearer",
                        ExpiresIn: jwtService.AccessTokenLifetimeSeconds,
                        Scope: storedToken.Scope
                    ));
                }
                finally
                {
                    jwtService.GrantSynchronizationLock.Release();
                }
            }

            return Results.BadRequest(new OidcErrorResponse(
                "unsupported_grant_type",
                "Only authorization_code and refresh_token grant types are supported."));
        }).AllowAnonymous();

        // 5. OIDC UserInfo Endpoint
        app.MapGet("/connect/userinfo", (ClaimsPrincipal user) =>
        {
            if (!TryExtractAuthenticatedIdentity(user, out var memberId, out var tenantId, out var email, out var displayName, out var roles))
            {
                return Results.Unauthorized();
            }

            return Results.Ok(new OidcUserInfoResponse(
                Sub: memberId,
                MemberId: memberId,
                TenantId: tenantId,
                ChurchId: tenantId,
                Roles: roles,
                Email: email,
                Name: displayName
            ));
        }).RequireAuthorization();

        // 6. OIDC Token Revocation Endpoint (RFC 7009)
        app.MapPost("/connect/revoke", async (
            HttpContext httpContext,
            ApplicationDbContext db,
            JwtTokenService jwtService) =>
        {
            var req = await ReadRevokeRequestAsync(httpContext);
            if (!jwtService.IsAllowedClientId(req.ClientId))
            {
                return Results.BadRequest(new OidcErrorResponse(
                    "invalid_client",
                    "Unknown or unauthorized client_id."));
            }

            if (string.IsNullOrWhiteSpace(req.Token))
            {
                return Results.Ok();
            }

            var rawToken = req.Token.Trim();
            await jwtService.GrantSynchronizationLock.WaitAsync(httpContext.RequestAborted);
            try
            {
                var tokenHash = JwtTokenService.ComputeSha256Base64Url(rawToken);
                var storedRefresh = await db.OidcRefreshTokens
                    .IgnoreQueryFilters()
                    .FirstOrDefaultAsync(t => t.TokenHash == tokenHash && t.ClientId == req.ClientId!.Trim());

                if (storedRefresh != null && !storedRefresh.RevokedAt.HasValue)
                {
                    var nowUtc = DateTime.UtcNow;
                    var nowUnixMs = new DateTimeOffset(nowUtc).ToUnixTimeMilliseconds();

                    // Revoke all active refresh tokens for this user
                    var activeTokens = await db.OidcRefreshTokens
                        .IgnoreQueryFilters()
                        .Where(t => t.UserId == storedRefresh.UserId && t.TenantId == storedRefresh.TenantId && t.RevokedAt == null)
                        .ToListAsync();

                    foreach (var token in activeTokens)
                    {
                        token.RevokedAt = nowUtc;
                    }

                    // Invalidate outstanding unconsumed authorization codes for this user
                    var outstandingCodes = await db.OidcAuthorizationCodes
                        .IgnoreQueryFilters()
                        .Where(c => c.UserId == storedRefresh.UserId && c.TenantId == storedRefresh.TenantId && c.ConsumedAt == null)
                        .ToListAsync();

                    foreach (var code in outstandingCodes)
                    {
                        code.ConsumedAt = nowUtc;
                    }

                    // Record user revocation watermark so active access tokens and pending codes cannot be redeemed
                    jwtService.RevokeAllUserTokens(storedRefresh.UserId);
                    var userCutOffHash = JwtTokenService.ComputeSha256Base64Url($"revoked-user:{storedRefresh.UserId:N}:{nowUnixMs}:{Guid.NewGuid():N}");
                    db.OidcRefreshTokens.Add(new OidcRefreshToken
                    {
                        Id = Guid.NewGuid(),
                        TenantId = storedRefresh.TenantId,
                        UserId = storedRefresh.UserId,
                        TokenHash = userCutOffHash,
                        ClientId = req.ClientId!.Trim(),
                        Scope = "revoked_user",
                        CreatedAt = nowUtc,
                        ExpiresAt = nowUtc.AddDays(jwtService.RefreshTokenLifetimeDays),
                        RevokedAt = nowUtc,
                        ReplacedByTokenHash = nowUnixMs.ToString()
                    });

                    await db.SaveChangesAsync();
                }
                else if (jwtService.TryValidateAccessToken(rawToken, out var revokedPrincipal, out _) &&
                         revokedPrincipal != null &&
                         TryExtractAuthenticatedIdentity(revokedPrincipal, out var revokedUserId, out var revokedTenantId, out _, out _, out _))
                {
                    var revokedJti = revokedPrincipal.FindFirst("jti")?.Value;
                    if (!string.IsNullOrWhiteSpace(revokedJti))
                    {
                        jwtService.RevokeAccessTokenJti(revokedJti, DateTime.UtcNow.AddHours(1));
                        var jtiMarkerHash = JwtTokenService.ComputeSha256Base64Url($"revoked-jti:{revokedJti}");
                        var existingJtiMarker = await db.OidcRefreshTokens
                            .IgnoreQueryFilters()
                            .FirstOrDefaultAsync(t => t.TokenHash == jtiMarkerHash);
                        if (existingJtiMarker == null)
                        {
                            var nowUtc = DateTime.UtcNow;
                            db.OidcRefreshTokens.Add(new OidcRefreshToken
                            {
                                Id = Guid.NewGuid(),
                                TenantId = revokedTenantId,
                                UserId = revokedUserId,
                                TokenHash = jtiMarkerHash,
                                ClientId = req.ClientId!.Trim(),
                                Scope = "revoked_jti",
                                CreatedAt = nowUtc,
                                ExpiresAt = nowUtc.AddHours(1),
                                RevokedAt = nowUtc
                            });
                            await db.SaveChangesAsync();
                        }
                    }
                }
            }
            finally
            {
                jwtService.GrantSynchronizationLock.Release();
            }

            return Results.Ok();
        }).AllowAnonymous();

        // 7. Authenticated Session Contract Endpoints (/api/v1/auth/me & /api/v1/auth/sign-out)
        var authApiGroup = app.MapGroup("/api/v1/auth")
            .RequireAuthorization();

        authApiGroup.MapGet("/me", (ClaimsPrincipal user) =>
        {
            if (!TryExtractAuthenticatedIdentity(user, out var memberId, out var tenantId, out var email, out var displayName, out var roles))
            {
                return Results.Unauthorized();
            }

            return Results.Ok(new CurrentUserResponse(
                MemberId: memberId,
                TenantId: tenantId,
                Email: email,
                DisplayName: displayName,
                Roles: roles
            ));
        });

        authApiGroup.MapPost("/sign-out", async (
            HttpContext httpContext,
            ClaimsPrincipal user,
            ApplicationDbContext db,
            JwtTokenService jwtService) =>
        {
            if (!TryExtractAuthenticatedIdentity(user, out var memberId, out var tenantId, out _, out _, out _))
            {
                return Results.Unauthorized();
            }

            await jwtService.GrantSynchronizationLock.WaitAsync(httpContext.RequestAborted);
            try
            {
                var nowUtc = DateTime.UtcNow;
                var nowUnixMs = new DateTimeOffset(nowUtc).ToUnixTimeMilliseconds();
                var jti = user.FindFirst("jti")?.Value;
                if (!string.IsNullOrWhiteSpace(jti))
                {
                    jwtService.RevokeAccessTokenJti(jti, nowUtc.AddHours(1));
                    var jtiMarkerHash = JwtTokenService.ComputeSha256Base64Url($"revoked-jti:{jti}");
                    var existingJtiMarker = await db.OidcRefreshTokens
                        .IgnoreQueryFilters()
                        .FirstOrDefaultAsync(t => t.TokenHash == jtiMarkerHash);
                    if (existingJtiMarker == null)
                    {
                        db.OidcRefreshTokens.Add(new OidcRefreshToken
                        {
                            Id = Guid.NewGuid(),
                            TenantId = tenantId,
                            UserId = memberId,
                            TokenHash = jtiMarkerHash,
                            ClientId = "sign_out",
                            Scope = "revoked_jti",
                            CreatedAt = nowUtc,
                            ExpiresAt = nowUtc.AddHours(1),
                            RevokedAt = nowUtc
                        });
                    }
                }
                jwtService.RevokeAllUserTokens(memberId);

                var activeTokens = await db.OidcRefreshTokens
                    .IgnoreQueryFilters()
                    .Where(t => t.UserId == memberId && t.TenantId == tenantId && t.RevokedAt == null)
                    .ToListAsync();

                foreach (var token in activeTokens)
                {
                    token.RevokedAt = nowUtc;
                }

                var outstandingCodes = await db.OidcAuthorizationCodes
                    .IgnoreQueryFilters()
                    .Where(c => c.UserId == memberId && c.TenantId == tenantId && c.ConsumedAt == null)
                    .ToListAsync();

                foreach (var code in outstandingCodes)
                {
                    code.ConsumedAt = nowUtc;
                }

                // Persist durable session-wide revocation watermark in the database so API restarts preserve sign-out revocation
                var userCutOffHash = JwtTokenService.ComputeSha256Base64Url($"revoked-user:{memberId:N}:{nowUnixMs}:{Guid.NewGuid():N}");
                db.OidcRefreshTokens.Add(new OidcRefreshToken
                {
                    Id = Guid.NewGuid(),
                    TenantId = tenantId,
                    UserId = memberId,
                    TokenHash = userCutOffHash,
                    ClientId = "sign_out",
                    Scope = "revoked_user",
                    CreatedAt = nowUtc,
                    ExpiresAt = nowUtc.AddDays(jwtService.RefreshTokenLifetimeDays),
                    RevokedAt = nowUtc,
                    ReplacedByTokenHash = nowUnixMs.ToString()
                });

                await db.SaveChangesAsync();
                return Results.NoContent();
            }
            finally
            {
                jwtService.GrantSynchronizationLock.Release();
            }
        });
    }

    private static bool TryExtractAuthenticatedIdentity(
        ClaimsPrincipal user,
        out Guid memberId,
        out Guid tenantId,
        out string email,
        out string displayName,
        out IReadOnlyList<string> roles)
    {
        memberId = Guid.Empty;
        tenantId = Guid.Empty;
        email = string.Empty;
        displayName = string.Empty;
        roles = Array.Empty<string>();

        var memberIdStr = user.FindFirst("member_id")?.Value ??
                          user.FindFirst("sub")?.Value ??
                          user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var tenantIdStr = user.FindFirst("tenant_id")?.Value ??
                          user.FindFirst("church_id")?.Value;

        if (!Guid.TryParse(memberIdStr, out memberId) || memberId == Guid.Empty ||
            !Guid.TryParse(tenantIdStr, out tenantId) || tenantId == Guid.Empty)
        {
            return false;
        }

        email = user.FindFirst(ClaimTypes.Email)?.Value ??
                user.FindFirst("email")?.Value ??
                string.Empty;
        displayName = user.FindFirst(ClaimTypes.Name)?.Value ??
                      user.FindFirst("name")?.Value ??
                      "Church Member";

        var extractedRoles = user.FindAll(ClaimTypes.Role)
            .Select(c => c.Value)
            .Concat(user.FindAll("roles").Select(c => c.Value))
            .Where(r => !string.IsNullOrWhiteSpace(r))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (extractedRoles.Count == 0)
        {
            extractedRoles.Add(ChurchRoleNames.Member);
        }

        roles = extractedRoles;
        return true;
    }

    private static async Task<IReadOnlyList<string>> LoadUserRolesAsync(
        ApplicationDbContext db,
        Guid userId,
        Guid tenantId)
    {
        var roleNames = await db.AppUserRoles
            .IgnoreQueryFilters()
            .Where(ur => ur.UserId == userId && ur.TenantId == tenantId)
            .Join(
                db.AppRoles.IgnoreQueryFilters(),
                ur => ur.RoleId,
                r => r.Id,
                (_, r) => r.Name)
            .Distinct()
            .ToListAsync();

        if (roleNames.Count == 0)
        {
            roleNames.Add(ChurchRoleNames.Member);
        }

        return roleNames;
    }

    private static async Task<OidcAuthorizeRequest> ReadAuthorizeRequestAsync(HttpContext httpContext)
    {
        if (HttpMethods.IsPost(httpContext.Request.Method))
        {
            if (httpContext.Request.HasFormContentType)
            {
                var form = await httpContext.Request.ReadFormAsync();
                Guid? formTenantId = Guid.TryParse(form["tenant_id"].FirstOrDefault() ?? form["church_id"].FirstOrDefault(), out var parsedTenant)
                    ? parsedTenant
                    : null;
                return new OidcAuthorizeRequest(
                    ClientId: form["client_id"].FirstOrDefault(),
                    RedirectUri: form["redirect_uri"].FirstOrDefault(),
                    ResponseType: form["response_type"].FirstOrDefault(),
                    Scope: form["scope"].FirstOrDefault(),
                    CodeChallenge: form["code_challenge"].FirstOrDefault(),
                    CodeChallengeMethod: form["code_challenge_method"].FirstOrDefault(),
                    State: form["state"].FirstOrDefault(),
                    Nonce: form["nonce"].FirstOrDefault(),
                    Email: form["email"].FirstOrDefault(),
                    Password: form["password"].FirstOrDefault(),
                    TenantId: formTenantId,
                    ResponseMode: form["response_mode"].FirstOrDefault()
                );
            }

            if (httpContext.Request.ContentType?.Contains("application/json", StringComparison.OrdinalIgnoreCase) == true)
            {
                var body = await httpContext.Request.ReadFromJsonAsync<OidcAuthorizeRequest>();
                if (body != null)
                {
                    return body;
                }
            }
        }

        var query = httpContext.Request.Query;
        Guid? queryTenantId = Guid.TryParse(query["tenant_id"].FirstOrDefault() ?? query["church_id"].FirstOrDefault(), out var qTenant)
            ? qTenant
            : null;
        return new OidcAuthorizeRequest(
            ClientId: query["client_id"].FirstOrDefault(),
            RedirectUri: query["redirect_uri"].FirstOrDefault(),
            ResponseType: query["response_type"].FirstOrDefault(),
            Scope: query["scope"].FirstOrDefault(),
            CodeChallenge: query["code_challenge"].FirstOrDefault(),
            CodeChallengeMethod: query["code_challenge_method"].FirstOrDefault(),
            State: query["state"].FirstOrDefault(),
            Nonce: query["nonce"].FirstOrDefault(),
            Email: query["email"].FirstOrDefault(),
            Password: query["password"].FirstOrDefault(),
            TenantId: queryTenantId,
            ResponseMode: query["response_mode"].FirstOrDefault()
        );
    }

    private static async Task<OidcTokenRequest> ReadTokenRequestAsync(HttpContext httpContext)
    {
        if (httpContext.Request.HasFormContentType)
        {
            var form = await httpContext.Request.ReadFormAsync();
            return new OidcTokenRequest(
                GrantType: form["grant_type"].FirstOrDefault(),
                ClientId: form["client_id"].FirstOrDefault(),
                Code: form["code"].FirstOrDefault(),
                RedirectUri: form["redirect_uri"].FirstOrDefault(),
                CodeVerifier: form["code_verifier"].FirstOrDefault(),
                RefreshToken: form["refresh_token"].FirstOrDefault(),
                Scope: form["scope"].FirstOrDefault()
            );
        }

        if (httpContext.Request.ContentType?.Contains("application/json", StringComparison.OrdinalIgnoreCase) == true)
        {
            var body = await httpContext.Request.ReadFromJsonAsync<OidcTokenRequest>();
            if (body != null)
            {
                return body;
            }
        }

        return new OidcTokenRequest(null, null, null, null, null, null, null);
    }

    private static async Task<OidcRevokeRequest> ReadRevokeRequestAsync(HttpContext httpContext)
    {
        if (httpContext.Request.HasFormContentType)
        {
            var form = await httpContext.Request.ReadFormAsync();
            return new OidcRevokeRequest(
                ClientId: form["client_id"].FirstOrDefault(),
                Token: form["token"].FirstOrDefault(),
                TokenTypeHint: form["token_type_hint"].FirstOrDefault()
            );
        }

        if (httpContext.Request.ContentType?.Contains("application/json", StringComparison.OrdinalIgnoreCase) == true)
        {
            var body = await httpContext.Request.ReadFromJsonAsync<OidcRevokeRequest>();
            if (body != null)
            {
                return body;
            }
        }

        return new OidcRevokeRequest(null, null, null);
    }

    private static string BuildInteractiveAuthorizeLoginHtml(OidcAuthorizeRequest req)
    {
        static string Encode(string? val) => WebUtility.HtmlEncode(val ?? string.Empty);

        var responseMode = string.IsNullOrWhiteSpace(req.ResponseMode) ? "redirect" : req.ResponseMode;
        var tenantIdVal = req.TenantId.HasValue && req.TenantId.Value != Guid.Empty
            ? req.TenantId.Value.ToString()
            : string.Empty;

        return $@"<!DOCTYPE html>
<html lang=""en"">
<head>
  <meta charset=""utf-8"" />
  <meta name=""viewport"" content=""width=device-width, initial-scale=1"" />
  <title>Church Sign In</title>
</head>
<body>
  <main>
    <h1>Sign in to your Church Account</h1>
    <form method=""post"" action=""/connect/authorize"">
      <input type=""hidden"" name=""client_id"" value=""{Encode(req.ClientId)}"" />
      <input type=""hidden"" name=""redirect_uri"" value=""{Encode(req.RedirectUri)}"" />
      <input type=""hidden"" name=""response_type"" value=""{Encode(req.ResponseType)}"" />
      <input type=""hidden"" name=""scope"" value=""{Encode(req.Scope)}"" />
      <input type=""hidden"" name=""code_challenge"" value=""{Encode(req.CodeChallenge)}"" />
      <input type=""hidden"" name=""code_challenge_method"" value=""{Encode(req.CodeChallengeMethod)}"" />
      <input type=""hidden"" name=""state"" value=""{Encode(req.State)}"" />
      <input type=""hidden"" name=""nonce"" value=""{Encode(req.Nonce)}"" />
      <input type=""hidden"" name=""response_mode"" value=""{Encode(responseMode)}"" />
      <div>
        <label for=""email"">Email</label>
        <input id=""email"" type=""email"" name=""email"" required autocomplete=""username"" />
      </div>
      <div>
        <label for=""password"">Password</label>
        <input id=""password"" type=""password"" name=""password"" required autocomplete=""current-password"" />
      </div>
      <div>
        <label for=""tenant_id"">Church Tenant ID (optional)</label>
        <input id=""tenant_id"" type=""text"" name=""tenant_id"" value=""{Encode(tenantIdVal)}"" />
      </div>
      <button type=""submit"">Sign In</button>
    </form>
  </main>
</body>
</html>";
    }
}
