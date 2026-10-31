# MVP Tenant Foundation and Provisioning Gap Audit

Parent PBI: Multi-Tenant Church Profile and Schema Setup (Issue #1), under MVP tracker #21.

## 1. Executive Summary & Objective

The goal of this audit is to provide a comprehensive, read-only implementation analysis of the multi-tenant church foundation currently residing on the `main` branch. This assessment determines whether PBI #1 ("Multi-Tenant Church Profile and Schema Setup", Issue #1) should be closed as completed or split into discrete child follow-ups, avoiding duplicated work or conflicting migrations with in-flight pull requests (such as Fellowship PR #22).

### Key Audit Finding
The foundational database schema for tenants and EF Core global query filtering are implemented and verified by automated unit and integration tests. However:
1. **Tenant Provisioning / Initialization is Completely Missing**: There are no API endpoints, CLI seed scripts, or onboarding workflows to register a new tenant (`Tenant`) record. The `Tenants` table is populated in tests only via in-memory instantiation.
2. **Church Profile Management Endpoints are Missing**: There are no CRUD or profile retrieval endpoints (`/api/v1/tenants` or `/api/v1/churches`) to inspect or update church profile attributes (such as `Name`, `Slug`, `ContactEmail`, `LogoUrl`, or `Status`).
3. **Tenant Context Resolution Relies on Prototype Headers**: The runtime tenant resolution mechanism in `TenantService` and `CustomAuthHandler` trusts client-supplied headers (`X-Tenant-Id`) with insecure fallbacks rather than validated authentication tokens.
4. **Issue #1 Should NOT Be Marked Complete**: Issue #1 cannot be closed based solely on the existence of the `Tenant` entity and migration. It must be split into narrow, targeted follow-up PBIs.

---

## 2. Existing Tenant Foundation on `main`

The table below catalogs every component of the tenant architecture present on `main`, citing exact source locations and test coverage.

| Component | Repository Path | Description & Implementation Details |
| :--- | :--- | :--- |
| **Tenant Domain Model** | `backend/Church.Core/Tenant.cs` | Defines the root `Tenant` entity with properties: `Guid Id`, `string Name`, `string Slug`, `string ContactEmail`, `string LogoUrl`, `DateTime CreatedAt`, and `string Status`. |
| **Multi-Tenant Interface** | `backend/Church.Core/IMultiTenantEntity.cs` | Contract interface requiring `Guid TenantId { get; set; }`. Implemented by all tenant-scoped entities (`Announcement`, `PrayerRequest`, `Song`, `Setlist`, `SetlistItem`). |
| **Tenant Service Abstraction** | `backend/Church.Infrastructure/ITenantService.cs` | Service contract defining `Guid GetCurrentTenantId()`. |
| **Tenant Service Implementation** | `backend/Church.API/Program.cs` (`TenantService`) | Resolves tenant ID in the following order: (1) `X-Tenant-Id` HTTP request header, (2) User claim `"church_id"`, (3) Returns `Guid.Empty` if neither exists. Registered as scoped service. |
| **EF Core DbContext & Query Filters** | `backend/Church.Infrastructure/ApplicationDbContext.cs` | Injects `ITenantService`, evaluates `_tenantId = tenantService.GetCurrentTenantId()`. Configures `Tenants` table with unique index on `Slug`. Dynamically iterates model entities implementing `IMultiTenantEntity` in `OnModelCreating` and applies global query filter: `.HasQueryFilter(e => e.TenantId == _tenantId)`. Column mapping translates C# `TenantId` to DB column `church_id` on tenant entities. |
| **Initial Migration** | `backend/Church.Infrastructure/Migrations/20261031115204_InitialCreate.cs` | Creates PostgreSQL table `Tenants` (`PK_Tenants` on `Id`, unique index `IX_Tenants_Slug` on `Slug`, default `CURRENT_TIMESTAMP` on `CreatedAt`). |
| **Subsequent Migrations** | `20261031130521_AddAnnouncements.cs`, `20261031144505_AddPrayerRequests.cs`, `20261031165556_AddWorshipAndSetlists.cs` | All downstream migrations preserve the `Tenants` table and add `church_id` foreign-key style tenant indexes across entities (`Announcements`, `PrayerRequests`, `Songs`, `Setlists`, `SetlistItems`). |
| **Model Snapshot** | `backend/Church.Infrastructure/Migrations/ApplicationDbContextModelSnapshot.cs` | Retains full entity definition for `Church.Core.Tenant` and tenant keys across all active modules. |
| **Custom Auth Middleware** | `backend/Church.API/Program.cs` (`CustomAuthHandler`) | Inspects test headers `X-User-Role`, `X-User-Id`, and `X-Tenant-Id` (or `Authorization: Bearer <role>`) to build `ClaimsPrincipal` with `ClaimTypes.Role`, `ClaimTypes.NameIdentifier`, and `"church_id"`. |
| **Tenant Provisioning Endpoints** | *None* | **Missing**. No endpoints exist under `/api/v1/tenants`, `/api/v1/churches`, or `/api/v1/admin/tenants`. |
| **Church Profile Endpoints** | *None* | **Missing**. No endpoints exist to view or update church details (such as settings, branding, contact info). |

### Relevant Tests on `main` Demonstrating Tenant Isolation

Automated tests demonstrating tenant isolation behavior include:

1. **`Church.Tests.DbContextTests`** (`backend/Church.Tests/DbContextTests.cs`):
   - `TenantQueryFilter_FiltersCorrectly`: Tests that entities belonging to `_tenantId1` and `_tenantId2` are strictly segregated by `ApplicationDbContext` query filters when queried under separate `MockTenantService` contexts.
   - `TenantModel_Creation`: Verifies property assignments and constraints on `Tenant` model.
2. **`Church.Tests.AnnouncementsApiTests`** (`backend/Church.Tests/AnnouncementsApiTests.cs`):
   - `TenantIsolation_AnnouncementsFilteredByChurchId`: Verifies that announcements created in Church A are not returned in feed queries made with `X-Tenant-Id: <Church B>`.
3. **`Church.Tests.WorshipApiTests`** (`backend/Church.Tests/WorshipApiTests.cs`):
   - `TenantIsolation_SongsAndSetlistsNeverExposedAcrossTenants`: Verifies cross-tenant isolation for songs and service setlists, ensuring Church B cannot view or reference songs belonging to Church A.
4. **`Church.Tests.PrayerRequestsApiTests`** (`backend/Church.Tests/PrayerRequestsApiTests.cs`):
   - Verifies pastoral prayer request isolation and role boundaries per tenant.

---

## 3. Issue #1 Acceptance Criteria Verification Matrix

Evaluating Issue #1 requirements ("Multi-Tenant Church Profile and Schema Setup") against current implementation on `main`:

| Acceptance Criteria / Requirement | Status | Evidence (File Paths & Tests) | Gap & Risk Analysis |
| :--- | :--- | :--- | :--- |
| **1. Multi-Tenant Schema & Isolation Key**<br>Database schema supports distinct church tenants; records partitioned by tenant identifier. | **DEMONSTRATED** | - `backend/Church.Core/IMultiTenantEntity.cs`<br>- `backend/Church.Core/Tenant.cs`<br>- `backend/Church.Infrastructure/ApplicationDbContext.cs`<br>- `backend/Church.Infrastructure/Migrations/20261031115204_InitialCreate.cs`<br>- `TenantQueryFilter_FiltersCorrectly` in `backend/Church.Tests/DbContextTests.cs` | Fully demonstrated at the ORM and schema level. Query filters enforce partition across all modules. |
| **2. Dynamic Tenant Resolution**<br>Backend resolves active church context per request. | **DEMONSTRATED (Prototype Only)** | - `backend/Church.Infrastructure/ITenantService.cs`<br>- `backend/Church.API/Program.cs` (`TenantService`) | Demonstrated via `X-Tenant-Id` header and `"church_id"` claim. **Gap**: Production requires server-validated JWT claim resolution without trusting client-supplied override headers (documented in `docs/architecture/mvp-identity-and-member-contract.md`). |
| **3. Church Tenant Registration / Provisioning Endpoint**<br>API to provision a new church tenant with slug, name, contact email, and active status. | **MISSING** | - No endpoints in `backend/Church.API/Program.cs`<br>- No tests in `backend/Church.Tests` | **High Gap**: Impossible for a new church to onboard through the API. The `Tenants` table can only be modified via direct DB SQL manipulation. |
| **4. Church Profile Retrieval & Configuration**<br>Endpoint to retrieve church profile details (`GET /api/v1/churches/{slug}` or `/api/v1/churches/me`). | **MISSING** | - No DTOs in `backend/Church.API/Models`<br>- No endpoints in `backend/Church.API/Program.cs` | **High Gap**: The mobile client and web client cannot fetch church metadata (logo URL, name, contact email) to customize app branding or display church info. |
| **5. Cross-Tenant Data Leakage Prevention**<br>Requests without a valid tenant context are rejected; queries never cross tenant boundaries. | **PARTIALLY DEMONSTRATED** | - `TenantIsolation_AnnouncementsFilteredByChurchId`<br>- `TenantIsolation_SongsAndSetlistsNeverExposedAcrossTenants` | Query filters prevent cross-tenant exposure when tenant ID is provided. **Gap**: When tenant ID is missing or invalid (`Guid.Empty`), some endpoints return 400 Bad Request (`ResolveTenantId`), but others fallback silently to querying with `Guid.Empty`, returning 0 records rather than a clear 400/401 error. |

---

## 4. Fellowship Ministry Spaces (PR #22 / Branch #6) Persistence Audit

Branch `origin/feat/fellowship-ministry-spaces-pbi-6-16669022207875329328` (Resolves Issue #6, PR #22) was analyzed for tenant persistence modifications:

### Persistence Changes Introduced in PR #22
1. **Domain Entities** (`backend/Church.Core/`):
   - `FellowshipGroup.cs`: Implements `IMultiTenantEntity`, mapped to column `church_id`.
   - `FellowshipMember.cs`: Implements `IMultiTenantEntity`, mapped to column `church_id`.
   - `FellowshipPost.cs`: Implements `IMultiTenantEntity`, mapped to column `church_id`.
2. **DbContext Configuration** (`backend/Church.Infrastructure/ApplicationDbContext.cs`):
   - Adds `DbSet<FellowshipGroup>`, `DbSet<FellowshipMember>`, `DbSet<FellowshipPost>`.
   - Maps table names `FellowshipGroups`, `FellowshipMembers`, `FellowshipPosts`.
   - Creates indexes on `church_id` (`IX_FellowshipGroups_church_id`, `IX_FellowshipMembers_church_id`, `IX_FellowshipPosts_church_id`).
   - Relies on the existing `IMultiTenantEntity` global query filter configuration loop in `OnModelCreating`.
3. **Migration** (`backend/Church.Infrastructure/Migrations/`):
   - Adds `20261031172108_AddFellowshipMinistrySpaces.cs`.
   - Updates `ApplicationDbContextModelSnapshot.cs`.

### Boundaries & Collision Prevention
- PR #22 **does not touch or modify** the `Tenant` entity, `Tenants` table schema, `InitialCreate` migration, or `ITenantService`.
- Any follow-up implementation to tenant provisioning or church profiles will NOT conflict with PR #22, provided it does not re-generate migrations from a stale branch state or modify fellowship models.

---

## 5. Recommended Path Forward: Child Tasks & Work Breakdown

Rather than marking PBI #1 closed (which would leave tenant onboarding unbuilt) or attempting to shoehorn provisioning into unrelated feature modules, PBI #1 should be **split into two distinct child PBIs**:

### Child Task 1: Church Profile Discovery & Management API
- **Scope**:
  - Add DTOs: `ChurchProfileResponse`, `UpdateChurchProfileRequest`.
  - Implement endpoints under `/api/v1/churches`:
    - `GET /api/v1/churches/{slug}`: Public endpoint (`[AllowAnonymous]`) allowing mobile clients to resolve a church by slug, retrieving display name, logo URL, and public contact info.
    - `GET /api/v1/churches/me`: Authenticated endpoint returning current tenant profile.
    - `PUT /api/v1/churches/me`: Protected endpoint (`[Authorize(Roles = "Admin")]`) to update church details (name, contact email, logo URL).
  - Add integration tests verifying profile retrieval by slug and role-protected profile update.
- **Dependencies**: Uses existing `Tenant` entity and `ApplicationDbContext.Tenants`. No migration required unless extra profile fields are requested.

### Child Task 2: Platform Provisioning & Pilot Tenant Onboarding
- **Scope**:
  - Implement initial tenant initialization path (Admin CLI seed command or platform provisioning endpoint `POST /api/v1/admin/tenants`).
  - Validation: Verify unique slug generation, required contact email, and active status defaults.
  - Coordinate with Module 10 (Pilot Deployment, Issue #20) to ensure the initial pilot church is seeded into the production database safely on first migration run.
  - Transition `TenantService` to enforce server-validated JWT claims as defined in `docs/architecture/mvp-identity-and-member-contract.md`.
- **Dependencies**: Depends on database migration pipeline; coordinated with Module 9 (Identity & Auth) and Module 10 (Pilot Deployment).

---

## 6. Conclusion

The core database foundation and multi-tenant query filter isolation are operational and well-tested on `main`. However, church provisioning and profile accessibility are missing. Proceeding with the recommended child PBIs will cleanly complete the tenant foundation without disturbing in-flight fellowship persistence in PR #22.
