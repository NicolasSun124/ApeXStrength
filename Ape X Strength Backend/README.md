# Ape X Strength Backend

Small Flask/PostgreSQL prototype for the current iOS authentication flow.

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
psql "$DATABASE_URL" -f migration.sql
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

For an existing database, run `incremental_sync_migration.sql` when needed and run `password_reset_migration.sql` once before using password reset.

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
