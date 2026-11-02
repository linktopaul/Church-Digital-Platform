"""Offline unit tests for backup and restore script safeguards."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parents[1]
SCRIPT = SCRIPT_DIR / "backup_restore.py"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import backup_restore  # noqa: E402


class OfflineBackupRestoreTests(unittest.TestCase):
    def invoke(self, args, extra_env=None):
        env = dict(os.environ)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [sys.executable, str(SCRIPT)] + args,
            text=True,
            capture_output=True,
            env=env,
            timeout=10,
        )

    def test_missing_subcommand_exits_nonzero(self):
        res = self.invoke([])
        self.assertNotEqual(res.returncode, 0)

    def test_restore_rejects_source_target_collision(self):
        with tempfile.NamedTemporaryFile() as tmp:
            tmp.write(b"non-empty")
            tmp.flush()
            res = self.invoke([
                "restore",
                "--backup-file", tmp.name,
                "--source-db", "same_db",
                "--target-db", "same_db",
            ])
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("cannot be the same", res.stderr)

    def test_restore_rejects_collision_via_pgdatabase_env(self):
        with tempfile.NamedTemporaryFile() as tmp:
            tmp.write(b"non-empty")
            tmp.flush()
            res = self.invoke(
                [
                    "restore",
                    "--backup-file", tmp.name,
                    "--target-db", "same_db",
                ],
                extra_env={"PGDATABASE": "same_db"},
            )
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("cannot be the same", res.stderr)

    def test_verify_rejects_source_target_collision(self):
        res = self.invoke([
            "verify",
            "--source-db", "same_db",
            "--target-db", "same_db",
        ])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("must be distinct", res.stderr)

    def test_restore_missing_backup_file_exits_nonzero(self):
        res = self.invoke([
            "restore",
            "--backup-file", "/nonexistent/path/to/backup.dump",
            "--source-db", "source_db",
            "--target-db", "target_db",
        ])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Backup archive not found", res.stderr)

    def test_restore_empty_backup_file_exits_nonzero(self):
        with tempfile.NamedTemporaryFile() as tmp:
            tmp.flush()
            res = self.invoke([
                "restore",
                "--backup-file", tmp.name,
                "--source-db", "source_db",
                "--target-db", "target_db",
            ])
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("Backup archive is empty", res.stderr)

    def test_invalid_database_identifier_rejected(self):
        res = self.invoke([
            "backup",
            "--source-db", "invalid;db;name",
            "--backup-file", "/tmp/any.dump",
        ])
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("invalid characters", res.stderr)

    def test_failed_backup_preserves_existing_backup_archive(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            existing_archive = Path(tmpdir) / "existing_recovery.dump"
            original_bytes = b"PGDMP_EXISTING_RECOVERY_ARCHIVE_CONTENT"
            existing_archive.write_bytes(original_bytes)

            def fake_run(*args, **kwargs):
                return subprocess.CompletedProcess(args[0], returncode=1, stdout="", stderr="connection failed")

            with mock.patch("backup_restore.subprocess.run", side_effect=fake_run):
                with self.assertRaises(RuntimeError):
                    backup_restore.run_backup("source_db", existing_archive)

            self.assertTrue(existing_archive.exists())
            self.assertEqual(existing_archive.read_bytes(), original_bytes)

    def test_verify_fails_when_application_table_count_query_fails_on_both_dbs(self):
        def fake_run_psql(db_name, query, env=None, tuples_only=False):
            if "__EFMigrationsHistory" in query:
                return subprocess.CompletedProcess(
                    ["psql"], returncode=0, stdout="20261031115204_InitialCreate:10.0.14\n", stderr=""
                )
            return subprocess.CompletedProcess(
                ["psql"], returncode=1, stdout="", stderr="ERROR: permission denied for table Tenants"
            )

        with mock.patch("backup_restore.run_psql", side_effect=fake_run_psql):
            with self.assertRaises(RuntimeError) as ctx:
                backup_restore.verify_databases("source_db", "target_db")
            self.assertIn("Failed to query row count", str(ctx.exception))

    def test_verify_fails_on_malformed_table_count_output(self):
        def fake_run_psql(db_name, query, env=None, tuples_only=False):
            if "__EFMigrationsHistory" in query:
                return subprocess.CompletedProcess(
                    ["psql"], returncode=0, stdout="20261031115204_InitialCreate:10.0.14\n", stderr=""
                )
            return subprocess.CompletedProcess(
                ["psql"], returncode=0, stdout="malformed_count\n", stderr=""
            )

        with mock.patch("backup_restore.run_psql", side_effect=fake_run_psql):
            with self.assertRaises(RuntimeError) as ctx:
                backup_restore.verify_databases("source_db", "target_db")
            self.assertIn("Malformed row count", str(ctx.exception))

    def test_verify_fails_when_row_signature_query_fails_on_both_dbs(self):
        def fake_run_psql(db_name, query, env=None, tuples_only=False):
            if "__EFMigrationsHistory" in query:
                return subprocess.CompletedProcess(
                    ["psql"], returncode=0, stdout="20261031115204_InitialCreate:10.0.14\n", stderr=""
                )
            if "SELECT count(*)" in query:
                return subprocess.CompletedProcess(["psql"], returncode=0, stdout="1\n", stderr="")
            return subprocess.CompletedProcess(
                ["psql"], returncode=1, stdout="", stderr="ERROR: permission denied"
            )

        with mock.patch("backup_restore.run_psql", side_effect=fake_run_psql):
            with self.assertRaises(RuntimeError) as ctx:
                backup_restore.verify_databases("source_db", "target_db")
            self.assertIn("Failed to query row signatures", str(ctx.exception))

    def test_verify_fails_on_same_count_row_signature_mismatch(self):
        hash_a = "a" * 32
        hash_b = "b" * 32

        def fake_run_psql(db_name, query, env=None, tuples_only=False):
            if "__EFMigrationsHistory" in query:
                return subprocess.CompletedProcess(
                    ["psql"], returncode=0, stdout="20261031115204_InitialCreate:10.0.14\n", stderr=""
                )
            if "SELECT count(*)" in query:
                return subprocess.CompletedProcess(["psql"], returncode=0, stdout="1\n", stderr="")
            if '"SetlistItems"' in query and db_name == "target_db":
                return subprocess.CompletedProcess(
                    ["psql"], returncode=0, stdout=f"row-1:{hash_b}\n", stderr=""
                )
            return subprocess.CompletedProcess(
                ["psql"], returncode=0, stdout=f"row-1:{hash_a}\n", stderr=""
            )

        with mock.patch("backup_restore.run_psql", side_effect=fake_run_psql):
            with self.assertRaises(AssertionError) as ctx:
                backup_restore.verify_databases("source_db", "target_db")
            self.assertIn("SetlistItems", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
