import os

os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"

import app as backend


def test_authentication_flow():
    sent = []
    backend.app.config.update(
        TESTING=True,
        CODE_SENDER=lambda email, code, purpose: sent.append((email, code, purpose)),
    )

    with backend.app.app_context():
        backend.db.drop_all()
        backend.db.create_all()
        client = backend.app.test_client()

        assert client.get("/").status_code == 200

        response = client.post(
            "/v1/auth/send-code",
            json={"email": "athlete@example.com", "password": "password123"},
        )
        assert response.status_code == 204
        assert len(sent) == 1
        assert sent[0][0] == "athlete@example.com"
        assert sent[0][2] == "verification"
        assert len(sent[0][1]) == 6 and sent[0][1].isdigit()
        verification_code = sent[0][1]

        response = client.post(
            "/v1/auth/verify-code",
            json={"email": "athlete@example.com", "code": verification_code},
        )
        assert response.status_code == 200
        token = response.get_json()["token"]

        response = client.patch(
            "/v1/profile",
            headers={"Authorization": f"Bearer {token}"},
            json={"name": "Ape Athlete"},
        )
        assert response.status_code == 200
        assert response.get_json()["user"]["name"] == "Ape Athlete"

        snapshot = {"cursor": 0, "changes": [
            {"entity": "exercise", "operation": "upsert", "client_uuid": "exercise-1", "data": {"name": "Bench"}},
            {"entity": "workout_session", "operation": "upsert", "client_uuid": "session-1", "data": {"rating": 5}},
        ]}
        response = client.put(
            "/v1/sync",
            headers={"Authorization": f"Bearer {token}"},
            json=snapshot,
        )
        assert response.status_code == 200
        body = response.get_json()
        assert body["cursor"] == 2
        assert len(body["accepted"]) == 2
        records = backend.db.session.execute(backend.db.select(backend.SyncRecord)).scalars().all()
        assert {record.client_uuid for record in records} == {"exercise-1", "session-1"}

        # Sessions are append-only and a retry cannot overwrite history.
        retry = client.put("/v1/sync", headers={"Authorization": f"Bearer {token}"}, json={"cursor": 2, "changes": [
            {"entity": "workout_session", "operation": "upsert", "client_uuid": "session-1", "data": {"rating": 1}}
        ]})
        assert retry.status_code == 200
        session = backend.db.session.execute(backend.db.select(backend.SyncRecord).filter_by(client_uuid="session-1")).scalar_one()
        assert session.data["rating"] == 5

        # Tombstones prevent an older device from resurrecting deleted data.
        deleted = client.put("/v1/sync", headers={"Authorization": f"Bearer {token}"}, json={"cursor": 2, "changes": [
            {"entity": "exercise", "operation": "delete", "client_uuid": "exercise-1", "data": {}}
        ]})
        assert deleted.status_code == 200
        resurrect = client.put("/v1/sync", headers={"Authorization": f"Bearer {token}"}, json={"cursor": 2, "changes": [
            {"entity": "exercise", "operation": "upsert", "client_uuid": "exercise-1", "data": {"name": "Old Bench"}}
        ]})
        assert resurrect.get_json()["conflicts"][0]["operation"] == "delete"

        response = client.post(
            "/v1/auth/sign-out",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 204

        response = client.patch(
            "/v1/profile",
            headers={"Authorization": f"Bearer {token}"},
            json={"name": "Someone Else"},
        )
        assert response.status_code == 401

        response = client.post(
            "/v1/auth/login",
            json={"email": "athlete@example.com", "password": "password123"},
        )
        assert response.status_code == 200
        login_token = response.get_json()["token"]
        assert login_token != token

        response = client.patch(
            "/v1/profile",
            headers={"Authorization": f"Bearer {login_token}"},
            json={"name": "Logged In Athlete"},
        )
        assert response.status_code == 200


def test_password_reset_flow_uses_random_single_use_code_and_revokes_session():
    sent = []
    backend.app.config.update(
        TESTING=True,
        CODE_SENDER=lambda email, code, purpose: sent.append((email, code, purpose)),
    )
    with backend.app.app_context():
        backend.db.drop_all()
        backend.db.create_all()
        user = backend.User(
            email="athlete@example.com",
            password_hash=backend.generate_password_hash("password123"),
            email_verified=True,
        )
        backend.db.session.add(user)
        backend.db.session.commit()
        client = backend.app.test_client()

        login = client.post(
            "/v1/auth/login",
            json={"email": "athlete@example.com", "password": "password123"},
        )
        old_token = login.get_json()["token"]
        response = client.post(
            "/v1/auth/request-password-reset",
            json={"email": "athlete@example.com"},
        )
        assert response.status_code == 200
        assert sent[-1][0] == "athlete@example.com"
        assert sent[-1][2] == "password_reset"
        reset_code = sent[-1][1]
        assert reset_code.isdigit() and len(reset_code) == 6

        response = client.post(
            "/v1/auth/reset-password",
            json={"email": "athlete@example.com", "code": reset_code, "password": "newpassword123"},
        )
        assert response.status_code == 204
        assert client.post(
            "/v1/auth/reset-password",
            json={"email": "athlete@example.com", "code": reset_code, "password": "anotherpassword"},
        ).status_code == 400
        assert client.patch(
            "/v1/profile",
            headers={"Authorization": f"Bearer {old_token}"},
            json={"name": "Should Fail"},
        ).status_code == 401
        assert client.post(
            "/v1/auth/login",
            json={"email": "athlete@example.com", "password": "newpassword123"},
        ).status_code == 200

        sent_count = len(sent)
        response = client.post(
            "/v1/auth/request-password-reset",
            json={"email": "unknown@example.com"},
        )
        assert response.status_code == 200
        assert len(sent) == sent_count


def test_sync_requires_authentication_and_complete_snapshot():
    backend.app.config.update(TESTING=True)
    with backend.app.app_context():
        backend.db.drop_all()
        backend.db.create_all()
        client = backend.app.test_client()
        assert client.put("/v1/sync", json={}).status_code == 401
