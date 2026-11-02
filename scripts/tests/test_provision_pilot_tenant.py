import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
import uuid


SCRIPT = Path(__file__).resolve().parents[1] / "provision_pilot_tenant.py"
spec = importlib.util.spec_from_file_location("provision_pilot_tenant", SCRIPT)
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


class ProvisionTests(unittest.TestCase):
    def setUp(self):
        self.church = {"name": "Pilot Church", "slug": "pilot-church",
                       "contact_email": "office@example.org", "logo_url": ""}

    def run_cli(self, data=None, env=None, error=None, raw=None):
        out, err = io.StringIO(), io.StringIO()
        payload = raw if raw is not None else json.dumps(self.church if data is None else data)
        with patch.dict(os.environ, env if env is not None else {"PGDATABASE": "test_only"}, clear=True), \
                patch.object(cli.sys, "stdin", io.StringIO(payload)), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                patch.object(cli.subprocess, "run", side_effect=error) as run:
            code = cli.main([])
        return code, out.getvalue(), err.getvalue(), run

    def test_invalid_input_never_connects(self):
        invalid = [[], {**self.church, "tenant_id": str(uuid.uuid4())}]
        for field, values in {
            "name": ["", "  ", "n" * 256, "line\nbreak", None, "\ud800"],
            "slug": ["", "UPPER", "-edge", "edge-", "two--parts", "a" * 101, "a/b"],
            "contact_email": ["", "no-address", "two @example.org"],
            "logo_url": ["javascript:alert(1)", "https://u:p@example.org/a", "https://", "https://a/b c"],
        }.items():
            invalid.extend({**self.church, field: value} for value in values)
        for data in invalid:
            with self.subTest(data=data):
                code, out, _, run = self.run_cli(data)
                self.assertEqual(code, 2)
                self.assertEqual(out, "")
                run.assert_not_called()

    def test_malformed_json_never_connects(self):
        for raw in ["", "{broken", "null"]:
            code, out, _, run = self.run_cli(raw=raw)
            self.assertEqual((code, out), (2, ""))
            run.assert_not_called()

    def test_explicit_target_required(self):
        code, out, _, run = self.run_cli(env={})
        self.assertEqual((code, out), (2, ""))
        run.assert_not_called()

    def test_success_prints_uuid_after_transaction_without_profile_or_prompt(self):
        code, out, err, run = self.run_cli(env={"PGSERVICE": "pilot_test"})
        self.assertEqual((code, err), (0, ""))
        tenant_id = uuid.UUID(out.strip())
        self.assertEqual(tenant_id.version, 4)
        args, kwargs = run.call_args
        for flag in ["--no-psqlrc", "--no-password", "--single-transaction", "--set=ON_ERROR_STOP=1", "--file=-"]:
            self.assertIn(flag, args[0])
        self.assertTrue(kwargs["check"])
        self.assertEqual(kwargs["env"]["PGSERVICE"], "pilot_test")
        self.assertEqual(kwargs["stdout"], subprocess.DEVNULL)
        self.assertEqual(kwargs["stderr"], subprocess.DEVNULL)
        self.assertNotIn("office@example.org", " ".join(args[0]))
        self.assertIn(cli.sql_text(str(tenant_id)) + "::uuid", kwargs["input"])
        self.assertIn('INSERT INTO public."Tenants"', kwargs["input"])
        self.assertNotIn("UPDATE", kwargs["input"])
        self.assertNotIn("ON CONFLICT", kwargs["input"])

    def test_unicode_quotes_and_backslashes_are_encoded_as_data(self):
        name = "St. Paul's \\'; DROP TABLE public.\"Tenants\"; -- தேவாலயம்"
        code, _, _, run = self.run_cli({**self.church, "name": name})
        self.assertEqual(code, 0)
        sql = run.call_args.kwargs["input"]
        self.assertNotIn(name, sql)
        self.assertNotIn("DROP TABLE", sql)
        self.assertIn(name.encode("utf-8").hex(), sql)

    def test_database_failure_missing_client_and_timeout_do_not_report_success_or_leak(self):
        for error in [FileNotFoundError("secret"),
                      subprocess.CalledProcessError(3, "psql", stderr="private contact"),
                      subprocess.TimeoutExpired("psql secret", 30), OSError("private path")]:
            with self.subTest(error=type(error)):
                code, out, err, _ = self.run_cli(error=error)
                self.assertEqual((code, out), (1, ""))
                self.assertNotIn("secret", err)
                self.assertNotIn("private", err)

    def test_trimmed_input_and_optional_logo(self):
        data = {**self.church, "name": "  Pilot Church  ", "logo_url": "https://example.org/logo.png"}
        self.assertEqual(cli.validate_church(data)["name"], "Pilot Church")
        del data["logo_url"]
        self.assertEqual(cli.validate_church(data)["logo_url"], "")


if __name__ == "__main__":
    unittest.main()
