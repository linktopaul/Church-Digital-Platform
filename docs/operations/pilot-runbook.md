# Portable Pilot Operations, Recovery, and Smoke Runbook

> **Operational Status**:
> Delivered under **Pilot Operations PBI #10 / Issue #19** (MVP tracker #21).
> All core MVP feature modules (Tenant Provisioning, ASP.NET Core Identity & OpenIddict PKCE, Confidential Prayer, Worship, Fellowships, Member Profiles & Family Directory) are delivered and verified across automated CI test suites. This document details verified containerization via Docker Compose, environment configuration, database migrations, backup/restore procedures, smoke testing, and the Kubernetes scaling roadmap.

---

## 1. System Overview & Architecture Touchpoints

The Church Digital Platform comprises three core tiers designed for multi-tenant church community operations:

1. **Backend Web API (`backend/Church.API`)**:
   - Built on ASP.NET Core (.NET 10.0 / `net10.0`).
   - Entity Framework Core with Npgsql PostgreSQL provider (`backend/Church.Infrastructure`).
   - Tenant isolation enforced via EF Core global query filters implementing `IMultiTenantEntity` against `TenantService.GetCurrentTenantId()`.
   - OpenIddict Authorization Code + PKCE (S256) identity provider with RS256 JWT signing (`backend/Church.API/Endpoints/AuthEndpoints.cs`).
   - Unauthenticated `/health` endpoint for container liveness/readiness probes.
2. **Mobile Client (`mobile/`)**:
   - Built with Flutter (Material 3).
   - Configurable backend base URL via compile-time environment variable `CHURCH_API_BASE_URL`.
   - Shared `AuthenticatedHttpClient` auditing against client header forgery (`x-tenant-id`, `x-user-role`, etc.) and automatically managing Bearer token attachment and 401 refresh retries.
   - Feature modules: Announcements (Home), Confidential Pastoral Prayer, Worship & Sunday Setlists, Fellowships, and Member Profile & Directory.
3. **Continuous Integration & Operations (`.github/workflows/`)**:
   - `.github/workflows/auto-orchestrator.yml`: Runs `.NET 10 unit tests` across all test fixtures.
   - `.github/workflows/flutter-mobile-ci.yml`: Runs `flutter test` across all mobile widget/unit tests.
   - `.github/workflows/db-backup-restore-ci.yml`: Validates backup creation, restore, and table integrity against disposable PostgreSQL 16.
   - `.github/workflows/tenant-provisioning-ci.yml`: Validates real PostgreSQL database migrations, tenant creation, and slug uniqueness.

---

## 2. Verified Local & Pilot Deployment Runtime

| Area | Verified Implementation on `main` | Pilot Deployment Architecture |
|---|---|---|
| **API Runtime** | .NET 10 Web API running on Kestrel (`backend/Church.API`). Verified passing integration tests with in-memory & PostgreSQL DBs. | Multi-stage Docker container (`mcr.microsoft.com/dotnet/aspnet:10.0`) running as non-root user `$APP_UID`, exposed via `docker-compose.yml`. |
| **Database** | PostgreSQL 16 (connection string via `ConnectionStrings__DefaultConnection`). Tested with Npgsql and EF Core migrations. | Containerized PostgreSQL 16 Alpine (`postgres:16-alpine`) with persistent Docker named volume `pgdata` and internal network isolation. |
| **Reverse Proxy** | Direct Kestrel binding in development. | Reverse proxy (Caddy / NGINX) terminating HTTPS with automatic Let's Encrypt certificates. |
| **Auth & OIDC** | OpenIddict PKCE S256 with RS256 token signing. `AllowTestHeaderAuth = false` in production mode. | RSA Private Key supplied via `Authentication__RsaPrivateKeyPem` environment variable. |
| **Health Probes** | `GET /health` endpoint returning HTTP 200 OK and `{ "status": "Healthy" }`. | Container healthcheck polling `http://localhost:8080/health`. |

---

## 3. Configuration & Secrets Management

All production secrets and environment settings are loaded through standard environment variables (12-Factor App design). No secrets or credentials are hard-coded in the repository.

### 3.1 Backend API Environment Variables

| Variable Name | Required | Example / Description |
|---|---|---|
| `ASPNETCORE_ENVIRONMENT` | Yes | `Production` or `Development` |
| `ConnectionStrings__DefaultConnection` | Yes | `Host=db;Port=5432;Database=church_pilot;Username=church_admin;Password=...` |
| `Authentication__Issuer` | Yes | Valid public URL of the API, e.g. `https://pilot.church.example.com` or `http://localhost:8080` |
| `Authentication__Audience` | Yes | Expected JWT audience, standard: `church_api` |
| `Authentication__AllowTestHeaderAuth` | Yes | Set strictly to `"false"` in production/pilot to reject forged headers |
| `Authentication__RsaPrivateKeyPem` | Yes | 2048-bit RSA Private Key in PEM format for RS256 JWT signing |

### 3.2 Mobile Client Build Configuration

| Variable Name | Required | Description |
|---|---|---|
| `CHURCH_API_BASE_URL` | Yes | Base URL where Church API is reachable (e.g. `https://pilot.church.example.com` or `http://10.0.2.2:8080` on Android emulator). |

---

## 4. Single-Church Pilot Launch via Docker Compose

### 4.1 Quickstart

1. **Configure Environment**:
   ```bash
   cp .env.pilot.example .env
   # Edit .env to set secure database passwords and host settings
   ```

2. **Generate RSA Signing Key (if not provided)**:
   ```bash
   openssl genrsa -out private_key.pem 2048
   export RSA_PRIVATE_KEY_PEM=$(cat private_key.pem)
   ```

3. **Start Pilot Stack**:
   ```bash
   docker compose up -d
   ```

4. **Verify Health**:
   ```bash
   curl -i http://localhost:8080/health
   # HTTP/1.1 200 OK
   # {"status":"Healthy","timestamp":"..."}
   ```

5. **Stop Stack**:
   ```bash
   docker compose down
   # Note: Persistent database data remains preserved in the 'pgdata' Docker volume.
   ```

---

## 5. Database Migrations, Upgrades, and Seed Strategy

### 5.1 Existing Migration Lineage
The repository contains the following sequential Entity Framework Core migrations in `backend/Church.Infrastructure/Migrations`:
1. `20261031115204_InitialCreate`: Creates `Tenants` table.
2. `20261031130521_AddAnnouncements`: Creates `Announcements` table with indexes on `church_id` and `published_at`.
3. `20261031144505_AddPrayerRequests`: Creates `PrayerRequests` table with indexes on `church_id` and `member_id`.
4. `20261031165556_AddWorshipAndSetlists`: Creates `Songs`, `Setlists`, and `SetlistItems` tables with relational foreign keys.
5. Subsequent migrations for Fellowships, Member Profiles, Families, and OpenIddict Refresh Tokens.

### 5.2 Deterministic Migration Execution
For production and pilot deployments, apply migrations using an idempotent SQL script generated from EF Core:
```bash
dotnet ef migrations script \
  --idempotent \
  --project backend/Church.Infrastructure \
  --startup-project backend/Church.API \
  --output ./migrations-bundle.sql

# Apply against target PostgreSQL database
psql "$ConnectionStrings__DefaultConnection" -f ./migrations-bundle.sql
```

### 5.3 Pilot Tenant Provisioning
Initialize the first pilot church tenant using the verified provisioning script, passing church JSON on standard input with the database configured via libpq (`PGDATABASE` or `PGSERVICE`):
```bash
export PGDATABASE="${DB_NAME:-church_pilot}"

cat << 'EOF' | python3 scripts/provision_pilot_tenant.py
{
  "name": "Pilot Grace Fellowship",
  "slug": "grace-pilot",
  "contact_email": "admin@grace-pilot.local",
  "logo_url": ""
}
EOF
```

---

## 6. Backup, Restore & Disaster Recovery

Validated by continuous integration workflow `.github/workflows/db-backup-restore-ci.yml`.

### 6.1 Logical Backup Procedure
Execute daily or pre-upgrade logical backups using `pg_dump` with custom archive format:
```bash
pg_dump \
  --host="${DB_HOST:-localhost}" \
  --port="${DB_PORT:-5432}" \
  --username="${DB_USER:-church_admin}" \
  --format=custom \
  --blobs \
  --file="backup_church_$(date +%Y%m%d_%H%M%S).dump" \
  "${DB_NAME:-church_pilot}"
```

### 6.2 Test Database Verification & Restore
Always verify backup validity by test-restoring into an isolated test database and verifying row-signature integrity:
```bash
# Method A: Direct verification comparison between source and restored verification database
createdb -h localhost -U church_admin church_verify_test
pg_restore -h localhost -U church_admin -d church_verify_test backup_church_latest.dump
python3 scripts/operations/backup_restore.py verify --source-db "${DB_NAME:-church_pilot}" --target-db church_verify_test
dropdb -h localhost -U church_admin church_verify_test

# Method B: Automated end-to-end rehearsal pipeline (creates backup, restores into target, verifies integrity, and proves source is untouched)
python3 scripts/operations/backup_restore.py rehearse \
  --source-db "${DB_NAME:-church_pilot}" \
  --target-db church_verify_test \
  --backup-file "backup_rehearsal.dump"
```

---

## 7. Kubernetes Scaling Roadmap (Multi-Church Cloud Scale)

While Docker Compose is ideal for a single-church pilot, the architecture is designed for seamless transition to Kubernetes (AWS EKS, GCP GKE, Azure AKS) when scaling to hundreds of congregations:

1. **Stateless API Deployment**: The container image built by `Dockerfile` scales horizontally behind a Kubernetes `Deployment` with a horizontal pod autoscaler (HPA) targeting CPU/memory.
2. **Managed Database (RDS / Cloud SQL)**: The database tier transitions from a local container to a managed, multi-AZ PostgreSQL instance with automated daily snapshots and read replicas.
3. **Kubernetes Ingress & Cert-Manager**: Cluster Ingress routes traffic based on tenant subdomains (`*.churchplatform.org`) with automatic TLS certificate provisioning via `cert-manager`.
4. **Secrets Management**: Sensitive values (`ConnectionStrings`, `RSA_PRIVATE_KEY_PEM`) map to Kubernetes `Secrets` backed by AWS Secrets Manager or HashiCorp Vault.

---

## 8. Pilot Smoke Testing Checklist

Execute this checklist before inviting real congregation members to the pilot environment:

- [ ] **1. Health & Liveness Probe**:
  - Request `GET /health` returns `200 OK` with `status: "Healthy"`.
- [ ] **2. Identity & PKCE Exchange**:
  - Unregistered / anonymous self-registration returns 404 (Invite-only enforcement).
  - Provisioned member authenticates via PKCE S256 code challenge exchange.
  - `/connect/userinfo` and `/api/v1/auth/me` return validated server claims.
  - Client-supplied `X-Tenant-Id` and `X-User-Role` headers are ignored.
- [ ] **3. Tenant Isolation & Privacy**:
  - Church A member cannot view or access announcements, prayers, or member directories belonging to Church B.
  - Direct ID queries across tenants return 404 Not Found.
- [ ] **4. Confidential Pastoral Prayer**:
  - Member submits confidential prayer; persists in personal feed.
  - Pastor in the same church views request in pastoral feed and updates status to `Praying` and `Answered`.
  - Non-pastor members cannot view pastoral feed or update status (403 Forbidden).
- [ ] **5. Fellowship Spaces & Messages**:
  - Member can view public groups and joined private groups.
  - Non-members cannot view private group post streams.
- [ ] **6. Member Profile & Family Directory**:
  - Member updates own contact and privacy opt-ins (`ShowEmail`, `ShowPhoneNumber`).
  - Directory search respects member privacy preferences and masks unlisted contacts.
- [ ] **7. Session Termination & Sign-Out**:
  - Sign-out invalidates local session and revokes refresh tokens at `/connect/revoke`.
  - Cached confidential data is immediately cleared from UI upon sign out.
- [ ] **8. Automated CI Status**:
  - All automated CI workflows on `main` branch pass green.
