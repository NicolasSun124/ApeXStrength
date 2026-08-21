import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

import psycopg
import pytest
from werkzeug.security import generate_password_hash


pytestmark = pytest.mark.e2e
ROOT = Path(__file__).resolve().parents[2]


def _psycopg_url(database_url):
    return database_url.replace("postgresql+psycopg://", "postgresql://", 1)


def _request(url, method="GET", payload=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        url,
        method=method,
        headers=headers,
        data=json.dumps(payload).encode() if payload is not None else None,
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b"{}")


@pytest.fixture(scope="module")
def postgres_url():
    url = os.getenv("TEST_DATABASE_URL")
    if not url:
        pytest.skip("Set TEST_DATABASE_URL to a disposable PostgreSQL database")
    with psycopg.connect(_psycopg_url(url)) as connection:
        database_name = connection.info.dbname
        if not database_name.endswith("_test"):
            pytest.fail("TEST_DATABASE_URL database name must end with '_test'")
        connection.execute("DROP SCHEMA public CASCADE")
        connection.execute("CREATE SCHEMA public")
        for migration in ("migration.sql", "normalized_domain_migration.sql"):
            connection.execute((ROOT / "migration" / migration).read_text())
        connection.commit()
    yield url


@pytest.fixture(scope="module")
def live_api(postgres_url):
    with psycopg.connect(_psycopg_url(postgres_url)) as connection:
        connection.execute(
            """INSERT INTO users (id, email, password_hash, email_verified)
               VALUES (%s, %s, %s, TRUE)""",
            ("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "e2e@example.com", generate_password_hash("password123")),
        )
        connection.commit()

    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env = os.environ.copy()
    env.update(DATABASE_URL=postgres_url, APP_ENV="test")
    process = subprocess.Popen(
        [sys.executable, "-m", "flask", "--app", "app", "run", "--host", "127.0.0.1", "--port", str(port)],
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    base_url = f"http://127.0.0.1:{port}"
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            pytest.fail(f"API failed to start:\n{process.stdout.read()}")
        try:
            if _request(base_url)[0] == 200:
                break
        except OSError:
            time.sleep(0.1)
    else:
        process.terminate()
        pytest.fail("API did not become ready within 10 seconds")
    yield base_url, postgres_url
    process.terminate()
    process.wait(timeout=5)


def test_login_sync_and_relational_projection_over_real_http(live_api):
    base_url, database_url = live_api
    status, login = _request(
        f"{base_url}/v1/auth/login",
        method="POST",
        payload={"email": "e2e@example.com", "password": "password123"},
    )
    assert status == 200

    status, sync = _request(
        f"{base_url}/v1/sync",
        method="PUT",
        token=login["token"],
        payload={"cursor": 0, "changes": [
            {
                "entity": "tag", "client_uuid": "e2e-tag", "operation": "upsert",
                "data": {"name": "End to End"},
            },
            {
                "entity": "exercise", "client_uuid": "e2e-exercise", "operation": "upsert",
                "data": {
                    "name": "E2E Bench Press",
                    "primary_muscle_id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
                    "primary_muscle_name": "E2E Chest",
                    "primary_muscle_color": "FF0000",
                },
            },
        ]},
    )
    assert status == 200
    assert sync["cursor"] == 2
    assert sync["accepted"][0]["client_uuid"] == "e2e-tag"

    with psycopg.connect(_psycopg_url(database_url)) as connection:
        tag = connection.execute(
            "SELECT name FROM tags WHERE client_uuid = %s", ("e2e-tag",)
        ).fetchone()
        journal = connection.execute(
            "SELECT revision, data->>'name' FROM sync_records WHERE client_uuid = %s",
            ("e2e-tag",),
        ).fetchone()
        exercise = connection.execute(
            """SELECT e.name, m.name
               FROM exercises e JOIN muscles m ON m.id = e.primary_muscle_id
               WHERE e.client_uuid = %s""",
            ("e2e-exercise",),
        ).fetchone()
    assert tag == ("End to End",)
    assert journal == (1, "End to End")
    assert exercise == ("E2E Bench Press", "E2E Chest")


def test_postgres_constraints_reject_invalid_domain_data(postgres_url):
    with psycopg.connect(_psycopg_url(postgres_url)) as connection:
        with pytest.raises(psycopg.errors.CheckViolation):
            connection.execute(
                "INSERT INTO muscles (id, name, color_hex) VALUES (%s, %s, %s)",
                ("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "Invalid", "ZZZZZZ"),
            )
