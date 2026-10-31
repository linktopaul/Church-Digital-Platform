# Confidential Prayer Request API & Visibility Contract

## 1. Executive Summary & Purpose

This contract establishes the architectural specifications, domain models, Data Transfer Objects (DTOs), visibility rules, and authorization boundaries for:
- **Module 3: Confidential Pastoral Prayer** (PBI Issue #3, under MVP Tracker #21)

Prayer requests often contain sensitive, deeply personal, and spiritually vulnerable information (such as health diagnoses, marriage struggles, financial distress, or family crises). Improper exposure of prayer requests can lead to severe breaches of trust, pastoral confidentiality violations, and legal/regulatory liabilities.

This document sets explicit boundaries for backend and mobile implementations:
1. Strict server-side isolation and global tenant filtering.
2. Safe privacy defaults (`PastorOnly` visibility by default).
3. Explicit role separation (Pastors vs. Admins vs. Regular Members).
4. Direct integration boundaries with **Module 9 (Identity & Tenant Context, PR #28 / Issue #18)** and **Module 6 (Fellowship Ministry Spaces, PR #22 / Issue #6)**.
5. Strict prohibitions against logging or exposing prayer request content in telemetry, notifications, and client diagnostic pipelines.

---

## 2. Domain Model & Core Specifications

### 2.1 Entity Definition (`Church.Core.PrayerRequest`)

All prayer requests implement `IMultiTenantEntity` to ensure automatic query filtering in EF Core.

```csharp
namespace Church.Core
{
    public class PrayerRequest : IMultiTenantEntity
    {
        public Guid Id { get; set; }

        /// <summary>
        /// Tenant identifier representing the church congregation.
        /// EF Core global query filter ensures tenant isolation.
        /// </summary>
        public Guid TenantId { get; set; }

        /// <summary>
        /// Compatibility alias mapped to TenantId.
        /// </summary>
        public Guid ChurchId
        {
            get => TenantId;
            set => TenantId = value;
        }

        /// <summary>
        /// Identifier of the authoring church member (matches ClaimTypes.NameIdentifier / sub).
        /// </summary>
        public Guid MemberId { get; set; }

        /// <summary>
        /// Cached author display name for rendering in lists without joining external profiles.
        /// Redacted or replaced with "Anonymous" if IsAnonymous is true.
        /// </summary>
        public string AuthorName { get; set; } = string.Empty;

        /// <summary>
        /// Short summary or title of the request (max 150 chars).
        /// </summary>
        public string Title { get; set; } = string.Empty;

        /// <summary>
        /// Detailed confidential prayer content.
        /// </summary>
        public string Content { get; set; } = string.Empty;

        /// <summary>
        /// Current lifecycle status of the prayer request.
        /// Default: Submitted.
        /// </summary>
        public PrayerRequestStatus Status { get; set; } = PrayerRequestStatus.Submitted;

        /// <summary>
        /// Audience visibility setting.
        /// Default: PastorOnly.
        /// </summary>
        public PrayerVisibility Visibility { get; set; } = PrayerVisibility.PastorOnly;

        /// <summary>
        /// Optional ministry space reference when Visibility is MinistryGroupOnly.
        /// Relates to FellowshipGroup in Module 6 (PR #22).
        /// </summary>
        public Guid? MinistryGroupId { get; set; }

        /// <summary>
        /// Whether the member requested their identity be masked from non-pastoral viewers.
        /// </summary>
        public bool IsAnonymous { get; set; } = false;

        /// <summary>
        /// Optional pastoral notes or response tracking (confidential to Pastors).
        /// </summary>
        public string? PastoralNotes { get; set; }

        /// <summary>
        /// Timestamp when the prayer request was marked answered or resolved.
        /// </summary>
        public DateTime? AnsweredAt { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
```

### 2.2 Enumerations

#### `PrayerRequestStatus`
Defines the spiritual and pastoral workflow lifecycle:
```csharp
namespace Church.Core
{
    public enum PrayerRequestStatus
    {
        /// <summary>
        /// Initial state upon submission. Awaiting pastoral review.
        /// </summary>
        Submitted = 0,

        /// <summary>
        /// Active state indicating a pastor or ministry group is actively interceding.
        /// </summary>
        Praying = 1,

        /// <summary>
        /// Praise report / answered prayer resolution.
        /// </summary>
        Answered = 2,

        /// <summary>
        /// Inactive or archived request, excluded from active intercession feeds.
        /// </summary>
        Archived = 3
    }
}
```

#### `PrayerVisibility`
Governs the audience eligible to read the prayer request:
```csharp
namespace Church.Core
{
    public enum PrayerVisibility
    {
        /// <summary>
        /// Strictly confidential to ordained Pastors of the church tenant and the author.
        /// Platform Admins WITHOUT the Pastor role CANNOT view.
        /// </summary>
        PastorOnly = 0,

        /// <summary>
        /// Visible to all verified members of the church tenant.
        /// </summary>
        ChurchPublic = 1,

        /// <summary>
        /// Visible only to verified members of a specific Fellowship Ministry Space (Module 6).
        /// Requires valid MinistryGroupId and active membership in that group.
        /// </summary>
        MinistryGroupOnly = 2
    }
}
```

---

## 3. Role-Based Access Control (RBAC) Matrix

### 3.1 Principles of Pastoral Privilege vs. Administrative Power
- **Pastoral Privilege**: The `Pastor` role carries sacred spiritual duty and confidentiality. Pastors can view all `PastorOnly` requests within their church tenant.
- **Administrative Separation**: The `Admin` role manages infrastructure, users, billing, and church configurations. **Admins do NOT inherit pastoral oversight.** Admins cannot view `PastorOnly` requests unless they are also explicitly granted the `Pastor` role or are the author of the request.
- **Author Ownership**: Regardless of role, any verified `Member` can view, edit, or archive requests they authored.

### 3.2 Detailed Access Matrix

| Action / Operation | Member (Author) | Member (Non-Author) | Pastor (Non-Author) | Admin (Non-Pastor) | Fellowship Leader (Module 6) |
|---|---|---|---|---|---|
| **Create Request (`PastorOnly`)** | Allowed | N/A (becomes Author) | Allowed | Allowed | Allowed |
| **Create Request (`ChurchPublic`)** | Allowed | N/A (becomes Author) | Allowed | Allowed | Allowed |
| **Create Request (`MinistryGroupOnly`)** | Allowed (if member of group) | N/A (becomes Author) | Allowed | Allowed (if member) | Allowed (if member of group) |
| **Read `PastorOnly` Request** | Allowed | **DENIED (404/403)** | **Allowed** | **DENIED (403 Forbidden)** | **DENIED (403 Forbidden)** |
| **Read `ChurchPublic` Request** | Allowed | **Allowed** | **Allowed** | **Allowed** | **Allowed** |
| **Read `MinistryGroupOnly` Request** | Allowed | **Allowed ONLY if group member** | **Allowed** | **DENIED unless group member** | **Allowed if group member** |
| **List Own Requests (`/api/v1/prayer-requests/my`)** | Allowed (all visibility) | N/A | Allowed (own authored) | Allowed (own authored) | Allowed (own authored) |
| **List All Requests (`/api/v1/prayer-requests`)** | Sees only Public + joined Group | Sees only Public + joined Group | Sees all Tenant requests | Sees only Public + joined Group | Sees Public + managed Group |
| **Update Request Content/Title** | Allowed | **DENIED** | **DENIED** (cannot tamper with member prayer) | **DENIED** | **DENIED** |
| **Update Status (`Praying` / `Answered`)** | Allowed (own request) | **DENIED** | **Allowed** (for any request in tenant) | **DENIED** | Allowed (only for their group) |
| **Add Pastoral Notes** | **DENIED** | **DENIED** | **Allowed** | **DENIED** | **DENIED** |
| **Delete / Archive Request** | Allowed (own request) | **DENIED** | Allowed (can archive tenant requests) | **DENIED** | Allowed (for group space) |

---

## 4. Server-Side Query & Filter Specifications

### 4.1 Safe Multi-Tenant Isolation
1. **Global Query Filter**:
   Entity Framework Core configuration in `ApplicationDbContext.cs`:
   ```csharp
   builder.Entity<PrayerRequest>(entity =>
   {
       entity.HasKey(e => e.Id);
       entity.Property(e => e.Title).IsRequired().HasMaxLength(150);
       entity.Property(e => e.Content).IsRequired();
       entity.Property(e => e.Status).HasConversion<string>();
       entity.Property(e => e.Visibility).HasConversion<string>();
       entity.Ignore(e => e.ChurchId);

       entity.HasQueryFilter(e => e.TenantId == _tenantService.GetCurrentTenantId());
   });
   ```
2. **Cross-Tenant Guarding**:
   - `TenantService.GetCurrentTenantId()` resolves the tenant strictly from validated claims (`tenant_id` or `church_id`).
   - If `GetCurrentTenantId()` returns `Guid.Empty`, endpoints must return `401 Unauthorized` or `400 Bad Request`.
   - Any query attempting cross-tenant access via client-supplied parameters is rejected.

### 4.2 Query Resolution Logic for List Feeds
When querying `GET /api/v1/prayer-requests`:

```csharp
var tenantId = tenantService.GetCurrentTenantId();
var currentUserId = CurrentUserHelper.GetCurrentUserId(user);
var isPastor = user.IsInRole("Pastor");

// Fetch active group IDs for the current user from Module 6 Fellowship context
var userGroupIds = await db.FellowshipMembers
    .Where(fm => fm.MemberId == currentUserId)
    .Select(fm => fm.FellowshipGroupId)
    .ToListAsync();

IQueryable<PrayerRequest> query = db.PrayerRequests.AsNoTracking();

if (isPastor)
{
    // Pastors have tenant-wide pastoral oversight
    // Can view PastorOnly, ChurchPublic, and all MinistryGroupOnly requests
    query = query.Where(p => p.Status != PrayerRequestStatus.Archived);
}
else
{
    // Non-pastor callers (Regular Members, Admins without Pastor role)
    // CANNOT see PastorOnly requests authored by others
    query = query.Where(p =>
        p.MemberId == currentUserId || // Own requests
        p.Visibility == PrayerVisibility.ChurchPublic || // Public requests
        (p.Visibility == PrayerVisibility.MinistryGroupOnly &&
         p.MinistryGroupId.HasValue &&
         userGroupIds.Contains(p.MinistryGroupId.Value)) // Joined fellowship groups
    ).Where(p => p.Status != PrayerRequestStatus.Archived);
}
```

### 4.3 Safe Defaults
- **Default Visibility**: If `Visibility` is omitted in `CreatePrayerRequestRequest`, the server enforces `PrayerVisibility.PastorOnly`.
- **Default Status**: New requests are initialized to `PrayerRequestStatus.Submitted`.
- **Anonymity Masking**:
  - If `IsAnonymous == true`:
    - For Fellow Members and Public Feeds: `AuthorName` is masked to `"Anonymous Member"` and `MemberId` is omitted (`Guid.Empty`).
    - For Pastors: `AuthorName` and `MemberId` remain visible so the Pastor knows who to contact for pastoral counseling (unless the leadership council mandates zero-knowledge anonymity, see Section 8).

---

## 5. REST API Endpoints & DTO Contracts

Base Route: `/api/v1/prayer-requests`

### 5.1 Endpoint Definitions

#### 1. `POST /api/v1/prayer-requests`
- **Description**: Submit a new prayer request.
- **Authorization**: `[Authorize]` (Any authenticated tenant member).
- **Validation**:
  - `Title` and `Content` required.
  - If `Visibility == MinistryGroupOnly`, `MinistryGroupId` must be provided and caller must be an active member of that group.
- **Response**: `201 Created` with `PrayerRequestResponse`.

#### 2. `GET /api/v1/prayer-requests/my`
- **Description**: List all prayer requests authored by the current authenticated caller.
- **Authorization**: `[Authorize]`.
- **Response**: `200 OK` with `List<PrayerRequestResponse>`.

#### 3. `GET /api/v1/prayer-requests`
- **Description**: List visible prayer requests according to the caller's role and group memberships.
- **Authorization**: `[Authorize]`.
- **Query Parameters**:
  - `?status=Submitted|Praying|Answered` (optional filter)
  - `?visibility=PastorOnly|ChurchPublic|MinistryGroupOnly` (optional filter)
  - `?groupId={guid}` (optional filter for a specific fellowship space)
  - `?page=1&pageSize=20` (pagination)
- **Response**: `200 OK` with `PagedResult<PrayerRequestResponse>`.

#### 4. `GET /api/v1/prayer-requests/{id:guid}`
- **Description**: Retrieve a specific prayer request by ID.
- **Authorization**: `[Authorize]`.
- **Behavior**:
  - Returns `404 Not Found` if entity does not exist or belongs to another tenant.
  - Returns `403 Forbidden` if caller lacks visibility rights (e.g., non-pastor trying to view another member's `PastorOnly` request).
- **Response**: `200 OK` with `PrayerRequestDetailResponse`.

#### 5. `PATCH /api/v1/prayer-requests/{id:guid}/status`
- **Description**: Update the prayer request status (e.g., from `Submitted` to `Praying` or `Answered`).
- **Authorization**: `[Authorize]`.
- **Permissions**:
  - Author can update their own status (e.g. to `Answered` or `Archived`).
  - Pastors can update any request in the church tenant.
  - Fellowship Leaders can update status for requests within their managed group.
- **Response**: `200 OK` with `PrayerRequestResponse`.

#### 6. `PATCH /api/v1/prayer-requests/{id:guid}/pastoral-notes`
- **Description**: Add or update confidential pastoral guidance notes.
- **Authorization**: `[Authorize(Policy = "PastorOnly")]`.
- **Response**: `200 OK` with `PrayerRequestDetailResponse`.

#### 7. `DELETE /api/v1/prayer-requests/{id:guid}`
- **Description**: Soft-delete or archive a prayer request.
- **Authorization**: `[Authorize]`.
- **Permissions**: Author or Pastor.

---

### 5.2 Request and Response DTO Shapes

```csharp
namespace Church.API.Models
{
    // Request DTOs
    public record CreatePrayerRequestRequest(
        string Title,
        string Content,
        PrayerVisibility? Visibility, // Defaults to PastorOnly if null
        Guid? MinistryGroupId,        // Required if Visibility == MinistryGroupOnly
        bool IsAnonymous = false
    );

    public record UpdatePrayerRequestContentRequest(
        string Title,
        string Content,
        PrayerVisibility Visibility,
        bool IsAnonymous
    );

    public record UpdatePrayerRequestStatusRequest(
        PrayerRequestStatus Status
    );

    public record UpdatePastoralNotesRequest(
        string PastoralNotes
    );

    // Response DTOs
    public record PrayerRequestResponse(
        Guid Id,
        Guid ChurchId,
        Guid? MemberId,       // Empty if IsAnonymous && caller is not Pastor/Author
        string AuthorName,    // "Anonymous Member" if IsAnonymous && caller is not Pastor/Author
        string Title,
        string Content,
        PrayerRequestStatus Status,
        PrayerVisibility Visibility,
        Guid? MinistryGroupId,
        bool IsAnonymous,
        DateTime CreatedAt,
        DateTime UpdatedAt,
        DateTime? AnsweredAt
    );

    public record PrayerRequestDetailResponse(
        Guid Id,
        Guid ChurchId,
        Guid? MemberId,
        string AuthorName,
        string Title,
        string Content,
        PrayerRequestStatus Status,
        PrayerVisibility Visibility,
        Guid? MinistryGroupId,
        string? MinistryGroupName,
        bool IsAnonymous,
        string? PastoralNotes, // Included ONLY if caller has Pastor role or is Author
        DateTime CreatedAt,
        DateTime UpdatedAt,
        DateTime? AnsweredAt
    );
}
```

---

## 6. Privacy, Telemetry, and Notification Guardrails

In adherence to Codex Code Review Rules and privacy principles:

1. **No Prayer Content in Server Logs**:
   - Diagnostic logging (`ILogger`) must NEVER log `request.Content`, `request.Title`, or `request.PastoralNotes`.
   - Permissible log statement:
     ```csharp
     _logger.LogInformation("Prayer request {PrayerId} created for tenant {TenantId} with visibility {Visibility}",
         prayerRequest.Id, prayerRequest.TenantId, prayerRequest.Visibility);
     ```
2. **No Sensitive Prayer Text in Push Notifications**:
   - Push notifications (e.g. FCM/APNs) to Pastors or group members must contain generic summary text only:
     - *Safe*: `"New confidential prayer request received for pastoral care."`
     - *Unsafe*: `"John Doe requested prayer: 'Please pray for my chemotherapy treatment tomorrow.'"`
   - Members must authenticate within the mobile app to decrypt or retrieve the actual prayer text via the secure API client.
3. **No Unauthenticated or Public Feed Exposure**:
   - No prayer endpoint shall ever have `[AllowAnonymous]`.
   - Global query filters in EF Core must never be bypassed using `.IgnoreQueryFilters()`.

---

## 7. File Ownership & Integration Boundaries

To maintain clean task isolation and avoid merge collisions with active child tasks, the following file boundaries are defined:

| Repository Layer | Module 3: Prayer Request Implementation | Shared Integration Notes |
|---|---|---|
| **Domain Entities (`Church.Core`)** | `PrayerRequest.cs`, `PrayerRequestStatus.cs`, `PrayerVisibility.cs` | Modifies `PrayerRequest.cs` to add `Visibility`, `Title`, `IsAnonymous`. |
| **Persistence (`Church.Infrastructure`)** | `ApplicationDbContext.cs` (`DbSet<PrayerRequest>`), EF migration `AddPrayerRequestVisibility` | Entity mapping configuration in dedicated extension or isolated block. |
| **API Endpoints (`Church.API`)** | `Endpoints/PrayerRequestEndpoints.cs` (or extension method mapped in `Program.cs`) | Avoid monolith additions to `Program.cs`. Use `app.MapPrayerRequestEndpoints()`. |
| **API DTOs (`Church.API/Models`)** | `PrayerRequestDtos.cs` | Contains all prayer-related records. |
| **Backend Tests (`Church.Tests`)** | `PrayerRequestsApiTests.cs`, `PrayerPrivacyIsolationTests.cs` | Unit and integration tests covering role separation, cross-tenant isolation, and anonymity redaction. |
| **Mobile Models (`mobile/lib/models`)** | `prayer_request_model.dart` | Immutable Dart models with `fromJson` / `toJson`. |
| **Mobile Services (`mobile/lib/services`)** | `prayer_service.dart` | Uses `api_client.dart` from Module 9 (PR #28). Attaches bearer token. |
| **Mobile Screens (`mobile/lib/screens`)** | `prayer_screen.dart`, `prayer_detail_screen.dart`, `create_prayer_screen.dart` | Replaces placeholder screen with tabbed feeds (My Prayers, Pastoral Prayer, Church Needs). |
| **Mobile Tests (`mobile/test`)** | `prayer_screen_test.dart`, `prayer_service_test.dart` | Widget and mock HTTP service tests. |

---

## 8. Cross-Module Dependencies & Conflict Preventions

### 8.1 Module 9: Identity, Sign-In & Tenant Context (PR #28 / Issue #18)
- **Dependency**: Stable `MemberId` derived from validated JWT token claims (`ClaimTypes.NameIdentifier` or `sub`) rather than test headers.
- **Current State Compatibility**: During development and testing, `CustomAuthHandler` in `Program.cs` requires `X-User-Id`, `X-User-Role`, and `X-Tenant-Id` headers.
- **Production Alignment**: When PR #28 merges, `PrayerRequestEndpoints` will seamlessly read the authenticated principal without code changes.

### 8.2 Module 6: Fellowship Ministry Spaces (PR #22 / Issue #6)
- **Dependency**: When a prayer request is submitted with `PrayerVisibility.MinistryGroupOnly`, the backend validates that `MinistryGroupId` exists in `FellowshipGroups` and that the caller exists in `FellowshipMembers`.
- **Conflict Prevention**: Module 3 will query `DbSet<FellowshipMember>` as a read-only dependency without modifying the `FellowshipGroup` or `FellowshipMember` entity definitions.

---

## 9. Decisions Requiring Church Leadership Guidance

The following architectural decisions are documented for executive confirmation by Church Leadership or the Product Council without making premature assumptions:

1. **Admin Visibility Exclusion**:
   - *Current Decision*: Admins are strictly prohibited from viewing `PastorOnly` prayer requests unless they also hold the `Pastor` role.
   - *Alternative*: Should Church Board Admins have an audit view (with prayer content masked, only timestamps and status visible) for pastoral accountability?
2. **Pastor Attribution for Anonymous Requests**:
   - *Current Decision*: Pastors can see the author's identity for anonymous requests to provide direct spiritual care, while fellow members see `"Anonymous Member"`.
   - *Alternative*: Strict zero-knowledge anonymity where even Pastors cannot see the author's identity unless the author consents.
3. **Intercessory Prayer Team Role**:
   - Does the church require a designated `PrayerTeam` or `Intercessor` role between `Pastor` and regular `Member` that can view requests marked for prayer ministry?
4. **Data Retention & Expiration Policy**:
   - Should answered or archived prayer requests be automatically purged after a configurable retention window (e.g., 180 days or 1 year) to minimize long-term privacy liability?
