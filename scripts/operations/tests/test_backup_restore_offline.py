"""Offline unit tests for backup and restore script safeguards."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "backup_restore.py"


class OfflineBackupRestoreTests(unittest.TestCase):
    def invoke(self, args):
        return subprocess.run(
            [sys.executable, str(SCRIPT)] + args,
            text=True,
            capture_output=True,
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


if __name__ == "__main__":
    unittest.main()
