#!/usr/bin/env python3
"""PostgreSQL backup, disposable restore, and verification rehearsal tool.

Follows operational safeguards:
- Standard libpq configuration (PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD, PGSERVICE)
- Secrets are never accepted as command-line arguments or printed in logs/diagnostics
- Strict refusal if source database equals target database
- Refuses restore into populated target databases by default (no DROP DATABASE, no --clean)
- Atomic backup staging so failed backups never delete or corrupt pre-existing archives
- Custom archive format (pg_dump -Fc) for transactional restores
- Comprehensive verification comparing EF migration history, table counts, and deterministic
  full-row cryptographic digests (covering content, Unicode, privacy flags, and FK columns)
- Guarantees source database is unmodified after backup
"""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

# Core tables and their primary key columns based on EF Core model in main baseline
TABLE_PRIMARY_KEYS = {
    "Tenants": "Id",
    "Announcements": "id",
    "PrayerRequests": "id",
    "Songs": "id",
    "Setlists": "id",
    "SetlistItems": "id",
    "FellowshipGroups": "id",
    "FellowshipMembers": "id",
    "FellowshipPosts": "id",
}

CORE_TABLES = list(TABLE_PRIMARY_KEYS.keys())

IDENTIFIER_REGEX = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*$")
ROW_SIGNATURE_REGEX = re.compile(r"^[^:]+:[0-9a-f]{32}$")


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


def run_psql(
    db_name: str, query: str, env: dict | None = None, tuples_only: bool = False
) -> subprocess.CompletedProcess:
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
    """Check if database exists on the PostgreSQL host using postgres maintenance DB or direct connect."""
    maintenance_db = os.environ.get("PGMAINTENANCEDATABASE") or "postgres"
    env = get_libpq_env()
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

    res_direct = run_psql(db_name, "SELECT 1;", env=env)
    return res_direct.returncode == 0


def is_database_populated(db_name: str) -> bool:
    """Check if non-system schemas have any user tables, views, or sequences."""
    query = (
        "SELECT ("
        "(SELECT count(*) FROM information_schema.tables "
        "WHERE table_schema NOT IN ('pg_catalog', 'information_schema') "
        "AND table_schema NOT LIKE 'pg_toast%') + "
        "(SELECT count(*) FROM information_schema.sequences "
        "WHERE sequence_schema NOT IN ('pg_catalog', 'information_schema') "
        "AND sequence_schema NOT LIKE 'pg_toast%')"
        ");"
    )
    res = run_psql(db_name, query, tuples_only=True)
    if res.returncode != 0:
        raise RuntimeError("Failed to check if target database is populated.")
    count_str = res.stdout.strip()
    if not count_str.isdigit():
        raise RuntimeError("Unexpected response from database when checking table counts.")
    return int(count_str) > 0


def run_backup(source_db: str, backup_path: Path) -> None:
    """Perform pg_dump in custom archive format using atomic staging file replacement."""
    validate_db_identifier(source_db, "Source")
    env = get_libpq_env()
    backup_path = Path(backup_path).resolve()
    backup_path.parent.mkdir(parents=True, exist_ok=True)

    fd, temp_str = tempfile.mkstemp(
        prefix=f".{backup_path.name}.",
        suffix=".tmp",
        dir=str(backup_path.parent),
    )
    os.close(fd)
    temp_path = Path(temp_str)

    try:
        cmd = [
            "pg_dump",
            "--no-password",
            "--format=custom",
            "--blobs",
            "--dbname",
            source_db,
            "--file",
            str(temp_path),
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
                "Backup operation failed. Database diagnostics are suppressed for privacy."
            )

        if not temp_path.exists() or temp_path.stat().st_size == 0:
            raise RuntimeError("Backup completed but produced an empty or missing archive.")

        os.replace(temp_path, backup_path)
    finally:
        if temp_path.exists():
            temp_path.unlink(missing_ok=True)


def run_restore(backup_path: Path, target_db: str, source_db: str | None = None) -> None:
    """Restore custom archive dump into a distinct, empty target database."""
    target_db = validate_db_identifier(target_db, "Target")
    effective_source_db = source_db if source_db is not None else os.environ.get("PGDATABASE")
    if effective_source_db:
        effective_source_db = validate_db_identifier(effective_source_db, "Source")
        if effective_source_db == target_db:
            raise ValueError(
                f"Source and target database cannot be the same ('{effective_source_db}'). "
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
            f"Target database '{target_db}' already contains tables or sequences. "
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
    """Capture migration history, table counts, and deterministic full-row digests."""
    validate_db_identifier(db_name, "Database")
    env = get_libpq_env()

    # 1. Fetch EF Migrations
    ef_query = (
        'SELECT "MigrationId" || \':\' || "ProductVersion" '
        'FROM public."__EFMigrationsHistory" ORDER BY "MigrationId";'
    )
    res = run_psql(db_name, ef_query, env=env, tuples_only=True)
    if res.returncode != 0:
        raise RuntimeError("Failed to read __EFMigrationsHistory from database.")
    migrations = [line.strip() for line in res.stdout.strip().splitlines() if line.strip()]
    if not migrations:
        raise RuntimeError("No EF Core migrations found in __EFMigrationsHistory.")

    # 2. Fetch Table Counts and Deterministic Full-Row Signatures
    counts = {}
    row_signatures = {}
    for table in CORE_TABLES:
        table_sql = f'SELECT count(*) FROM public."{table}";'
        res_count = run_psql(db_name, table_sql, env=env, tuples_only=True)
        if res_count.returncode != 0:
            raise RuntimeError(
                f"Failed to query row count for table '{table}'. Database diagnostics are suppressed."
            )
        count_str = res_count.stdout.strip()
        if not count_str.isdigit():
            raise RuntimeError(f"Malformed row count response for table '{table}'.")
        counts[table] = int(count_str)

        pk_col = TABLE_PRIMARY_KEYS[table]
        sig_sql = (
            f'SELECT t."{pk_col}"::text || \':\' || md5(row_to_json(t)::text) '
            f'FROM public."{table}" AS t ORDER BY t."{pk_col}"::text;'
        )
        res_sig = run_psql(db_name, sig_sql, env=env, tuples_only=True)
        if res_sig.returncode != 0:
            raise RuntimeError(
                f"Failed to query row signatures for table '{table}'. Database diagnostics are suppressed."
            )
        sigs = [line.strip() for line in res_sig.stdout.strip().splitlines() if line.strip()]
        if len(sigs) != counts[table] or any(not ROW_SIGNATURE_REGEX.match(s) for s in sigs):
            raise RuntimeError(
                f"Malformed or inconsistent row signature response for table '{table}'."
            )
        row_signatures[table] = sigs

    return {
        "migrations": migrations,
        "counts": counts,
        "row_signatures": row_signatures,
    }


def verify_databases(source_db: str, target_db: str) -> None:
    """Compare source and target databases to verify backup and restore integrity."""
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
    for table in CORE_TABLES:
        src_count = src_snapshot["counts"].get(table)
        tgt_count = tgt_snapshot["counts"].get(table)
        if src_count != tgt_count:
            raise AssertionError(
                f"Row count mismatch for table '{table}': source has {src_count}, target has {tgt_count}."
            )

    # 3. Compare deterministic full-row signatures (all columns, Unicode fields, and FK relations)
    for table in CORE_TABLES:
        if src_snapshot["row_signatures"].get(table) != tgt_snapshot["row_signatures"].get(table):
            raise AssertionError(
                f"Row content or relationship signature mismatch for table '{table}' "
                f"between {source_db} and {target_db}."
            )


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
