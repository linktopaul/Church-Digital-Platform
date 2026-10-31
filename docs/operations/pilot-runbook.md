# Portable Pilot Operations, Recovery, and Smoke Runbook

> **Context & Disclaimer**:
> This runbook is a draft operational specification created under **Pilot Operations PBI #19** (MVP tracker #21).
> **Important**: This document distinguishes between *verified existing local codebase configuration* and *proposed/unverified operational procedures*. No live infrastructure has been provisioned, no cloud services have been contracted, and no production backup/restore or disaster recovery has been executed or verified against a live database. All deployment and migration procedures described for pilot environments are proposed specifications pending pilot infrastructure establishment and executive approvals.

---

## 1. System Overview & Architecture Touchpoints

The Church Digital Platform comprises three core tiers designed for multi-tenant church community operations:

1. **Backend Web API (`backend/Church.API`)**:
   - Built on ASP.NET Core (.NET 10.0 / `net10.0`).
   - Entity Framework Core with Npgsql PostgreSQL provider (`backend/Church.Infrastructure`).
   - Tenant isolation enforced via EF Core global query filters implementing `IMultiTenantEntity` against `TenantService.GetCurrentTenantId()`.
2. **Mobile Client (`mobile/`)**:
   - Built with Flutter (Material 3).
   - Configurable backend base URL via compile-time environment variable `CHURCH_API_BASE_URL`.
   - Feature modules: Announcements/Feed (Home), Prayer Requests, Worship & Sunday Setlists, Messages/Fellowships, Member Profile.
3. **Continuous Integration (`.github/workflows/`)**:
   - `.github/workflows/auto-orchestrator.yml`: Runs `.NET 10 unit tests` across all `*Tests.csproj` in Release mode.
   - `.github/workflows/flutter-mobile-ci.yml`: Runs `flutter test` on push/PR to `main`.

---

## 2. Verified Existing Local Setup vs. Proposed Pilot Process

| Area | Verified Existing Local Implementation (on `main`) | Proposed Portable Pilot Process (Unverified / Planned) |
|---|---|---|
| **API Runtime** | .NET 10 Web API running locally on Kestrel (`http://localhost:5178` or configured launch settings). Verified passing unit/integration tests with in-memory DB. | Containerized Kestrel service (Docker / systemd) behind reverse proxy (Caddy or NGINX) with TLS termination. *(Proposed / Unverified)* |
| **Database** | PostgreSQL connection string defined in `appsettings.json` (`Host=localhost;Database=ChurchDigitalPlatform;Username=postgres;Password=postgres`). | Standalone or managed PostgreSQL 16+ instance. Secrets provided via environment variables. *(Proposed / Unverified)* |
| **Migrations** | 4 EF Core migrations present in `backend/Church.Infrastructure/Migrations`: `InitialCreate`, `AddAnnouncements`, `AddPrayerRequests`, `AddWorshipAndSetlists`. | Migration script / bundle applied during maintenance window before API container startup. *(Proposed / Unverified)* |
| **Authentication** | Prototype `CustomAuthHandler` in `Program.cs` accepting `X-User-Role`, `X-User-Id`, `X-Tenant-Id`, or mock bearer tokens (`Bearer admin`, `Bearer pastor`, `Bearer member`). | Cryptographically signed JWT Bearer authentication (OIDC / OAuth2) as defined in `docs/architecture/mvp-identity-and-member-contract.md`. Test header auth disabled in production. *(Proposed / Unverified)* |
| **Tenant Resolution**| `TenantService` inspects `X-Tenant-Id` header, then `church_id` claim, else `Guid.Empty`. | `TenantService` strictly resolves tenant from signed JWT claims (`tenant_id` or `church_id`), rejecting client-supplied headers in production. *(Proposed / Unverified)* |
| **Mobile Config** | `WorshipScreen` defaults to `http://10.0.2.2:5178` (Android emulator loopback) if `CHURCH_API_BASE_URL` is omitted. | Built with `--dart-define=CHURCH_API_BASE_URL=https://pilot-api.example-church.org` pointing to HTTPS endpoint. *(Proposed / Unverified)* |
| **Health Checks** | No dedicated `/health` or `/ready` endpoint currently mapped in `backend/Church.API/Program.cs`. Base OpenAPI spec mapped only in Development. | Map ASP.NET Core Health Checks at `/healthz/live` (liveness) and `/healthz/ready` (readiness with DB check). *(Proposed / Unverified)* |
| **Backups & Recovery**| Not executed or configured in codebase. | Automated logical backups (`pg_dump -Fc`) with scheduled verification restore into an isolated staging database. *(Proposed / Unverified)* |

---

## 3. Configuration & Secrets Management (Variable Names Only)

To prevent credential leakage and enable vendor neutrality across self-hosted virtual machines or container environments, all settings must be injected via environment variables.

> **Privacy & Security Directive**: Never commit actual connection strings, database passwords, signing keys, or member data to repositories, configuration files, or logs.

### 3.1 Backend API Environment Variables

| Variable Name | Required | Purpose / Notes |
|---|---|---|
| `ASPNETCORE_ENVIRONMENT` | Yes | Set to `Production` for pilot deployment. (Enables secure metadata enforcement, disables Swagger/OpenAPI debug endpoints). |
| `ASPNETCORE_URLS` | Yes | Binding URLs, e.g., `http://0.0.0.0:8080`. |
| `ConnectionStrings__DefaultConnection` | Yes | PostgreSQL connection string (`Host=...;Database=...;Username=...;Password=...`). |
| `Authentication__Authority` | Yes (Module 9) | OIDC provider authority URL (e.g., self-hosted Keycloak, OpenIddict, or Supabase Auth). |
| `Authentication__Audience` | Yes (Module 9) | Expected JWT audience identifier for the church platform API. |
| `Logging__LogLevel__Default` | Optional | Set to `Information` or `Warning`. |
| `Logging__LogLevel__Microsoft.AspNetCore` | Optional | Set to `Warning` to avoid log spamming. |
| `Logging__LogLevel__Microsoft.EntityFrameworkCore.Database.Command` | Optional | Set to `Warning` in production to prevent query parameter and sensitive payload logging. |

### 3.2 Mobile Client Environment Variables

Passed during Flutter compilation via `--dart-define`:

| Variable Name | Required | Purpose / Notes |
|---|---|---|
| `CHURCH_API_BASE_URL` | Yes | Root URL of the pilot backend API (e.g., `https://api.pilot.church.local` or public HTTPS URL). Must not have a trailing slash. |
| `CHURCH_DEFAULT_TENANT_ID` | Optional | Default tenant identifier for single-church pilot testing during pre-login discovery. |

---

## 4. API & Database Health Checks

### 4.1 Verified Current State
Currently, `backend/Church.API/Program.cs` does not expose an unauthenticated health probe. The minimal API groups (`/api/v1/announcements`, `/api/v1/prayer-requests`, `/api/v1/worship`) all enforce authorization via `.RequireAuthorization()`. Unauthenticated requests to these endpoints return `401 Unauthorized`.

### 4.2 Proposed Health Check Implementation *(Unverified / Proposed)*
For reliable container orchestration, reverse proxy load balancer routing, and monitoring, the following standard endpoints should be registered in `Program.cs`:

1. **Liveness Probe (`GET /healthz/live`)**:
   - Returns `200 OK` (`"Healthy"`) if the Kestrel web server process is actively responding.
   - Does not touch external dependencies.
2. **Readiness Probe (`GET /healthz/ready`)**:
   - Checks database connectivity using `DbContext.Database.CanConnectAsync()`.
   - Returns `200 OK` (`"Healthy"`) if database queries can be executed.
   - Returns `503 Service Unavailable` (`"Unhealthy"`) if the database is unreachable or migrations are pending.

#### Suggested Health Check Registration (ASP.NET Core):
```csharp
// Proposed registration in Program.cs
builder.Services.AddHealthChecks()
    .AddNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")!);

app.MapHealthChecks("/healthz/live", new HealthCheckOptions { Predicate = _ => false });
app.MapHealthChecks("/healthz/ready", new HealthCheckOptions { Predicate = check => true });
```

---

## 5. Database Migrations, Upgrades, and Seed Strategy

### 5.1 Existing Migration Lineage
The repository contains the following sequential Entity Framework Core migrations in `backend/Church.Infrastructure/Migrations`:
1. `20261031115204_InitialCreate`: Creates `Tenants` table.
2. `20261031130521_AddAnnouncements`: Creates `Announcements` table with indexes on `church_id` and `published_at`.
3. `20261031144505_AddPrayerRequests`: Creates `PrayerRequests` table with indexes on `church_id` and `member_id`.
4. `20261031165556_AddWorshipAndSetlists`: Creates `Songs`, `Setlists`, and `SetlistItems` tables with relational foreign keys.

### 5.2 Fresh Database Provisioning
To initialize a clean PostgreSQL database for pilot operations:

```bash
# Ensure dotnet-ef tool is installed
dotnet tool install --global dotnet-ef || true
export PATH="$PATH:$HOME/.dotnet/tools"

# Apply all migrations directly against the target database
dotnet ef database update \
  --project backend/Church.Infrastructure \
  --startup-project backend/Church.API \
  --connection "$ConnectionStrings__DefaultConnection"
```

### 5.3 Deterministic Migration Script Generation (Recommended for Production)
Rather than executing EF Core tooling directly in production, generate an idempotent SQL script during CI/CD:

```bash
# Generate idempotent SQL script for all migrations
dotnet ef migrations script \
  --idempotent \
  --project backend/Church.Infrastructure \
  --startup-project backend/Church.API \
  --output ./migrations-bundle.sql
```
Apply the generated `migrations-bundle.sql` via `psql` using a privileged database migration user before routing traffic to the updated API.

### 5.4 Initial Tenant Seeding *(Proposed / Unverified)*
Prior to onboarding pilot members, a seed record must exist in the `Tenants` table:
```sql
-- Example template: replace placeholder UUID and names prior to execution
INSERT INTO "Tenants" ("Id", "Name", "Slug", "ContactEmail", "LogoUrl", "Status", "CreatedAt")
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Pilot Grace Fellowship',
    'grace-pilot',
    'admin@grace-pilot.local',
    '',
    'Active',
    CURRENT_TIMESTAMP
) ON CONFLICT ("Id") DO NOTHING;
```

---

## 6. Backup, Verification Restore, and Disaster Recovery

> **Verification Notice**:
> The backup and restore commands below represent **proposed operational procedures**. No live database backup or restore has been performed in this repository environment.

### 6.1 Logical Backup Procedure
Automated backups should execute at least once daily (or before any schema migration), capturing a consistent snapshot using PostgreSQL custom archive format:

```bash
# Export schema and data in compressed custom archive format
pg_dump \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --username="$DB_USER" \
  --format=custom \
  --blobs \
  --verbose \
  --file="backup_church_$(date +%Y%m%d_%H%M%S).dump" \
  "$DB_NAME"
```

### 6.2 Restore Verification to an Isolated Test Database
A backup is not considered valid until successfully restored and validated against a distinct verification database:

```bash
# 1. Create a temporary, isolated verification database
createdb --host="$DB_HOST" --username="$DB_USER" "ChurchDigitalPlatform_Verification"

# 2. Restore the archive dump into the verification database
pg_restore \
  --host="$DB_HOST" \
  --username="$DB_USER" \
  --dbname="ChurchDigitalPlatform_Verification" \
  --clean \
  --if-exists \
  --exit-on-error \
  --verbose \
  "backup_church_TIMESTAMP.dump"

# 3. Execute integrity queries to verify table counts and tenant references
psql --host="$DB_HOST" --username="$DB_USER" --dbname="ChurchDigitalPlatform_Verification" -c "
  SELECT count(*) AS tenant_count FROM \"Tenants\";
  SELECT count(*) AS announcement_count FROM \"Announcements\";
  SELECT count(*) AS prayer_count FROM \"PrayerRequests\";
  SELECT count(*) AS song_count FROM \"Songs\";
  SELECT count(*) AS setlist_count FROM \"Setlists\";
"

# 4. Clean up verification database after validation
dropdb --host="$DB_HOST" --username="$DB_USER" "ChurchDigitalPlatform_Verification"
```

### 6.3 Rollback Strategy

In the event of an operational failure, deployment bug, or failed migration:

1. **API Rollback**:
   - Revert the backend application container/binary to the previous stable release tag.
   - Restart the Kestrel service.
2. **Database Migration Rollback**:
   - If a newly applied migration fails or corrupts operations, roll back schema changes to the previous migration using EF Core target migration syntax:
     ```bash
     dotnet ef database update <PreviousMigrationName> \
       --project backend/Church.Infrastructure \
       --startup-project backend/Church.API \
       --connection "$ConnectionStrings__DefaultConnection"
     ```
   - **Emergency State Recovery**: If migration rollback fails or data loss occurred, restore the pre-deployment database dump (`backup_church_pre_migration.dump`) into the active database after terminating existing client connections.

---

## 7. Outstanding Architecture & Module Dependencies

Before declaring the platform ready for an end-user pilot deployment, the following core dependencies must be finalized:

1. **Module 9: Identity & Sign-In (Issue #18)**:
   - *Status*: Architectural contract established (`docs/architecture/mvp-identity-and-member-contract.md`). Implementation pending.
   - *Requirement*: Replacement of prototype `CustomAuthHandler` with real OIDC/JWT bearer validation and secure session persistence in mobile.
2. **Module 6: Fellowship Ministry Spaces (PR #22)**:
   - *Status*: Active in PR #22.
   - *Requirement*: Group spaces (Men's Fellowship, Sunday School, House Prayer) with private membership enforcement and assigned leader edit rights.
3. **Module 7: Member Profile & Family Directory (Issue #9)**:
   - *Status*: Architecture contract completed. Implementation pending.
   - *Requirement*: Persistence for congregant profiles and privacy redaction rules.
4. **Log Redaction & Privacy Guardrails**:
   - ASP.NET Core and EF Core logging must suppress SQL parameter values to ensure confidential pastoral prayers and member phone numbers/emails are never written to disk or centralized log collectors.

---

## 8. Pilot Smoke Testing Checklist

This smoke testing checklist must be executed by operations or QA personnel immediately following any deployment to a pilot environment.

### 8.1 Authentication & Session Expiry
- [ ] **Sign-In Flow**: Member submits valid credentials (or OIDC token) and receives valid session tokens.
- [ ] **Unauthenticated Access**: Requests lacking `Authorization: Bearer <token>` to protected endpoints (`/api/v1/announcements`, `/api/v1/prayer-requests`, `/api/v1/worship/songs`) return HTTP `401 Unauthorized`.
- [ ] **Expired Token**: Using a token past its `exp` claim returns HTTP `401 Unauthorized` without crashing the API or mobile client.
- [ ] **Client Storage**: Tokens are stored exclusively in platform-secure storage (Keychain/Keystore) and cleared immediately upon sign-out.

### 8.2 Tenant Isolation Integrity
- [ ] **Data Scoping**: When User from Tenant A queries `/api/v1/announcements` or `/api/v1/worship/songs`, zero records belonging to Tenant B are returned.
- [ ] **Direct Access Protection**: Attempting to GET `/api/v1/worship/songs/{id}` where `{id}` belongs to Tenant B returns HTTP `404 Not Found` (never 200).
- [ ] **Mutation Protection**: Attempting to create a setlist in Tenant A referencing a song from Tenant B returns HTTP `400 Bad Request`.
- [ ] **Spoofed Header Rejection**: Passing an arbitrary `X-Tenant-Id` header while authenticated as Tenant A has no effect on query results or created entity `TenantId` values.

### 8.3 Church Announcements Roles & Notices
- [ ] **Member Read Access**: User with `Member` role can fetch `/api/v1/announcements` and receives announcements ordered reverse-chronologically with priority indicators (`Routine`, `Urgent`, `Emergency`).
- [ ] **Member Publish Restriction**: User with `Member` role attempting `POST /api/v1/announcements` receives HTTP `403 Forbidden`.
- [ ] **Leader Publishing**: User with `Admin` or `Pastor` role can create an announcement (`201 Created`), and the announcement appears in the feed.

### 8.4 Confidential Pastoral Prayer Privacy
- [ ] **Member Submission**: Authenticated Member can submit a prayer request via `POST /api/v1/prayer-requests`.
- [ ] **Member Own Requests**: Member can fetch `/api/v1/prayer-requests/my` and see only their own submitted requests.
- [ ] **Confidentiality / Privacy Check**:
  - Request to `GET /api/v1/prayer-requests` (all requests) by a standard `Member` returns HTTP `403 Forbidden`.
  - Request to `GET /api/v1/prayer-requests` by an `Admin` returns HTTP `403 Forbidden` (strictly reserved for `Pastor`).
- [ ] **Pastor Status Update**: User with `Pastor` role can view all tenant prayer requests and update status via `PATCH /api/v1/prayer-requests/{id}/status` to `Praying` or `Answered`.
- [ ] **Log & Output Hygiene**: Confirm that application logs, monitoring tools, and error responses contain zero prayer request text or personal identifiers.

### 8.5 Persisted Worship & Setlists
- [ ] **Library Browsing**: Any authenticated tenant member can browse `/api/v1/worship/songs` and view lyrics, chords, and keys.
- [ ] **Song Management**: `WorshipLeader`, `Pastor`, or `Admin` can create, update, and delete songs.
- [ ] **Setlist Composition**: `WorshipLeader`, `Pastor`, or `Admin` can create a Sunday setlist with ordered songs and key overrides (`201 Created`).
- [ ] **Member Setlist View**: Members can retrieve `/api/v1/worship/setlists` and view upcoming service orders without mutation access.

### 8.6 Private Fellowship Ministry Spaces (PR #22 Integration)
- [ ] **Private Group Visibility**: Non-members of private fellowship groups cannot access member rosters or internal group discussions.
- [ ] **Leader Edits**: Assigned ministry space leaders (and church pastors/admins) can update group details, schedules, and membership approvals.
- [ ] **Cross-Group Isolation**: Membership in one fellowship group grants no permissions in unrelated private groups.
