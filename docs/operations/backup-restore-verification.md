# PostgreSQL Backup and Restore Verification Rehearsal

> **Context & Disclaimer**:
> This document records the operational rehearsal and verification tooling developed under **MVP Task: Verify PostgreSQL backup and restore with disposable CI** (Child of pilot operations #19 under MVP tracker #21).
> **Important**: This procedure is an operator-run backup and restore verification rehearsal executed exclusively against disposable PostgreSQL databases. It is **not** a live pilot deployment, does not touch production environments or live credentials, and does **not** claim complete disaster recovery acceptance for future production operations. Live disaster recovery, backup encryption key management, offsite replication, and retention scheduling remain explicit future operator responsibilities.

---

## 1. Tested Baseline & Tooling Versions

The rehearsal tooling and automated disposable CI verification were validated against the following repository state and runtime environment:

- **Baseline Commit**: `311752f906622a098fcdefaa8e73c8b49c94c05b` (`main`)
- **Database Engine**: PostgreSQL 16 (specifically PostgreSQL 16.15 / client v16+)
- **.NET SDK**: .NET 10.0 (`10.0.103`)
- **EF Core CLI**: `dotnet-ef` version `10.0.14`
- **Python**: 3.12+
- **Baseline EF Core Migrations Tested**:
  1. `20261031115204_InitialCreate` (`Tenants`)
  2. `20261031130521_AddAnnouncements` (`Announcements`)
  3. `20261031144505_AddPrayerRequests` (`PrayerRequests`)
  4. `20261031165556_AddWorshipAndSetlists` (`Songs`, `Setlists`, `SetlistItem`)
  5. `20261031172108_AddFellowshipMinistrySpaces` (`FellowshipGroups`, `FellowshipMembers`, `FellowshipPosts`)

---

## 2. Operational Safeguards & Invariants

To avoid data loss, cross-tenant leaks, or production outages, `scripts/operations/backup_restore.py` enforces the following guardrails:

1. **Standard `libpq` Environment Configuration**:
   - Connection parameters must be supplied via standard PostgreSQL environment variables (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`, or `PGSERVICE`).
   - Secrets are **never** passed as command-line arguments and are **never** logged to stdout/stderr.
2. **Explicit Target Requirement**:
   - No implicit or default database targets are permitted. The operator must specify exact database names.
3. **Collision Refusal**:
   - The tool strictly rejects operations where `--source-db` equals `--target-db`.
4. **Refusal of Populated Target Databases**:
   - The tool refuses to restore into an existing database that already contains user tables or sequences (`information_schema.tables`).
   - Overwrite flags like `--clean`, `DROP DATABASE`, or destructive script cascades are **forbidden**. Operators must create a clean, dedicated disposable database for each verification or restore drill.
5. **No Production Database Overwrites**:
   - Restore automation is strictly designed for isolated disposable target verification.
6. **Suppression of Sensitive Diagnostics & Privacy Protection**:
   - Error messages suppress detailed query payloads and parameters to prevent leaking member identities, prayer request contents, or credentials.
   - Database dumps and backup archives are **never** uploaded as CI artifacts.

---

## 3. Operator Execution Guide (Disposable Rehearsal)

### 3.1 Prerequisites
Ensure `psql`, `pg_dump`, and `pg_restore` are present on `PATH`. Configure standard `libpq` environment variables:

```bash
export PGHOST="localhost"
export PGPORT="5432"
export PGUSER="pilot_test"
export PGPASSWORD="disposable_ci_only"
export PGMAINTENANCEDATABASE="postgres"
```

### 3.2 Automated Rehearsal Pipeline
The `rehearse` command automates taking a snapshot of the source, performing a backup, restoring to a distinct fresh database, verifying integrity, and confirming the source database was not modified:

```bash
# 1. Create a fresh disposable target database
psql -d postgres -c 'CREATE DATABASE "test_target_disposable";'

# 2. Execute the end-to-end rehearsal command
python3 scripts/operations/backup_restore.py rehearse \
  --source-db "test_source_disposable" \
  --target-db "test_target_disposable" \
  --backup-file "/tmp/disposable_rehearsal.dump"

# 3. Clean up disposable databases and local temporary files
psql -d postgres -c 'DROP DATABASE "test_target_disposable";'
rm -f /tmp/disposable_rehearsal.dump
```

### 3.3 Discrete Commands
Operators can also run the stages independently:

- **Backup**:
  ```bash
  python3 scripts/operations/backup_restore.py backup \
    --source-db "test_source_disposable" \
    --backup-file "/tmp/backup.dump"
  ```

- **Restore to Empty Target**:
  ```bash
  python3 scripts/operations/backup_restore.py restore \
    --backup-file "/tmp/backup.dump" \
    --target-db "test_target_disposable" \
    --source-db "test_source_disposable"
  ```

- **Verify Database Parity**:
  ```bash
  python3 scripts/operations/backup_restore.py verify \
    --source-db "test_source_disposable" \
    --target-db "test_target_disposable"
  ```

---

## 4. Verification Criteria

The verification step verifies the following parity checks:
1. **EF Migration Lineage**:
   - Confirms `__EFMigrationsHistory` rows and order match between source and restored database.
2. **Table Record Counts**:
   - Compares counts across all core tables: `Tenants`, `Announcements`, `PrayerRequests`, `Songs`, `Setlists`, `SetlistItem`, `FellowshipGroups`, `FellowshipMembers`, `FellowshipPosts`.
3. **Primary & Foreign Key Relationships**:
   - Ensures parent-child integrity (e.g. Setlists to SetlistItems, FellowshipGroups to FellowshipMembers).
4. **Unicode & Special Character Fidelity**:
   - Ensures multi-lingual characters (Tamil, German, etc.) and emojis survive serialization and restoration intact.
5. **Source Database Immutability**:
   - Ensures source database state before and after the rehearsal remains identical.

---

## 5. Recovery Limitations & Future Operator Decisions

This rehearsal validates the logical backup format (`pg_dump -Fc`) and transactional restore against repository EF migrations. However, operators must account for the following production operational decisions:

1. **Logical Backup vs. Point-in-Time Recovery (PITR)**:
   - Logical backups (`pg_dump`) provide a point-in-time snapshot but do not enable arbitrary rollbacks to specific minutes or seconds. Production deployments will require WAL (Write-Ahead Logging) archiving (e.g., via `pgBackRest` or managed cloud WAL archiving) for true PITR.
2. **Encryption at Rest & in Flight**:
   - Rehearsal archives are created unencrypted locally. Production backup routines must incorporate envelope encryption (e.g., GPG or cloud KMS) before moving archives to secondary or offsite object storage.
3. **Backup Retention & Scheduling**:
   - Automated cron or pipeline schedules, retention lifecycle rules (e.g., 7 daily, 4 weekly, 12 monthly), and geo-redundant storage remain operational tasks to be configured during production infrastructure rollout.
4. **Live Recovery Runbooks**:
   - Disaster recovery onto live infrastructure requires dedicated connection draining, DNS repointing, and identity provider session handling that cannot be tested in disposable CI alone.
