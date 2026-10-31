# MVP Identity Provider Options & Decision Checklist

## 1. Executive Summary & Purpose

This document provides a comprehensive, vendor-neutral architectural evaluation of zero-additional-cost identity options for the **Church Digital Platform Single-Church Pilot**.

### 1.1 Context & Traceability
- **Parent Issue**: Module 9: Identity, Sign-In & Tenant Context (PBI [#18](https://github.com/organization/repo/issues/18))
- **MVP Tracker**: MVP Milestone Tracker ([#21](https://github.com/organization/repo/issues/21))
- **Preceding Contract**: `docs/architecture/mvp-identity-and-member-contract.md` (PR [#28](https://github.com/organization/repo/pull/28))
- **Downstream Unblocked Tasks**:
  - Child Task 1: Backend JWT Validation & Session Endpoints ([#24](https://github.com/organization/repo/issues/24))
  - Child Task 2: Mobile Auth Client, Secure Token Storage & Auth Gate ([#25](https://github.com/organization/repo/issues/25))

### 1.2 Non-Authorization & Boundary Notice
> **Important**: This document is strictly an engineering evaluation and decision preparation guide. It **does not** constitute authorization to select, contract, or provision an external cloud identity service, nor does it guarantee perpetual free-tier availability from commercial cloud vendors. No production provider accounts have been created, no billable services have been provisioned, and no source code, workflows, or project dependencies have been modified in this task.

### 1.3 Cost Separation: Developer AI Subscriptions vs. Cloud/Identity Infrastructure
To maintain financial transparency for church leadership and non-technical stakeholders:
- **Developer AI Subscriptions (e.g., ChatGPT Plus, Gemini Advanced, GitHub Copilot, Claude Pro)**: Personal or organizational developer-tooling subscriptions used during software design and coding. These have **zero** operational or runtime cost for church congregants, servers, or the mobile application.
- **Runtime Identity & Infrastructure Costs**: The actual monthly cost to authenticate church members, store profile records, and run the backend API. The options analyzed below are specifically evaluated for their ability to operate at **$0.00 additional monthly cost** for the pilot church.

---

## 2. Architectural Baseline & Contract Requirements

Any viable identity solution must seamlessly adhere to the contracts established in PR #28 and address vulnerabilities identified in the existing backend codebase.

### 2.1 Current Backend State & Security Risks
The current API in `backend/Church.API/Program.cs` uses `CustomAuthHandler` and `TenantService`:
1. **Header Spoofing**: Any client can pass `X-Tenant-Id`, `X-User-Role: Admin`, or `X-User-Id` to bypass security and impersonate any user or church tenant.
2. **Volatile Fallback IDs**: When non-Member roles omit `X-User-Id`, `CustomAuthHandler` invokes `Guid.NewGuid().ToString()`, causing member IDs to fluctuate across successive HTTP calls.
3. **Transition Requirement**: Header-based auth must be strictly restricted to development/unit testing (`builder.Environment.IsDevelopment() || builder.Environment.IsEnvironment("Testing")`). In production, all identity claims (`sub`, `role`, `tenant_id`) must originate exclusively from validated cryptographic tokens.

### 2.2 Core Technical Requirements for Production Auth
1. **ASP.NET Core 10 JWT Bearer Validation**:
   - Backend must validate tokens using `Microsoft.AspNetCore.Authentication.JwtBearer` against standard OpenID Connect (OIDC) Discovery (`/.well-known/openid-configuration`) and JSON Web Key Sets (JWKS).
   - Validates signature, issuer (`iss`), audience (`aud`), and expiration (`exp`).
2. **Stable Member ID Mapping**:
   - The user identifier must be a persistent standard UUID (`Guid`) representing the congregant.
   - Extracted from `ClaimTypes.NameIdentifier` or `sub`.
3. **Server-Validated Tenant Context**:
   - Multi-tenant isolation requires that the tenant ID cannot be forged by client HTTP headers.
   - The tenant ID must either be embedded in the signed JWT payload (e.g. `tenant_id` custom claim) or resolved via the verified member profile record in PostgreSQL.
4. **Least-Privilege Role Administration**:
   - The platform defines four standard roles: `Member`, `Pastor`, `Admin`, and `WorshipLeader`.
   - The identity solution must support assigning and mapping these roles without requiring an enterprise paid tier.
5. **Session Lifecycle & Revocation**:
   - Short-lived access tokens (e.g., 15–60 minutes) combined with sliding refresh tokens.
   - Immediate session revocation capability upon sign-out or password change.
6. **Flutter Client Integration**:
   - Tokens stored exclusively in hardware-backed secure storage (`flutter_secure_storage` utilizing Keychain on iOS and EncryptedSharedPreferences/KeyStore on Android).
   - Automatic injection of `Authorization: Bearer <token>` in mobile HTTP requests and handling of `401 Unauthorized` refresh flows.

---

## 3. Viable Zero-Additional-Cost Identity Options

We evaluate four primary approaches capable of supporting the single-church pilot (100–500 members) with zero recurring subscription fees.

### Option 1: Supabase Auth (Cloud Free Tier or Self-Hosted)

*An open-source Firebase alternative built around PostgreSQL and the GoTrue auth engine.*

- **Account & Setup Requirements**:
  - Cloud: A free Supabase organization account and project (hosted on AWS region closest to pilot church, e.g., `ap-south-1` Mumbai).
  - Self-Hosted: Can alternatively be run as a Docker container alongside the backend database with zero external dependencies.
- **Free-Tier Limits & Quotas**:
  - Up to **50,000 Monthly Active Users (MAU)** free of charge.
  - Unlimited social login providers (Google, Apple, etc.).
  - Built-in SMTP rate limits: 30 emails/hour for confirmation/magic links (custom external free SMTP like Resend/SendGrid recommended for higher throughput).
- **Free-Tier Uncertainties & Risks**:
  - *Project Inactivity Pausing*: Free-tier Supabase Cloud projects are automatically paused after 7 days of API inactivity. (Mitigation: Single-church pilot has weekly Sunday usage, but an automated uptime ping or self-hosting prevents unexpected sleep).
  - *Terms Changes*: Free tiers on managed SaaS platforms are subject to provider policy updates over time.
- **Flutter Support**:
  - First-party, mature `supabase_flutter` package.
  - Native support for deep linking, OAuth redirects, and local session persistence.
- **ASP.NET Core 10 Token Validation**:
  - Supabase issues standard RS256 or HS256 JWTs.
  - Asymmetric keys are exposed at standard JWKS endpoint (`https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json`), enabling native ASP.NET Core `AddJwtBearer()` integration.
- **Stable Member & Tenant Mapping**:
  - Supabase Auth generates standard UUIDv4 strings for all user IDs (`auth.users.id`), providing 100% native compatibility with backend `Guid MemberId`.
  - Custom claims (`tenant_id`, `role`) can be injected into the JWT via Supabase Auth Custom Claims Hooks (PostgreSQL functions) or mapped through an initial `/api/v1/auth/session` handshake.
- **Role Administration**:
  - Managed either via `raw_app_meta_data` in Supabase Auth or through local role tables in the church's existing PostgreSQL schema.
- **Session Expiry & Secure Storage**:
  - Default access token lifetime: 1 hour; refresh tokens have customizable sliding expiry.
  - Supported directly via `flutter_secure_storage`.

---

### Option 2: Firebase Authentication (Google Cloud Identity Platform)

*Google's enterprise-grade, turnkey identity platform with extensive mobile SDK integration.*

- **Account & Setup Requirements**:
  - Google Cloud / Firebase console account.
  - Registration of Android package name (`com.churchdigital.platform`) with SHA-1 fingerprint and iOS bundle identifier.
  - Configuration files (`google-services.json` and `GoogleService-Info.plist`).
- **Free-Tier Limits & Quotas**:
  - **Spark Plan (Free Tier)**: Up to **50,000 MAU** for Email/Password, Email Link (passwordless), and Google Sign-In.
  - Free email verification and password reset emails handled by Google infrastructure.
- **Free-Tier Uncertainties & Critical Cost Risks**:
  - **SMS Phone OTP is NOT Free**: While Email/Password is free up to 50,000 MAU, Firebase Phone Authentication (SMS OTP) requires the Blaze (Pay-as-you-go) billing plan. While a small monthly allowance of SMS verifications may exist depending on region, SMS costs apply per message thereafter (e.g., $0.015–$0.06/SMS in India and North America).
  - *Risk Warning*: If church congregants expect Phone OTP sign-in, Firebase will incur real recurring costs unless strictly restricted to Email/Password or third-party OAuth.
- **Flutter Support**:
  - Official Google Flutter package (`firebase_auth`). Battle-tested across billions of devices.
- **ASP.NET Core 10 Token Validation**:
  - Firebase tokens are standard signed RS256 JWTs.
  - Validated via ASP.NET Core `AddJwtBearer`:
    - Authority: `https://securetoken.google.com/<firebase-project-id>`
    - Issuer: `https://securetoken.google.com/<firebase-project-id>`
    - Audience: `<firebase-project-id>`
    - Public Keys: Google JWKS (`https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`).
- **Stable Member & Tenant Mapping**:
  - Firebase user IDs (`uid`) are alphanumeric strings (e.g. `4fK9mP...`, 28 characters), **not standard GUIDs**.
  - *Impact*: Requires maintaining an explicit mapping table (`FirebaseUid` -> `Guid MemberId`) in `ApplicationDbContext`, or computing a deterministic UUID from the UID string.
- **Role Administration**:
  - Handled via Firebase Custom User Claims (requires a lightweight server-side script using Firebase Admin .NET SDK) or directly in the local backend database upon token exchange.
- **Session Expiry & Secure Storage**:
  - Access tokens expire after 1 hour with automatic client-side SDK refresh.

---

### Option 3: Embedded Self-Hosted OIDC / OpenIddict on .NET 10

*An in-process, self-contained OpenID Connect and OAuth2 server integrated directly into `Church.API` and `Church.Infrastructure`.*

- **Account & Setup Requirements**:
  - **Zero external cloud provider accounts**.
  - Uses the existing ASP.NET Core 10 backend and PostgreSQL database already provisioned for Church Digital Platform.
  - Implemented using OpenIddict (`OpenIddict.AspNetCore`, `OpenIddict.EntityFrameworkCore`) or lightweight JWT token issuance with ASP.NET Core Identity.
- **Free-Tier Limits & Quotas**:
  - **Unlimited MAU**: No quotas, no external rate limits, and 100% free forever.
  - Zero risk of cloud vendor pricing changes, inactivity project pausing, or sudden tier restrictions.
- **Free-Tier Uncertainties & Operational Trade-offs**:
  - Operational responsibility: Email sending for password reset or email verification requires a transactional SMTP service (e.g. Resend free tier: 3,000 emails/month; or church's Google Workspace SMTP relay).
  - Initial engineering effort is slightly higher to build and maintain the user credential storage tables and endpoints.
- **Flutter Support**:
  - Standard OAuth2 Resource Owner Password Credentials (ROPC) or Authorization Code flow with PKCE, or custom REST endpoint (`/api/v1/auth/login`).
  - No proprietary client SDK required; uses standard HTTP requests and `flutter_secure_storage`.
- **ASP.NET Core 10 Token Validation**:
  - Native in-memory or asymmetric RS256 token validation with zero network latency (no external HTTP calls needed to fetch remote JWKS keys).
- **Stable Member & Tenant Mapping**:
  - Native `Guid` primary keys throughout. The user ID in the database is the exact `Guid MemberId`.
  - The `tenant_id` claim is baked directly into the JWT upon user authentication.
- **Role Administration**:
  - Full native control using ASP.NET Core Identity roles (`Admin`, `Pastor`, `Member`, `WorshipLeader`) stored directly in EF Core.
- **Session Expiry & Secure Storage**:
  - Full control over token lifetimes (e.g., 15-minute access token, 30-day sliding refresh token).
  - Refresh tokens stored in PostgreSQL with immediate server-side revocation on logout.

---

### Option 4: Auth0 by Okta / Clerk (Evaluation & Limits)

*Specialized Customer Identity and Access Management (CIAM) platforms.*

- **Free-Tier Limits**:
  - Auth0: Up to 7,500 MAU free tier.
  - Clerk: Up to 10,000 MAU free tier.
- **Evaluation & Cost Risks**:
  - While generous for a pilot, Auth0 has steep pricing escalations once user count or required features (such as custom domains, role-based access control, or enterprise connections) exceed free limits.
  - Clerk is primarily web/Next.js focused; Flutter support relies on community packages.
  - *Verdict*: Not recommended for long-term church non-profit budgets where predictable $0 recurring costs are required.

---

## 4. Comprehensive Comparison Matrix

| Evaluation Dimension | Option 1: Supabase Auth | Option 2: Firebase Auth | Option 3: Embedded OpenIddict (.NET 10) | Option 4: Auth0 / Clerk |
|---|---|---|---|---|
| **Subscription Cost** | $0.00 (Free Tier) | $0.00 (Spark Free Tier) | $0.00 (Zero vendor dependencies) | $0.00 (Limited Free Tier) |
| **Free Tier MAU Limit** | 50,000 MAU | 50,000 MAU (Email/Google) | Unlimited | 7,500–10,000 MAU |
| **SMS OTP Capability** | Paid third-party provider | Paid beyond small trial (Blaze plan) | Paid third-party provider | Paid add-on |
| **Inactivity Pausing Risk** | Yes (7 days inactivity on Cloud) | No | No | No |
| **External Vendor Account Needed** | Yes (Supabase) | Yes (Google Cloud) | **No (Self-contained)** | Yes (Okta / Clerk) |
| **Flutter Client SDK** | Official `supabase_flutter` | Official `firebase_auth` | Standard HTTP / `oauth2` | Community / REST |
| **.NET 10 JWT Validation** | Standard JWKS / OIDC | Google JWKS / OIDC | Native OpenIddict / JwtBearer | Standard OIDC / JWKS |
| **User ID Format** | Native UUID (`Guid`) | Alphanumeric string (needs mapping) | **Native UUID (`Guid`)** | Alphanumeric string |
| **Tenant ID in Token** | Via Auth Hooks or local DB | Via Custom Claims (Admin SDK) | **Direct native claim issuance** | Via Actions / Rules |
| **Role Management** | `app_metadata` or local DB | Custom Claims / local DB | **Native ASP.NET Core Identity** | Dashboard Roles / Rules |
| **Data Sovereignty & Privacy** | High (PostgreSQL / Self-hostable) | Moderate (Google Cloud) | **Maximum (Church owns full DB)** | Moderate (Proprietary cloud) |
| **Offline Dev / Local Testing** | Local Supabase CLI / Docker | Firebase Local Emulator | **Direct in-memory / Local Postgres** | Requires internet access |

---

## 5. Architectural Recommendation for MVP Pilot

### 5.1 Primary Recommendation: Two-Tier Strategy

1. **Recommended Path A: Embedded OpenIddict / ASP.NET Core Identity on .NET 10**
   - **Why**:
     - **True Zero Cost**: Does not introduce external cloud account management, API quotas, or third-party privacy concerns.
     - **Perfect Alignment with Existing Architecture**: The backend is already an ASP.NET Core 10 app running PostgreSQL with EF Core. Adding OpenIddict or standard ASP.NET Identity token endpoints directly issues tokens with native `Guid MemberId` and `tenant_id` claims.
     - **No Foreign ID Mapping**: Eliminates the need to bridge Firebase strings to EF Core GUIDs.
     - **Offline & CI Testing**: Backend integration tests run 100% in-memory without mock cloud services or network calls.

2. **Recommended Path B: Supabase Auth (Cloud Free Tier)**
   - **Why (if external managed auth is preferred)**:
     - If church leadership prefers an out-of-the-box administrative user dashboard and social login (Google/Apple) without writing authentication endpoints in .NET.
     - Generous 50,000 MAU free tier with native UUID identifiers.
     - Requires setting up a periodic ping or cron job to prevent the 7-day inactivity pause on free Supabase Cloud projects.

### 5.2 Not Recommended for Pilot
- **Firebase Phone OTP**: Due to immediate per-SMS billing risks that violate the no-additional-cost requirement.
- **Auth0 / Okta**: Due to vendor lock-in and high subscription step-costs if user count grows.

---

## 6. Church-Owner Decision Checklist

To unblock **Child Task 1 (Backend JWT & Auth Endpoints, Issue #24)** and **Child Task 2 (Mobile Auth Client & Screens, Issue #25)**, the Church Owner and Leadership Council must provide clear guidance on the following five decisions:

```
+---------------------------------------------------------------------------------------------------+
| CHURCH OWNER DECISION CHECKLIST                                                                   |
+----+----------------------------------------------+----------------------------------+------------+
| #  | Decision Item                                | Recommended Default              | Selected   |
+----+----------------------------------------------+----------------------------------+------------+
| 1  | Identity Provider Architecture               | Option 3: Embedded OpenIddict    | [ ] Opt 3  |
|    | - Embedded OpenIddict (In-house, $0 forever)  | (or Option 1: Supabase Cloud)    | [ ] Opt 1  |
|    | - Supabase Auth (Managed Cloud Free Tier)     |                                  | [ ] Opt 2  |
|    | - Firebase Auth (Google Cloud Free Tier)      |                                  |            |
+----+----------------------------------------------+----------------------------------+------------+
| 2  | Congregant Sign-In Method                    | Email + Password                 | [ ] Email  |
|    | - Traditional Email + Password ($0 cost)     | (with optional Magic Link)       | [ ] Magic  |
|    | - Email Magic Link / OTP ($0 cost)           |                                  | [ ] Phone* |
|    | - Phone SMS OTP (*requires paid SMS budget)  |                                  |            |
+----+----------------------------------------------+----------------------------------+------------+
| 3  | Tenant Membership & Pilot Registration       | Invite-Only / Pastor Approval    | [ ] Invite |
|    | - Closed / Pre-provisioned members only      |                                  | [ ] Code   |
|    | - Self-registration with Church Tenant Code  |                                  | [ ] Open   |
|    | - Open public self-registration              |                                  |            |
+----+----------------------------------------------+----------------------------------+------------+
| 4  | Seed Administrator & Pastor Accounts         | Appoint 1 Pilot Church Admin     | [ ] Yes    |
|    | - Designate initial email address for Admin  | and 1 Pastor account for seeding |            |
|    | - Designate initial email address for Pastor | during database initialization   |            |
+----+----------------------------------------------+----------------------------------+------------+
| 5  | Token Expiration & Inactivity Policies      | Access Token: 15 minutes         | [ ] Default|
|    | - Access token lifetime (short-lived)        | Refresh Token: 30 days sliding   | [ ] Custom |
|    | - Refresh token sliding inactivity window    |                                  |            |
+----+----------------------------------------------+----------------------------------+------------+
```

### 6.1 Impact on Child Task #24 (Backend JWT & Auth Endpoints)
- Unblocks configuring `Authentication:Authority`, `Authentication:Audience`, and signing keys in `appsettings.json`.
- Unblocks deprecating `CustomAuthHandler` in production environments while keeping test schemes active for automated tests.
- Defines the exact contract for `GET /api/v1/auth/me` and session exchange.

### 6.2 Impact on Child Task #25 (Mobile Auth Client & Screens)
- Unblocks choosing whether to include `supabase_flutter`, `firebase_auth`, or a lightweight standard REST `oauth2` client in `mobile/pubspec.yaml`.
- Unblocks UI design for the login screen (Email/Password fields vs. Magic Link vs. Social Auth buttons).
- Unblocks implementation of `mobile/lib/services/token_storage.dart` and `mobile/lib/screens/auth_gate.dart`.

---

## 7. Official Citations & References

The following official documentation sources were consulted during this evaluation (accessed October 2026):

1. **Supabase Auth Documentation & Pricing**:
   - Supabase Pricing and Free Plan Limits: https://supabase.com/pricing
   - Supabase Auth Deep Dive & JWT Structure: https://supabase.com/docs/guides/auth
   - Supabase Auth Custom Claims & Hooks: https://supabase.com/docs/guides/auth/auth-hooks
   - Supabase Flutter SDK: https://pub.dev/packages/supabase_flutter

2. **Google Firebase Authentication Documentation & Pricing**:
   - Firebase Pricing (Spark vs. Blaze Plan): https://firebase.google.com/pricing
   - Firebase Identity Platform Limits & Quotas: https://firebase.google.com/docs/auth/limits
   - Verifying Firebase ID Tokens in .NET / REST: https://firebase.google.com/docs/auth/admin/verify-id-tokens
   - FlutterFire Authentication: https://firebase.flutter.dev/docs/auth/overview

3. **OpenIddict (.NET Foundation)**:
   - OpenIddict Official Documentation: https://documentation.openiddict.com/
   - OpenIddict ASP.NET Core Integration: https://documentation.openiddict.com/guides/getting-started/creating-an-authorization-server.html

4. **Microsoft ASP.NET Core Security & Authentication**:
   - Overview of ASP.NET Core Authentication: https://learn.microsoft.com/aspnet/core/security/authentication/
   - Configure JWT Bearer Authentication in ASP.NET Core: https://learn.microsoft.com/aspnet/core/security/authentication/jwt-bearer
