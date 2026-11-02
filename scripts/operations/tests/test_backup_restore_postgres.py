"""Integration tests for PostgreSQL backup and restore against disposable databases."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

SCRIPT = Path(__file__).resolve().parents[1] / "backup_restore.py"
REPO_ROOT = Path(__file__).resolve().parents[3]


def run_psql_cmd(db_name, sql):
    env = dict(os.environ)
    env.setdefault("PGCONNECT_TIMEOUT", "10")
    return subprocess.run(
        [
            "psql",
            "--no-psqlrc",
            "--no-password",
            "--quiet",
            "--set=ON_ERROR_STOP=1",
            "--dbname",
            db_name,
            "--command",
            sql,
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=30,
    )


@unittest.skipUnless(
    os.environ.get("BACKUP_RESTORE_DISPOSABLE_DB_TEST") == "1",
    "Requires BACKUP_RESTORE_DISPOSABLE_DB_TEST=1 and disposable PostgreSQL instance",
)
class DisposablePostgreSQLBackupRestoreTests(unittest.TestCase):
    def setUp(self):
        self.suffix = uuid.uuid4().hex[:8]
        self.source_db = f"test_source_{self.suffix}"
        self.target_db = f"test_target_{self.suffix}"
        self.temp_dir = tempfile.TemporaryDirectory()
        self.backup_path = Path(self.temp_dir.name) / "rehearsal.dump"

        # Create fresh disposable databases
        self._createdb(self.source_db)
        self._createdb(self.target_db)

    def tearDown(self):
        self.temp_dir.cleanup()
        self._dropdb(self.target_db)
        self._dropdb(self.source_db)

    def _createdb(self, name):
        maintenance_db = os.environ.get("PGMAINTENANCEDATABASE") or "postgres"
        run_psql_cmd(maintenance_db, f'CREATE DATABASE "{name}";')

    def _dropdb(self, name):
        maintenance_db = os.environ.get("PGMAINTENANCEDATABASE") or "postgres"
        try:
            # Terminate active connections first
            run_psql_cmd(
                maintenance_db,
                f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{name}';",
            )
            run_psql_cmd(maintenance_db, f'DROP DATABASE IF EXISTS "{name}";')
        except Exception:
            pass

    def _apply_migrations(self, db_name):
        conn_str = os.environ.get(
            "ConnectionStrings__DefaultConnection",
            f"Host={os.environ.get('PGHOST', 'localhost')};Port={os.environ.get('PGPORT', '5432')};Database={db_name};Username={os.environ.get('PGUSER', 'pilot_test')};Password={os.environ.get('PGPASSWORD', 'disposable_ci_only')}",
        )
        # Update Database name in connection string
        # Replace Database=...;
        import re
        conn_str = re.sub(r"Database=[^;]+;", f"Database={db_name};", conn_str)

        res = subprocess.run(
            [
                "dotnet-ef",
                "database",
                "update",
                "--project",
                str(REPO_ROOT / "backend" / "Church.Infrastructure"),
                "--startup-project",
                str(REPO_ROOT / "backend" / "Church.API"),
                "--connection",
                conn_str,
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        self.assertEqual(res.returncode, 0, f"Migration failed: {res.stderr}\n{res.stdout}")

    def _seed_fictional_data(self, db_name):
        tenant1_id = str(uuid.uuid4())
        tenant2_id = str(uuid.uuid4())
        song_id = str(uuid.uuid4())
        setlist_id = str(uuid.uuid4())
        group_id = str(uuid.uuid4())
        member_id = str(uuid.uuid4())
        prayer_id = str(uuid.uuid4())

        # Unicode values: Tamil (தூயவர்), German umlauts (Güte), Emoji (🙏)
        sql = f"""
        INSERT INTO public."Tenants" ("Id", "Name", "Slug", "ContactEmail", "LogoUrl", "Status")
        VALUES
            ('{tenant1_id}', 'Grace Fellowship தேவாலயம்', 'grace-{self.suffix}', 'office@grace.local', 'https://grace.local/logo.png', 'Active'),
            ('{tenant2_id}', 'Köln Hoffnung Kirche', 'koln-{self.suffix}', 'info@koln.local', '', 'Active');

        INSERT INTO public."Announcements" ("id", "church_id", "author_id", "title", "content", "priority", "published_at")
        VALUES
            ('{uuid.uuid4()}', '{tenant1_id}', '{member_id}', 'Sunday Service ஞாயிறு வழிபாடு', 'Welcome all to the service 🙏', 'Routine', NOW());

        INSERT INTO public."Songs" ("id", "church_id", "title", "artist", "default_key", "tempo_bpm", "lyrics", "chords", "created_at")
        VALUES
            ('{song_id}', '{tenant1_id}', 'Amazing Grace / அளவற்ற கிருபை', 'John Newton', 'G', 72, 'Amazing grace how sweet the sound...', '[G] [C] [D]', NOW());

        INSERT INTO public."Setlists" ("id", "church_id", "title", "service_date", "notes", "created_at")
        VALUES
            ('{setlist_id}', '{tenant1_id}', 'Sunday Worship Setlist', NOW(), 'Morning Service', NOW());

        INSERT INTO public."SetlistItems" ("id", "church_id", "setlist_id", "song_id", "order", "key_override", "notes")
        VALUES
            ('{uuid.uuid4()}', '{tenant1_id}', '{setlist_id}', '{song_id}', 1, 'G', 'Opening hymn');

        INSERT INTO public."FellowshipGroups" ("id", "church_id", "name", "description", "group_type", "leader_id", "leader_name", "meeting_schedule", "location", "is_private", "created_at")
        VALUES
            ('{group_id}', '{tenant1_id}', 'Men Fellowship ஆண்கள் ஐக்கியம்', 'Weekly fellowship meeting', 'MensFellowship', '{member_id}', 'Leader Paul', 'Fridays 7 PM', 'Hall 2', false, NOW());

        INSERT INTO public."FellowshipMembers" ("id", "church_id", "fellowship_group_id", "member_id", "member_name", "role", "joined_at")
        VALUES
            ('{uuid.uuid4()}', '{tenant1_id}', '{group_id}', '{member_id}', 'Paul', 'Leader', NOW());

        INSERT INTO public."FellowshipPosts" ("id", "church_id", "fellowship_group_id", "author_id", "author_name", "title", "content", "created_at")
        VALUES
            ('{uuid.uuid4()}', '{tenant1_id}', '{group_id}', '{member_id}', 'Paul', 'Announcement', 'Meeting is confirmed for Friday at 7 PM!', NOW());

        INSERT INTO public."PrayerRequests" ("id", "church_id", "member_id", "content", "status", "created_at")
        VALUES
            ('{prayer_id}', '{tenant1_id}', '{member_id}', 'Pastoral prayer for recovery and healing 🙏', 'Pending', NOW());
        """
        run_psql_cmd(db_name, sql)

    def invoke(self, args):
        return subprocess.run(
            [sys.executable, str(SCRIPT)] + args,
            text=True,
            capture_output=True,
            timeout=60,
        )

    def test_rehearse_and_verify_end_to_end(self):
        # 1. Apply migrations to source database
        self._apply_migrations(self.source_db)

        # 2. Seed representative fictional feature records
        self._seed_fictional_data(self.source_db)

        # 3. Execute rehearse command: backup -> restore -> verify
        res = self.invoke([
            "rehearse",
            "--source-db", self.source_db,
            "--target-db", self.target_db,
            "--backup-file", str(self.backup_path),
        ])
        self.assertEqual(res.returncode, 0, f"Rehearsal failed: {res.stderr}\n{res.stdout}")
        self.assertIn("Full backup and restore rehearsal completed and verified successfully", res.stdout)
        self.assertTrue(self.backup_path.exists())
        self.assertGreater(self.backup_path.stat().st_size, 0)

        # 4. Run explicit verify command
        verify_res = self.invoke([
            "verify",
            "--source-db", self.source_db,
            "--target-db", self.target_db,
        ])
        self.assertEqual(verify_res.returncode, 0)
        self.assertIn("Verification successful", verify_res.stdout)

    def test_restore_into_populated_target_is_rejected(self):
        # Apply migrations to both so target is populated
        self._apply_migrations(self.source_db)
        self._apply_migrations(self.target_db)

        # Create valid backup
        res_backup = self.invoke([
            "backup",
            "--source-db", self.source_db,
            "--backup-file", str(self.backup_path),
        ])
        self.assertEqual(res_backup.returncode, 0)

        # Attempt to restore into populated target: must fail without modifying target
        res_restore = self.invoke([
            "restore",
            "--backup-file", str(self.backup_path),
            "--target-db", self.target_db,
            "--source-db", self.source_db,
        ])
        self.assertNotEqual(res_restore.returncode, 0)
        self.assertIn("already contains tables", res_restore.stderr)

    def test_corrupted_backup_restore_fails_nonzero(self):
        # Write corrupted content into backup file
        corrupt_backup = Path(self.temp_dir.name) / "corrupt.dump"
        corrupt_backup.write_bytes(b"PGDMP\x01\x02\x03CORRUPTED_PAYLOAD_HERE")

        res = self.invoke([
            "restore",
            "--backup-file", str(corrupt_backup),
            "--target-db", self.target_db,
            "--source-db", self.source_db,
        ])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Restore operation failed", res.stderr)


if __name__ == "__main__":
    unittest.main()
