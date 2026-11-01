"""Integration contract against an explicitly enabled disposable migrated database."""
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
import uuid

SCRIPT = Path(__file__).resolve().parents[1] / "provision_pilot_tenant.py"

@unittest.skipUnless(os.environ.get("PILOT_DISPOSABLE_DB_TEST") == "1",
                     "requires disposable migrated PostgreSQL")
class PostgreSQLProvisionTests(unittest.TestCase):
    def invoke(self, church):
        return subprocess.run([sys.executable, str(SCRIPT)], input=json.dumps(church),
                              text=True, capture_output=True, timeout=40)

    def row(self, tenant_id):
        # Only generated/validated UUIDs enter this query.
        tenant_id = str(uuid.UUID(tenant_id))
        result = subprocess.run(
            ["psql", "-X", "-w", "-A", "-t", "-v", "ON_ERROR_STOP=1",
             "-c", 'SELECT row_to_json(t)::text FROM public."Tenants" t WHERE "Id"=\''
             + tenant_id + "\'::uuid"],
            text=True, capture_output=True, check=True, timeout=15)
        return json.loads(result.stdout.strip())

    def test_persists_exact_data_rejects_duplicate_and_generates_distinct_ids(self):
        suffix = uuid.uuid4().hex
        church = {"name": "St. Paul's தேவாலயம் \\ sample",
                  "slug": "integration-" + suffix,
                  "contact_email": "office@example.org",
                  "logo_url": "https://example.org/logo.png"}
        result = self.invoke(church)
        self.assertEqual(result.returncode, 0, "disposable database insertion failed")
        first_id = str(uuid.UUID(result.stdout.strip()))
        self.assertEqual(result.stderr, "")
        saved = self.row(first_id)
        self.assertEqual(saved["Name"], church["name"])
        self.assertEqual(saved["Slug"], church["slug"])
        self.assertEqual(saved["ContactEmail"], church["contact_email"])
        self.assertEqual(saved["LogoUrl"], church["logo_url"])
        self.assertEqual(saved["Status"], "Active")
        self.assertTrue(saved["CreatedAt"])

        duplicate = self.invoke({**church, "name": "Must not replace original"})
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertEqual(duplicate.stdout, "")
        self.assertEqual(self.row(first_id), saved)

        second = self.invoke({**church, "slug": "second-" + suffix})
        self.assertEqual(second.returncode, 0, "second database insertion failed")
        second_id = str(uuid.UUID(second.stdout.strip()))
        self.assertNotEqual(first_id, second_id)
        self.assertEqual(self.row(second_id)["Slug"], "second-" + suffix)

if __name__ == "__main__":
    unittest.main()
