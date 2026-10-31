# MVP Identity, Tenant Context, and Member Profile Contract

## 1. Executive Summary & Purpose

This contract defines the unified architecture, data transfer objects (DTOs), session lifecycle boundaries, and authorization rules for:
- **Module 9: Identity, Sign-In & Tenant Context** (Issue #18)
- **Module 7: Member Profile & Family Directory** (Issue #9)

By establishing strict API contracts, clear separation of concerns, and unambiguous file ownership prior to implementation, both modules can be developed autonomously and concurrently by Jules subtasks without merge conflicts, code churn, or guesswork regarding domain models.

---

## 2. Current-State Audit: Test Header Auth & Tenant Service

### 2.1 Existing Implementation Overview
The current backend repository relies on prototype test authentication and header-driven tenant resolution located in `backend/Church.API/Program.cs` and `backend/Church.Infrastructure/ITenantService.cs`:

1. **`TenantService` (`backend/Church.API/Program.cs`)**:
   ```csharp
   public Guid GetCurrentTenantId()
   {
       var httpContext = _httpContextAccessor.HttpContext;
       if (httpContext == null) return Guid.Empty;

       var tenantIdString = httpContext.Request.Headers["X-Tenant-Id"].FirstOrDefault();
       if (Guid.TryParse(tenantIdString, out var tenantId))
       {
           return tenantId;
       }

       var churchClaim = httpContext.User.FindFirst("church_id")?.Value;
       if (Guid.TryParse(churchClaim, out var churchId))
       {
           return churchId;
       }

       return Guid.Empty;
   }
   ```
2. **`CustomAuthHandler` (`backend/Church.API/Program.cs`)**:
   - Inspects headers: `X-User-Role`, `X-User-Id`, `X-Tenant-Id`.
   - Inspects `Authorization` header prefixes: `"TestRole <Role>"` and mock tokens `"Bearer admin"`, `"Bearer pastor"`, `"Bearer member"`.
   - Synthesizes user identity claims without cryptographic signature or token verification.
   - Fallback behavior: If `X-User-Id` is omitted for non-Member roles, it invokes `Guid.NewGuid().ToString()`, causing member IDs to fluctuate across successive HTTP calls.

### 2.2 Security & Multi-Tenancy Vulnerabilities
- **Header Spoofing**: Any HTTP client or mobile agent can pass arbitrary `X-Tenant-Id` and `X-User-Role: Admin` headers to bypass authorization policies and query or mutate cross-tenant records.
- **Unverified Identity**: Identity claims (`sub`, `nameidentifier`, `role`) are not validated against an asymmetric public key or trusted issuer.
- **Client-Side Dependency**: Downstream features (e.g. Prayer Requests, Announcements, Worship Setlists, and the active Fellowship Ministry Spaces module in PR #8) currently rely on `user.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? user.FindFirst("sub")?.Value`.

### 2.3 Transition Strategy
- **Production Guarding**: Header-based authentication (`CustomAuthHandler`) and client-selected `X-Tenant-Id` override must be disabled or strictly restricted to the development/test environment (`builder.Environment.IsDevelopment() || builder.Environment.IsEnvironment("Testing")`).
- **Production Mode**: Tenant ID and User Roles must be extracted exclusively from validated claims inside a signed JWT issued by the configured identity provider.

---

## 3. Production Identity, Tenant Claims & Authorization Rules

### 3.1 Stable Member ID
- The member identifier must be a persistent UUID (`Guid`) representing the account across the platform.
- Derived from the standard JWT subject claim (`sub`) or `ClaimTypes.NameIdentifier`.
- The backend helper logic must consistently parse this claim:
  ```csharp
  public static Guid GetCurrentUserId(ClaimsPrincipal user)
  {
      var sub = user.FindFirst(ClaimTypes.NameIdentifier)?.Value
             ?? user.FindFirst("sub")?.Value;
      return Guid.TryParse(sub, out var id) ? id : Guid.Empty;
  }
  ```
- Random ID generation (`Guid.NewGuid()`) within auth middleware must never occur in production. Unauthenticated or invalid token requests must yield HTTP `401 Unauthorized`.

### 3.2 Server-Validated Tenant Context
- Multi-tenant boundary integrity is paramount.
- The active tenant ID (`church_id` or `tenant_id`) must reside within the cryptographically signed JWT payload (e.g., custom claim `"tenant_id": "00000000-0000-0000-0000-000000000001"`).
- `TenantService.GetCurrentTenantId()` in production must read:
  1. `ClaimsPrincipal.FindFirst("tenant_id")?.Value`
  2. `ClaimsPrincipal.FindFirst("church_id")?.Value`
- `X-Tenant-Id` request header inspection is ignored in production.
- Entity Framework Core query filters automatically apply `Where(e => e.TenantId == _tenantService.GetCurrentTenantId())` for all entities implementing `IMultiTenantEntity`.

### 3.3 Roles & Least-Privilege Policies
The system supports four standardized roles:
1. **`Member`**: Standard congregant with access to announcements, public fellowships, submitting confidential prayer requests, and directory viewing based on privacy settings.
2. **`Pastor`**: Spiritual leader with full access to confidential pastoral prayers, publishing announcements, ministry spaces, and unredacted member directory records.
3. **`Admin`**: Platform/church administrator capable of managing tenant settings, roles, announcements, ministry spaces, and member records.
4. **`WorshipLeader`**: Music ministry coordinator with elevated rights to manage songs and Sunday service setlists.

#### Authorization Policies:
- `Default`: All `/api/v1/*` endpoints require `[Authorize]` unless explicitly marked with `[AllowAnonymous]` (e.g., health checks, public discovery).
- `PastorOnly`: `policy.RequireRole("Pastor")`
- `CanPublishAnnouncements`: `policy.RequireRole("Admin", "Pastor")`
- `CanManageWorship`: `policy.RequireRole("Admin", "Pastor", "WorshipLeader")`
- `CanManageFellowships`: `policy.RequireRole("Admin", "Pastor")` (or group-level leader)
- `CanManageMembers`: `policy.RequireRole("Admin", "Pastor")`

---

## 4. Provider-Neutral API & Session Boundaries

To avoid proprietary vendor lock-in and enable seamless integration with any OpenID Connect (OIDC) / OAuth2 compliant provider (e.g., Supabase Auth, Firebase Auth, OpenIddict, or Keycloak), the API and Flutter client communicate via standard bearer tokens.

### 4.1 Backend Architecture (.NET 10)
- **Standard Authentication Middleware**:
  ASP.NET Core JWT Bearer authentication (`Microsoft.AspNetCore.Authentication.JwtBearer`):
  ```csharp
  builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
      .AddJwtBearer(options =>
      {
          options.Authority = builder.Configuration["Authentication:Authority"];
          options.Audience = builder.Configuration["Authentication:Audience"];
          options.RequireHttpsMetadata = !builder.Environment.IsDevelopment();
          options.TokenValidationParameters = new TokenValidationParameters
          {
              ValidateIssuer = true,
              ValidateAudience = true,
              ValidateLifetime = true,
              ValidateIssuerSigningKey = true,
              NameClaimType = "name",
              RoleClaimType = "role"
          };
      });
  ```
- **Session Lifecycle Endpoints (`/api/v1/auth`)**:
  - `GET /api/v1/auth/me`: Returns the current user's session claims, resolved roles, and tenant context.
  - `POST /api/v1/auth/session`: (Optional) Validates an external provider token, creates or links the local church member record, and returns the unified church session.
  - `POST /api/v1/auth/sign-out`: Terminates active session or revokes server-side refresh tokens.

#### DTO Contracts:
```csharp
public record CurrentUserResponse(
    Guid UserId,
    Guid TenantId,
    string Email,
    string? Name,
    IReadOnlyList<string> Roles,
    bool HasCompletedProfile
);

public record AuthSessionExchangeRequest(
    string ProviderToken
);
```

### 4.2 Flutter Client Architecture
- **`AuthService` Abstraction (`mobile/lib/services/auth_service.dart`)**:
  ```dart
  abstract class AuthService {
    Future<AuthSession?> getCurrentSession();
    Future<AuthSession> signIn({required String identifier, required String secret});
    Future<void> signOut();
    Stream<AuthSession?> get sessionStateStream;
  }
  ```
- **`AuthSession` Model**:
  ```dart
  class AuthSession {
    final String accessToken;
    final String? refreshToken;
    final String userId;
    final String tenantId;
    final List<String> roles;
    final DateTime expiresAt;

    bool get isExpired => DateTime.now().isAfter(expiresAt);
    bool hasRole(String role) => roles.contains(role);
  }
  ```
- **Secure Token Persistence (`mobile/lib/services/token_storage.dart`)**:
  - Encapsulates secure platform storage (`flutter_secure_storage` or Keychain/Keystore abstraction).
  - Never stores raw tokens or credentials in plaintext `SharedPreferences`.
- **`AuthenticatedHttpClient` (`mobile/lib/services/api_client.dart`)**:
  - HTTP client wrapper that automatically attaches `Authorization: Bearer <accessToken>`.
  - Listens for `401 Unauthorized` responses to attempt automatic token refresh or notify `AuthService` to redirect to sign-in.

---

## 5. Member Profile & Family Directory Contract (Module 7)

### 5.1 Domain Model Definition

```csharp
namespace Church.Core
{
    public class Member : IMultiTenantEntity
    {
        public Guid Id { get; set; } // Matches authenticated sub / NameIdentifier
        public Guid TenantId { get; set; } // Enforced church tenant
        public string FirstName { get; set; } = string.Empty;
        public string LastName { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string? PhoneNumber { get; set; }
        public string? AvatarUrl { get; set; }
        public DateTime? DateOfBirth { get; set; }
        public DateTime? AnniversaryDate { get; set; }
        public string? Address { get; set; }

        // Family Unit Association
        public Guid? FamilyId { get; set; }
        public Family? Family { get; set; }
        public FamilyRole FamilyRole { get; set; } = FamilyRole.Individual;

        // Privacy Visibility Controls
        public DirectoryVisibility DirectoryVisibility { get; set; } = DirectoryVisibility.PublicToMembers;
        public bool ShowPhoneNumber { get; set; } = true;
        public bool ShowEmail { get; set; } = true;
        public bool ShowAddress { get; set; } = false;
        public bool ShowBirthDayAndMonth { get; set; } = true;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }

    public enum FamilyRole
    {
        Individual = 0,
        HeadOfHousehold = 1,
        Spouse = 2,
        Child = 3,
        Other = 4
    }

    public enum DirectoryVisibility
    {
        PublicToMembers = 0, // Visible to all verified church members
        LeadersOnly = 1,     // Visible only to Pastors and Admins
        Private = 2          // Hidden from church directory listing
    }

    public class Family : IMultiTenantEntity
    {
        public Guid Id { get; set; }
        public Guid TenantId { get; set; }
        public string FamilyName { get; set; } = string.Empty;
        public ICollection<Member> Members { get; set; } = new List<Member>();
    }
}
```

### 5.2 API Endpoints (`/api/v1/members`)

1. **`GET /api/v1/members/me`**
   - **Auth**: Any authenticated member.
   - **Behavior**: Returns the full profile of the caller, including unredacted personal details, family unit members, and privacy settings.
   - **Response**: `200 OK (FullMemberProfileResponse)`.

2. **`PUT /api/v1/members/me`**
   - **Auth**: Any authenticated member.
   - **Behavior**: Updates personal details (name, phone, address, avatar, dates) and privacy settings.
   - **Request**: `UpdateMemberProfileRequest`.
   - **Response**: `200 OK (FullMemberProfileResponse)`.

3. **`GET /api/v1/members`**
   - **Auth**: `[Authorize]`.
   - **Behavior**: Returns a filtered directory list for the current church tenant.
     - Regular members only see profiles where `DirectoryVisibility == PublicToMembers`.
     - Admins and Pastors see all tenant profiles regardless of `DirectoryVisibility`.
     - Fields are redacted according to member privacy flags (`ShowPhoneNumber`, `ShowEmail`, etc.).
   - **Query Parameters**: `?search=&page=1&pageSize=50`.
   - **Response**: `200 OK (PagedList<DirectoryMemberResponse>)`.

4. **`GET /api/v1/members/{id:guid}`**
   - **Auth**: `[Authorize]`.
   - **Behavior**: Returns directory profile of a specific church member.
     - If Caller is Pastor, Admin, or Self: Returns unredacted details.
     - If Caller is another Member: Redacts contact info based on member privacy settings. If member marked `DirectoryVisibility == Private` or `LeadersOnly`, returns `404 Not Found` (or `403 Forbidden`).
   - **Response**: `200 OK (DirectoryMemberResponse)`.

5. **`GET /api/v1/members/families/{id:guid}`**
   - **Auth**: `[Authorize]`.
   - **Behavior**: Retrieves family unit structure and members.

### 5.3 Member DTO Contracts

```csharp
namespace Church.API.Models
{
    public record FullMemberProfileResponse(
        Guid Id,
        Guid TenantId,
        string FirstName,
        string LastName,
        string Email,
        string? PhoneNumber,
        string? AvatarUrl,
        DateTime? DateOfBirth,
        DateTime? AnniversaryDate,
        string? Address,
        Guid? FamilyId,
        string? FamilyName,
        FamilyRole FamilyRole,
        DirectoryVisibility DirectoryVisibility,
        bool ShowPhoneNumber,
        bool ShowEmail,
        bool ShowAddress,
        bool ShowBirthDayAndMonth,
        DateTime UpdatedAt
    );

    public record DirectoryMemberResponse(
        Guid Id,
        string FullName,
        string? AvatarUrl,
        string? Email,       // Redacted if !ShowEmail && !IsPrivileged
        string? PhoneNumber, // Redacted if !ShowPhoneNumber && !IsPrivileged
        string? Address,     // Redacted if !ShowAddress && !IsPrivileged
        string? BirthdayNotice, // e.g. "April 15" if ShowBirthDayAndMonth
        Guid? FamilyId,
        string? FamilyName,
        FamilyRole FamilyRole
    );

    public record UpdateMemberProfileRequest(
        string FirstName,
        string LastName,
        string? PhoneNumber,
        string? AvatarUrl,
        DateTime? DateOfBirth,
        DateTime? AnniversaryDate,
        string? Address,
        DirectoryVisibility DirectoryVisibility,
        bool ShowPhoneNumber,
        bool ShowEmail,
        bool ShowAddress,
        bool ShowBirthDayAndMonth
    );
}
```

### 5.4 Privacy Visibility Redaction Matrix

| Field | Caller: Self | Caller: Pastor / Admin | Caller: Fellow Member (Public) | Caller: Fellow Member (Hidden) |
|---|---|---|---|---|
| **Full Name** | Visible | Visible | Visible | 404 / Hidden |
| **Avatar URL** | Visible | Visible | Visible | 404 / Hidden |
| **Phone Number** | Visible | Visible | Visible only if `ShowPhoneNumber == true` | 404 / Hidden |
| **Email Address** | Visible | Visible | Visible only if `ShowEmail == true` | 404 / Hidden |
| **Home Address** | Visible | Visible | Visible only if `ShowAddress == true` | 404 / Hidden |
| **Birthday (MM/DD)** | Visible | Visible | Visible only if `ShowBirthDayAndMonth == true` | 404 / Hidden |
| **Birth Year** | Visible | Visible | Redacted | 404 / Hidden |
| **Family Unit** | Visible | Visible | Visible | 404 / Hidden |

---

## 6. Child Tasks: File Ownership & Integration Touchpoints

To guarantee that Child Task 1 (Identity & Sign-In, Issue #18) and Child Task 2 (Member Profile, Issue #9) execute without conflicting edits, files are strictly partitioned:

| Layer | Module 9: Identity & Sign-In (Issue #18) | Module 7: Member Profile (Issue #9) |
|---|---|---|
| **Domain (`Church.Core`)** | None (uses existing `Tenant.cs`) | `Member.cs`, `Family.cs`, `DirectoryVisibility.cs` |
| **Persistence (`Church.Infrastructure`)** | Update `TenantService.cs` (read claims first) | Add `DbSet<Member>`, `DbSet<Family>` to `ApplicationDbContext.cs`, generate EF migration |
| **API Endpoints (`Church.API`)** | Minimal API map in `Endpoints/AuthEndpoints.cs` or `Program.cs` auth pipeline | Minimal API map in `Endpoints/MemberEndpoints.cs` |
| **DTOs (`Church.API/Models`)** | `AuthDtos.cs` | `MemberDtos.cs` |
| **Backend Tests (`Church.Tests`)** | `AuthApiTests.cs`, `TenantResolutionTests.cs` | `MemberApiTests.cs`, `DirectoryPrivacyTests.cs` |
| **Mobile Services (`mobile/lib`)** | `services/auth_service.dart`, `services/token_storage.dart`, `services/api_client.dart` | `services/member_service.dart` |
| **Mobile Screens (`mobile/lib`)** | `screens/login_screen.dart`, `screens/auth_gate.dart` | `screens/profile_screen.dart`, `screens/directory_screen.dart` |
| **Mobile Tests (`mobile/test`)** | `auth_service_test.dart`, `login_screen_test.dart` | `profile_screen_test.dart`, `directory_screen_test.dart` |

### Avoiding Conflicts in Shared Files:
1. **`backend/Church.API/Program.cs`**:
   - Module 9 registers JWT Bearer authentication schemes and `app.MapAuthEndpoints()`.
   - Module 7 registers `app.MapMemberEndpoints()` in a dedicated extension method.
2. **`mobile/lib/main.dart`**:
   - Module 9 introduces `AuthGate` as the app root or wraps `MainNavigationScreen`.
   - Module 7 replaces `mobile/lib/screens/profile_screen.dart` placeholder content with the full profile view, avoiding edits to `main.dart`.

---

## 7. Decisions Requiring Church Owner Guidance

The following architectural decisions require executive guidance from the Church Owner or Leadership Council. No paid selections or subscriptions are assumed:

### 7.1 Identity Provider (IdP) Selection
1. **Supabase Auth (Cloud or Self-Hosted)**:
   - *Pros*: Generous free tier (up to 50,000 monthly active users), native PostgreSQL integration, Row Level Security (RLS) support, built-in magic links and social auth.
   - *Cost*: Free tier available ($0/mo for pilot).
2. **Firebase Authentication (Google Cloud)**:
   - *Pros*: Battle-tested mobile SDKs, simple phone OTP and email authentication, free up to 50,000 monthly active users.
   - *Cost*: Free tier for Email/Google ($0/mo), paid SMS rate applies after initial phone quota.
3. **Self-Hosted OpenID Connect (OpenIddict / Keycloak)**:
   - *Pros*: Zero recurring vendor licensing costs, complete church ownership of user credentials and database, full control over multi-tenant token issuance.
   - *Cons*: Additional server maintenance and deployment operations.
4. **Auth0 / Okta**:
   - *Pros*: Enterprise-grade identity management.
   - *Cons*: Steep pricing tiers beyond 7,500 MAU; not recommended for typical church budget constraints.

### 7.2 Preferred Member Sign-In Mechanisms
Owner decision needed on primary authentication factor for congregants:
- **Option A: Phone Number OTP (SMS / WhatsApp)** — Recommended for Indian and international congregation convenience, but carries SMS gateway per-message costs.
- **Option B: Passwordless Magic Link / Email OTP** — Near-zero cost, highly secure, requires members to have accessible email on mobile.
- **Option C: Traditional Email + Password** — Zero messaging cost, but requires self-service password reset flows.

### 7.3 Multi-Tenant Directory Policy
- Should members belonging to the same church have their profiles discoverable in the directory by default (opt-out), or should church members explicitly opt in before appearing in the directory?
- *Contract Recommendation*: Default to opt-in with `DirectoryVisibility = PublicToMembers`, but with contact numbers hidden unless explicitly allowed by the member (`ShowPhoneNumber = false` default).
