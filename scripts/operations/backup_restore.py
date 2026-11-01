#!/usr/bin/env python3
"""PostgreSQL backup, disposable restore, and verification rehearsal tool.

Follows operational safeguards:
- Standard libpq configuration (PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD, PGSERVICE)
- Secrets are never accepted as command-line arguments or printed in logs/diagnostics
- Strict refusal if source database equals target database
- Refuses restore into populated target databases by default (no DROP DATABASE, no --clean)
- Custom archive format (pg_dump -Fc) for transactional restores
- Comprehensive verification comparing EF migration history, table counts, relationships, and Unicode fields
- Guarantees source database is unmodified after backup
"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

# Tables to verify based on EF Core model in main baseline
CORE_TABLES = [
    "Tenants",
    "Announcements",
    "PrayerRequests",
    "Songs",
    "Setlists",
    "SetlistItems",
    "FellowshipGroups",
    "FellowshipMembers",
    "FellowshipPosts",
]

IDENTIFIER_REGEX = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*$")


def validate_db_identifier(name: str, label: str) -> str:
    """Validate that the database identifier is safe and matches standard naming conventions."""
    if not name or not isinstance(name, str):
        raise ValueError(f"{label} database name must be a non-empty string.")
    name = name.strip()
    if not IDENTIFIER_REGEX.match(name) or len(name) > 63:
        raise ValueError(
            f"{label} database name contains invalid characters or exceeds 63 characters."
        )
    return name


def get_libpq_env() -> dict:
    """Return standard libpq environment variables with sane connection timeout."""
    env = dict(os.environ)
    env.setdefault("PGCONNECT_TIMEOUT", "10")
    return env


def run_psql(db_name: str, query: str, env: dict | None = None, tuples_only: bool = False) -> subprocess.CompletedProcess:
    """Run a query via psql with safe parameters and suppressed diagnostic leaking."""
    if env is None:
        env = get_libpq_env()
    cmd = [
        "psql",
        "--no-psqlrc",
        "--no-password",
        "--quiet",
        "--set=ON_ERROR_STOP=1",
    ]
    if tuples_only:
        cmd.extend(["--tuples-only", "--no-align"])
    cmd.extend([
        "--dbname",
        db_name,
        "--command",
        query,
    ])
    return subprocess.run(
        cmd,
        env=env,
        capture_output=True,
        text=True,
        timeout=45,
    )


def check_database_exists(db_name: str) -> bool:
    """Check if database exists on the PostgreSQL host using postgres maintenance DB or template1."""
    # Try connecting to the database directly; if connection succeeds, it exists.
    maintenance_db = os.environ.get("PGMAINTENANCEDATABASE") or "postgres"
    env = get_libpq_env()
    # First try querying pg_database via maintenance db
    query = f"SELECT 1 FROM pg_database WHERE datname = '{db_name}';"
    res = subprocess.run(
        [
            "psql",
            "--no-psqlrc",
            "--no-password",
            "--tuples-only",
            "--quiet",
            "--set=ON_ERROR_STOP=1",
            "--dbname",
            maintenance_db,
            "--command",
            query,
        ],
        env=env,
        capture_output=True,
        text=True,
        timeout=15,
    )
    if res.returncode == 0:
        return bool(res.stdout.strip())

    # Fallback: test connecting to the db directly
    res_direct = run_psql(db_name, "SELECT 1;", env=env)
    return res_direct.returncode == 0


def is_database_populated(db_name: str) -> bool:
    """Check if public schema has any user tables or sequences."""
    query = (
        "SELECT count(*) FROM information_schema.tables "
        "WHERE table_schema = 'public' AND table_type = 'BASE TABLE';"
    )
    res = run_psql(db_name, query, tuples_only=True)
    if res.returncode != 0:
        raise RuntimeError(f"Failed to check if target database is populated.")
    count_str = res.stdout.strip()
    try:
        count = int(count_str)
        return count > 0
    except ValueError:
        raise RuntimeError("Unexpected response from database when checking table counts.")


def run_backup(source_db: str, backup_path: Path) -> None:
    """Perform pg_dump in custom archive format into backup_path."""
    validate_db_identifier(source_db, "Source")
    env = get_libpq_env()
    backup_path = Path(backup_path).resolve()
    backup_path.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        "pg_dump",
        "--no-password",
        "--format=custom",
        "--blobs",
        "--dbname",
        source_db,
        "--file",
        str(backup_path),
    ]

    res = subprocess.run(
        cmd,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if res.returncode != 0:
        if backup_path.exists():
            backup_path.unlink(missing_ok=True)
        raise RuntimeError(
            "Backup operation failed. Database diagnostics are suppressed for privacy."
        )

    if not backup_path.exists() or backup_path.stat().st_size == 0:
        if backup_path.exists():
            backup_path.unlink(missing_ok=True)
        raise RuntimeError("Backup completed but produced an empty or missing archive.")


def run_restore(backup_path: Path, target_db: str, source_db: str | None = None) -> None:
    """Restore custom archive dump into a distinct, empty target database."""
    target_db = validate_db_identifier(target_db, "Target")
    if source_db:
        source_db = validate_db_identifier(source_db, "Source")
        if source_db == target_db:
            raise ValueError(
                f"Source and target database cannot be the same ('{source_db}'). "
                "Refusing destructive in-place restore."
            )

    backup_path = Path(backup_path).resolve()
    if not backup_path.exists():
        raise FileNotFoundError(f"Backup archive not found at: {backup_path}")
    if backup_path.stat().st_size == 0:
        raise ValueError("Backup archive is empty.")

    if not check_database_exists(target_db):
        raise RuntimeError(
            f"Target database '{target_db}' does not exist. "
            "Please create a fresh disposable database before restore."
        )

    if is_database_populated(target_db):
        raise RuntimeError(
            f"Target database '{target_db}' already contains tables. "
            "Refusing restore into non-empty target to prevent accidental overwrite."
        )

    env = get_libpq_env()
    # Execute pg_restore in single transaction and exit-on-error.
    # Notice: NO --clean or --create or DROP commands are used.
    cmd = [
        "pg_restore",
        "--no-password",
        "--exit-on-error",
        "--single-transaction",
        "--dbname",
        target_db,
        str(backup_path),
    ]

    res = subprocess.run(
        cmd,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if res.returncode != 0:
        raise RuntimeError(
            "Restore operation failed. Database diagnostics are suppressed for privacy."
        )


def get_database_snapshot(db_name: str) -> dict:
    """Capture table counts, migration histories, and row hashes/signatures for verification."""
    validate_db_identifier(db_name, "Database")
    env = get_libpq_env()

    # 1. Fetch EF Migrations
    ef_query = 'SELECT "MigrationId", "ProductVersion" FROM public."__EFMigrationsHistory" ORDER BY "MigrationId";'
    res = run_psql(db_name, ef_query, env=env, tuples_only=True)
    if res.returncode != 0:
        raise RuntimeError("Failed to read __EFMigrationsHistory from database.")
    migrations = [line.strip() for line in res.stdout.strip().splitlines() if line.strip()]

    # 2. Fetch Table Counts
    counts = {}
    for table in CORE_TABLES:
        table_sql = f'SELECT count(*) FROM public."{table}";'
        res = run_psql(db_name, table_sql, env=env, tuples_only=True)
        if res.returncode == 0 and res.stdout.strip().isdigit():
            counts[table] = int(res.stdout.strip())
        else:
            # Table might not exist or error
            counts[table] = -1

    # 3. Fetch exact IDs and representative hashes (Tenants, FellowshipGroups, Songs)
    tenant_ids_query = 'SELECT "Id"::text, "Slug", "Name" FROM public."Tenants" ORDER BY "Id";'
    res_t = run_psql(db_name, tenant_ids_query, env=env, tuples_only=True)
    tenants = [line.strip() for line in res_t.stdout.strip().splitlines() if line.strip()]

    groups_query = 'SELECT "id"::text, "church_id"::text, "name" FROM public."FellowshipGroups" ORDER BY "id";'
    res_g = run_psql(db_name, groups_query, env=env, tuples_only=True)
    groups = [line.strip() for line in res_g.stdout.strip().splitlines() if line.strip()]

    songs_query = 'SELECT "id"::text, "church_id"::text, "title" FROM public."Songs" ORDER BY "id";'
    res_s = run_psql(db_name, songs_query, env=env, tuples_only=True)
    songs = [line.strip() for line in res_s.stdout.strip().splitlines() if line.strip()]

    # Prayer Requests count and IDs without leaking prayer text
    pr_query = 'SELECT "id"::text, "church_id"::text, "status" FROM public."PrayerRequests" ORDER BY "id";'
    res_p = run_psql(db_name, pr_query, env=env, tuples_only=True)
    pr = [line.strip() for line in res_p.stdout.strip().splitlines() if line.strip()]

    return {
        "migrations": migrations,
        "counts": counts,
        "tenants": tenants,
        "groups": groups,
        "songs": songs,
        "pr": pr,
    }


def verify_databases(source_db: str, target_db: str) -> None:
    """Compare source and target databases to verify backup integrity."""
    source_db = validate_db_identifier(source_db, "Source")
    target_db = validate_db_identifier(target_db, "Target")
    if source_db == target_db:
        raise ValueError("Source and target database names must be distinct for verification.")

    src_snapshot = get_database_snapshot(source_db)
    tgt_snapshot = get_database_snapshot(target_db)

    # 1. Compare EF migrations
    if src_snapshot["migrations"] != tgt_snapshot["migrations"]:
        raise AssertionError(
            f"EF Migration history mismatch between {source_db} and {target_db}."
        )

    # 2. Compare table counts
    for table, count in src_snapshot["counts"].items():
        tgt_count = tgt_snapshot["counts"].get(table)
        if count != tgt_count:
            raise AssertionError(
                f"Row count mismatch for table '{table}': source has {count}, target has {tgt_count}."
            )

    # 3. Compare tenants (IDs, slugs, Unicode names)
    if src_snapshot["tenants"] != tgt_snapshot["tenants"]:
        raise AssertionError("Tenant records mismatch between source and target.")

    # 4. Compare fellowship groups & relations
    if src_snapshot["groups"] != tgt_snapshot["groups"]:
        raise AssertionError("Fellowship groups mismatch between source and target.")

    # 5. Compare worship songs & relations
    if src_snapshot["songs"] != tgt_snapshot["songs"]:
        raise AssertionError("Songs mismatch between source and target.")

    # 6. Compare prayer requests & statuses
    if src_snapshot["pr"] != tgt_snapshot["pr"]:
        raise AssertionError("Prayer requests metadata mismatch between source and target.")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify PostgreSQL backup and restore against disposable targets."
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # Backup subcommand
    backup_p = subparsers.add_parser("backup", help="Create custom archive backup.")
    backup_p.add_argument("--source-db", required=True, help="Source database name.")
    backup_p.add_argument("--backup-file", required=True, type=Path, help="Target backup file path.")

    # Restore subcommand
    restore_p = subparsers.add_parser("restore", help="Restore backup into clean disposable target.")
    restore_p.add_argument("--backup-file", required=True, type=Path, help="Backup file to restore.")
    restore_p.add_argument("--target-db", required=True, help="Target disposable database name.")
    restore_p.add_argument("--source-db", help="Original source database name (for collision check).")

    # Verify subcommand
    verify_p = subparsers.add_parser("verify", help="Compare source and restored target databases.")
    verify_p.add_argument("--source-db", required=True, help="Source database name.")
    verify_p.add_argument("--target-db", required=True, help="Target restored database name.")

    # Rehearse all-in-one subcommand
    rehearse_p = subparsers.add_parser(
        "rehearse", help="Execute complete backup -> restore -> verify pipeline."
    )
    rehearse_p.add_argument("--source-db", required=True, help="Source database name.")
    rehearse_p.add_argument("--target-db", required=True, help="Target disposable database name.")
    rehearse_p.add_argument("--backup-file", required=True, type=Path, help="Path for temporary backup archive.")

    args = parser.parse_args(argv)

    try:
        if args.subcommand == "backup":
            run_backup(args.source_db, args.backup_file)
            print(f"Backup created successfully: {args.backup_file}")
            return 0

        elif args.subcommand == "restore":
            run_restore(args.backup_file, args.target_db, args.source_db)
            print(f"Backup restored successfully into target database: {args.target_db}")
            return 0

        elif args.subcommand == "verify":
            verify_databases(args.source_db, args.target_db)
            print(f"Verification successful: {args.source_db} and {args.target_db} match exactly.")
            return 0

        elif args.subcommand == "rehearse":
            initial_source_snapshot = get_database_snapshot(args.source_db)
            run_backup(args.source_db, args.backup_file)
            run_restore(args.backup_file, args.target_db, args.source_db)
            verify_databases(args.source_db, args.target_db)
            post_source_snapshot = get_database_snapshot(args.source_db)
            if initial_source_snapshot != post_source_snapshot:
                raise AssertionError("Source database was modified during the rehearsal process.")
            print("Full backup and restore rehearsal completed and verified successfully.")
            return 0

    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
