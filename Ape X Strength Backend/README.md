# Ape X Strength Backend

Small Flask/PostgreSQL prototype for the current iOS authentication flow.

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
psql "$DATABASE_URL" -f migration/migration.sql
psql "$DATABASE_URL" -f migration/normalized_domain_migration.sql
psql "$DATABASE_URL" -f migration/premade_domain_seed.sql
flask --app app run --debug
```

## Development email with Mailpit

Mailpit captures every development email locally instead of delivering it to a real inbox. With the Mailpit binary installed:

```bash
mailpit --smtp 127.0.0.1:1025 --listen 127.0.0.1:8025
flask --app app run --debug
```

Or run it with Docker:

```bash
docker compose up -d mailpit
flask --app app run --debug
```

Open `http://localhost:8025` to read verification and password-reset emails. The API sends SMTP mail to Mailpit at `localhost:1025` by default. Every code is a cryptographically random six-digit value and expires after 10 minutes.

For an existing database, apply the scripts in `migration/` that have not yet
been run. `normalized_domain_migration.sql` introduces the relational domain
schema. `sync_records` remains the incremental synchronization journal; the new
tables provide the normalized relational persistence layer for application data.

The normalized schema includes user settings, muscles, exercises, tags, workout
templates, planned exercises/sets, workout sessions, performed exercises/sets,
and explicit join tables for all many-to-many relationships. Foreign keys,
ownership-scoped unique client identifiers, ordering constraints, value checks,
and cascade behavior enforce the domain invariants in PostgreSQL.

`PUT /v1/sync` writes accepted changes to both the sync journal and the matching
normalized tables in one transaction. Relationship identifiers are resolved
within the authenticated user's records, and deletions remove the normalized row
while retaining the journal tombstone used for cross-device conflict handling.

## Production email with Brevo

Set `APP_ENV=production`, `EMAIL_TRANSPORT=brevo`, `BREVO_API_KEY`, and a Brevo-verified `EMAIL_FROM_EMAIL`. The API sends transactional messages through Brevo's `POST /v3/smtp/email` API and never falls back to Mailpit in production.

Endpoints:

- `POST /v1/auth/send-code` with `email` and `password`
- `POST /v1/auth/verify-code` with `email` and `code`
- `POST /v1/auth/login` with `email` and `password`
- `POST /v1/auth/request-password-reset` with `email`
- `POST /v1/auth/reset-password` with `email`, `code`, and `password`
- `POST /v1/auth/sign-out` with a bearer token
- `PATCH /v1/profile` with a bearer token and `name`
- `PUT /v1/sync` with a bearer token, cursor, and incremental record changes. The response includes acknowledgements, conflicts, and server changes after the cursor.

Copy the settings in `.env.example` into your environment for local or production deployment. Do not commit a Brevo API key.
