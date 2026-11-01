# Pilot tenant provisioning

`provision_pilot_tenant.py` creates one church in the existing PostgreSQL schema
for #46 (part of #1/#21). Requires Python 3.10+ and `psql` on PATH. Apply the
repository EF migrations first. This operator tool uses database permissions;
it does not create members, assign roles, implement sign-in, or validate runtime
tenant isolation. Identity provider choice remains with the church owner.

Configure an explicit `PGSERVICE` (recommended) in a protected libpq service
file, or `PGDATABASE` plus the usual libpq connection configuration. Supply
passwords through a protected password file/service setup. Do not put connection
strings or passwords in shell arguments, source files, or submitted logs. TLS
and access permissions are controlled by the operator's connection setup.

After selecting the intended database, provide church JSON on stdin:

```sh
python3 scripts/provision_pilot_tenant.py < /protected/path/church.json
```

Example input (fictional, no credentials):

```json
{
  "name": "Pilot Church",
  "slug": "pilot-church",
  "contact_email": "office@example.org",
  "logo_url": "https://example.org/logo.png"
}
```

Name must contain 1–255 characters; slug must contain 1–100 lowercase ASCII
letters/digits with single separating hyphens. Contact email is required.
Logo URL is optional (stored as an empty string when omitted) and must use
HTTP(S) without embedded credentials. Unknown fields and control characters
are rejected. The status is `Active`; `CreatedAt` uses the database default.

The tool generates a UUID and inserts one row into `public."Tenants"` in a
single transaction. The existing unique slug index rejects conflicts, including
concurrent attempts. It never updates an existing row. Exit 0 prints only the
UUID after `psql` confirms commit; exit 2 means invalid input/configuration;
exit 1 means a dependency/database failure or an unconfirmed result. A timeout
or lost connection can leave commit outcome uncertain: inspect the selected
database by slug before retrying. Preserve the confirmed UUID for later trusted
identity-to-church mapping; do not use it as a client-supplied access credential.

`psql` startup files are disabled, password prompts are disabled, connection
timeout defaults to 10 seconds, and execution is limited to 30 seconds. Raw SQL,
contact values, connection diagnostics, and database errors are not printed.
Use approved database tooling to diagnose a failure privately.

Run offline regression tests:

```sh
python3 -m unittest discover -s scripts/tests -v
```

These tests cover validation, SQL data encoding, process options, and failure
reporting using a mocked process. They do not prove PostgreSQL persistence or
rollback. Before pilot use, verify against a disposable migrated PostgreSQL
database: insert a church, retrieve its UUID/fields/timestamp, retry its slug
with different details and confirm failure with the original row unchanged,
then create a second church and confirm its UUID differs. No live database or
deployment is needed for development. Parent #1 remains open for runtime
tenant authorization/isolation and profile management; #21 remains incomplete.
