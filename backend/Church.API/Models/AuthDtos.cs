using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Church.API.Models;

public record CurrentUserResponse(
    Guid MemberId,
    Guid TenantId,
    string Email,
    string DisplayName,
    IReadOnlyList<string> Roles
);

public record OidcDiscoveryDocument(
    [property: JsonPropertyName("issuer")] string Issuer,
    [property: JsonPropertyName("authorization_endpoint")] string AuthorizationEndpoint,
    [property: JsonPropertyName("token_endpoint")] string TokenEndpoint,
    [property: JsonPropertyName("userinfo_endpoint")] string UserInfoEndpoint,
    [property: JsonPropertyName("revocation_endpoint")] string RevocationEndpoint,
    [property: JsonPropertyName("jwks_uri")] string JwksUri,
    [property: JsonPropertyName("response_types_supported")] IReadOnlyList<string> ResponseTypesSupported,
    [property: JsonPropertyName("grant_types_supported")] IReadOnlyList<string> GrantTypesSupported,
    [property: JsonPropertyName("code_challenge_methods_supported")] IReadOnlyList<string> CodeChallengeMethodsSupported,
    [property: JsonPropertyName("scopes_supported")] IReadOnlyList<string> ScopesSupported,
    [property: JsonPropertyName("token_endpoint_auth_methods_supported")] IReadOnlyList<string> TokenEndpointAuthMethodsSupported
);

public record OidcAuthorizeRequest(
    [property: JsonPropertyName("client_id")] string? ClientId,
    [property: JsonPropertyName("redirect_uri")] string? RedirectUri,
    [property: JsonPropertyName("response_type")] string? ResponseType,
    [property: JsonPropertyName("scope")] string? Scope,
    [property: JsonPropertyName("code_challenge")] string? CodeChallenge,
    [property: JsonPropertyName("code_challenge_method")] string? CodeChallengeMethod,
    [property: JsonPropertyName("state")] string? State,
    [property: JsonPropertyName("nonce")] string? Nonce,
    [property: JsonPropertyName("email")] string? Email,
    [property: JsonPropertyName("password")] string? Password,
    [property: JsonPropertyName("tenant_id")] Guid? TenantId,
    [property: JsonPropertyName("response_mode")] string? ResponseMode
);

public record OidcAuthorizeResponse(
    [property: JsonPropertyName("code")] string Code,
    [property: JsonPropertyName("state")] string? State,
    [property: JsonPropertyName("redirect_uri")] string RedirectUri
);

public record OidcTokenRequest(
    [property: JsonPropertyName("grant_type")] string? GrantType,
    [property: JsonPropertyName("client_id")] string? ClientId,
    [property: JsonPropertyName("code")] string? Code,
    [property: JsonPropertyName("redirect_uri")] string? RedirectUri,
    [property: JsonPropertyName("code_verifier")] string? CodeVerifier,
    [property: JsonPropertyName("refresh_token")] string? RefreshToken,
    [property: JsonPropertyName("scope")] string? Scope
);

public record OidcTokenResponse(
    [property: JsonPropertyName("access_token")] string AccessToken,
    [property: JsonPropertyName("id_token")] string IdToken,
    [property: JsonPropertyName("refresh_token")] string RefreshToken,
    [property: JsonPropertyName("token_type")] string TokenType,
    [property: JsonPropertyName("expires_in")] int ExpiresIn,
    [property: JsonPropertyName("scope")] string Scope
);

public record OidcUserInfoResponse(
    [property: JsonPropertyName("sub")] Guid Sub,
    [property: JsonPropertyName("member_id")] Guid MemberId,
    [property: JsonPropertyName("tenant_id")] Guid TenantId,
    [property: JsonPropertyName("church_id")] Guid ChurchId,
    [property: JsonPropertyName("roles")] IReadOnlyList<string> Roles,
    [property: JsonPropertyName("email")] string Email,
    [property: JsonPropertyName("name")] string Name
);

public record OidcRevokeRequest(
    [property: JsonPropertyName("client_id")] string? ClientId,
    [property: JsonPropertyName("token")] string? Token,
    [property: JsonPropertyName("token_type_hint")] string? TokenTypeHint
);

public record OidcErrorResponse(
    [property: JsonPropertyName("error")] string Error,
    [property: JsonPropertyName("error_description")] string ErrorDescription
);
