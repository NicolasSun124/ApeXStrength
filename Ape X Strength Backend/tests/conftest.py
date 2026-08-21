import os
from pathlib import Path
import sys

import pytest


# The application reads its database URL while it is imported. Keep the default
# test run hermetic; the PostgreSQL E2E suite starts the app in a subprocess with
# its own explicit DATABASE_URL.
os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import app as backend  # noqa: E402


@pytest.fixture
def app():
    sent_emails = []
    backend.app.config.update(
        TESTING=True,
        CODE_SENDER=lambda email, code, purpose: sent_emails.append(
            (email, code, purpose)
        ),
    )
    with backend.app.app_context():
        backend.db.session.execute(backend.db.text("PRAGMA foreign_keys = ON"))
        backend.db.drop_all()
        backend.db.create_all()
        yield backend.app
        backend.db.session.remove()
        backend.db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def authenticated_user(app):
    token = "integration-test-token"
    user = backend.User(
        email="athlete@example.com",
        password_hash=backend.generate_password_hash("password123"),
        email_verified=True,
        session_token_hash=backend.digest(token),
    )
    backend.db.session.add(user)
    backend.db.session.commit()
    return user, {"Authorization": f"Bearer {token}"}
