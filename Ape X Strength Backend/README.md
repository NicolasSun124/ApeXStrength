# Ape X Strength Backend

Small Flask/PostgreSQL prototype for the current iOS authentication flow.

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
psql "$DATABASE_URL" -f migration.sql
flask --app app run --debug
```

For an existing database created before incremental sync, run `incremental_sync_migration.sql` once.

Endpoints:

- `POST /v1/auth/send-code` with `email` and `password`
- `POST /v1/auth/verify-code` with `email` and `code`
- `POST /v1/auth/login` with `email` and `password`
- `POST /v1/auth/sign-out` with a bearer token
- `PATCH /v1/profile` with a bearer token and `name`
- `PUT /v1/sync` with a bearer token, cursor, and incremental record changes. The response includes acknowledgements, conflicts, and server changes after the cursor.

The development code defaults to `123456`. Configure SMTP variables from `.env.example` when you want real email delivery.
