#!/usr/bin/env python3
"""Provision one church using operator database access and church JSON on stdin."""

import argparse
import json
import os
import re
import subprocess
import sys
import uuid
from urllib.parse import urlsplit


def validate_church(data):
    if not isinstance(data, dict):
        raise ValueError("Expected an object")
    fields = {"name", "slug", "contact_email", "logo_url"}
    if set(data) - fields:
        raise ValueError("Unknown fields")
    church = {}
    for field in fields:
        value = data.get(field, "")
        if not isinstance(value, str) or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError("Text without control characters required")
        value.encode("utf-8")
        church[field] = value.strip()
    if not 1 <= len(church["name"]) <= 255:
        raise ValueError("Invalid name length")
    if (not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", church["slug"])
            or len(church["slug"]) > 100):
        raise ValueError("Invalid slug")
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", church["contact_email"]):
        raise ValueError("Invalid email")
    if church["logo_url"]:
        url = urlsplit(church["logo_url"])
        if (url.scheme not in {"https", "http"} or not url.hostname
                or url.username is not None or url.password is not None
                or any(c.isspace() for c in church["logo_url"])):
            raise ValueError("Invalid logo URL")
    return church


def sql_text(value):
    # Hex keeps Unicode, quotes and backslashes out of SQL and psql syntax.
    return "convert_from(decode('" + value.encode("utf-8").hex() + "', 'hex'), 'UTF8')"


def provision(church, tenant_id):
    values = [str(tenant_id), church["name"], church["slug"],
              church["contact_email"], church["logo_url"], "Active"]
    sql = ('INSERT INTO public."Tenants" '
           '("Id", "Name", "Slug", "ContactEmail", "LogoUrl", "Status") VALUES ('
           + ", ".join(sql_text(value) + ("::uuid" if i == 0 else "")
                       for i, value in enumerate(values)) + ");\n")
    # Existing unique index handles concurrent duplicate slugs; never upsert.
    env = dict(os.environ)
    env.setdefault("PGCONNECT_TIMEOUT", "10")
    subprocess.run(
        ["psql", "--no-psqlrc", "--no-password", "--quiet",
         "--set=ON_ERROR_STOP=1", "--single-transaction", "--file=-"],
        input=sql, text=True, encoding="utf-8", env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        check=True, timeout=30,
    )


def main(argv=None):
    argparse.ArgumentParser(description=__doc__).parse_args(argv)
    if not (os.environ.get("PGDATABASE", "").strip() or os.environ.get("PGSERVICE", "").strip()):
        print("Set an explicit PGDATABASE or PGSERVICE before provisioning.", file=sys.stderr)
        return 2
    try:
        church = validate_church(json.load(sys.stdin))
    except (ValueError, UnicodeError):
        print("Invalid church JSON; check documented fields and validation rules.", file=sys.stderr)
        return 2
    tenant_id = uuid.uuid4()
    try:
        provision(church, tenant_id)
    except FileNotFoundError:
        print("PostgreSQL client psql is required on PATH.", file=sys.stderr)
        return 1
    except (subprocess.SubprocessError, OSError):
        print("Provisioning was not confirmed. Check connectivity, schema and slug conflicts; "
              "inspect the target before retrying. Database diagnostics are suppressed.", file=sys.stderr)
        return 1
    print(tenant_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
