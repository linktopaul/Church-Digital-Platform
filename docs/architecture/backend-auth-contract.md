# Backend Identity, OIDC PKCE & Tenant Authorization Contract

## Overview

This document defines the production authentication and authorization contract implemented for Issue `#24` and consumed by the mobile native OIDC PKCE client (`#25`) and downstream member/profile slices (`#45`).

---

## 1. Public Client & OIDC Discovery Configuration

- **Discovery Document**: `GET /.well-known/openid-configuration`
- **JWKS Endpoint**: `GET /.well-known/jwks.json` (RS256 public key set)
- **Authorization Endpoint**: `GET /connect/authorize` and `POST /connect/authorize`
- **Token Endpoint**: `POST /connect/token`
- **UserInfo Endpoint**: `GET /connect/userinfo`
- **Revocation Endpoint**: `POST /connect/revoke`
- **Session Profile Endpoint**: `GET /api/v1/auth/me`
- **Session Sign-Out Endpoint**: `POST /api/v1/auth/sign-out`

### Registered Public Client Defaults

| Setting | Default Value | Configuration Key |
|---|---|---|
| Client ID | `church_mobile_app` | `Authentication:AllowedClientIds` |
| Redirect URIs | `com.church.app://oauthredirect`, `http://localhost/callback`, `https://localhost/callback` | `Authentication:AllowedRedirectUris` |
| Response Type | `code` | Fixed |
| PKCE Method | `S256` (required; `plain` and missing challenge rejected) | Fixed |
| Supported Grants | `authorization_code`, `refresh_token` (`password` grant explicitly disabled) | Fixed |
| Scopes | `openid profile email offline_access roles church_api` | Fixed |
| Audience | `church_api` | `Authentication:Audience` |

---

## 2. Token & Claim Contract

### Access Token (`access_token`)
RS256-signed JWT with audience `church_api` and default lifetime 900 seconds (`15` minutes):
- `sub`: `<member_uuid>`
- `member_id`: `<member_uuid>`
- `tenant_id`: `<church_uuid>`
- `church_id`: `<church_uuid>`
- `email`: `<email>`
- `name`: `<display_name>`
- `roles`: `["Admin" | "Pastor" | "WorshipLeader" | "FellowshipLeader" | "Member"]`
- `jti`: unique token identifier used for immediate revocation checks

### ID Token (`id_token`)
RS256-signed JWT with audience `<client_id>` and optional `nonce` echo when supplied during `/connect/authorize`.

### Refresh Token (`refresh_token`)
- Single-use 256-bit cryptographically random token stored only as a SHA-256 base64url digest in `OidcRefreshTokens`.
- Every `grant_type=refresh_token` call marks the presented token as consumed (`consumed_at`) and issues a replacement token (`replaced_by_token_hash`).
- Replaying a consumed refresh token or authorization code immediately revokes all active refresh tokens in that grant family and returns HTTP `400 Bad Request` with `{"error": "invalid_grant"}`.

---

## 3. Production Tenant & Header Guardrails

- **Production Environment**:
  - `X-User-Role`, `X-User-Id`, `X-Tenant-Id`, `Authorization: TestRole <role>`, and mock `Authorization: Bearer admin|pastor|member` tokens are **completely disabled** and rejected with `401 Unauthorized`.
  - `TenantService.GetCurrentTenantId()` derives the active church tenant **exclusively** from the validated JWT `tenant_id` / `church_id` claim.
  - Even if a client sends a conflicting `X-Tenant-Id` header alongside a valid JWT, `TenantService` ignores the header and enforces the JWT's `tenant_id`.
- **Development / Testing Environment**:
  - Real RS256 JWT bearer tokens are validated first and enforce strict claim-derived tenant isolation.
  - Legacy header/mock token shortcuts remain available only when `Environment` is `Development` or `Testing` and `Authentication:AllowTestHeaderAuth` is `true` (default in dev/test).
