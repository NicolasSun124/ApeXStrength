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
        created_user = backend.db.session.execute(
            backend.db.select(backend.User).filter_by(email="athlete@example.com")
        ).scalar_one()
        assert len(backend.db.session.execute(backend.db.select(backend.Muscle)).scalars().all()) == 22
        assert len(backend.db.session.execute(
            backend.db.select(backend.Tag).filter_by(user_id=created_user.id)
        ).scalars().all()) == 22

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
        user = backend.db.session.execute(backend.db.select(backend.User).filter_by(email="athlete@example.com")).scalar_one()
        assert backend.domain_row(backend.Exercise, user.id, "exercise-1").name == "Bench"

        # Active sessions remain mutable so progress can be synced repeatedly.
        retry = client.put("/v1/sync", headers={"Authorization": f"Bearer {token}"}, json={"cursor": 2, "changes": [
            {"entity": "workout_session", "operation": "upsert", "client_uuid": "session-1", "data": {"rating": 1, "ended_at": None}}
        ]})
        assert retry.status_code == 200
        session = backend.db.session.execute(backend.db.select(backend.SyncRecord).filter_by(client_uuid="session-1")).scalar_one()
        assert session.data["rating"] == 1

        # Tombstones prevent an older device from resurrecting deleted data.
        deleted = client.put("/v1/sync", headers={"Authorization": f"Bearer {token}"}, json={"cursor": 2, "changes": [
            {"entity": "exercise", "operation": "delete", "client_uuid": "exercise-1", "data": {}}
        ]})
        assert deleted.status_code == 200
        assert backend.domain_row(backend.Exercise, user.id, "exercise-1") is None
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


def test_multiple_devices_keep_independent_sessions_and_sign_out_independently():
    with backend.app.app_context():
        backend.db.drop_all()
        backend.db.create_all()
        user = backend.User(
            email="multi-device@example.com",
            password_hash=backend.generate_password_hash("password123"),
            email_verified=True,
        )
        backend.db.session.add(user)
        backend.db.session.commit()
        client = backend.app.test_client()

        first = client.post("/v1/auth/login", json={
            "email": user.email, "password": "password123",
        }).get_json()["token"]
        second = client.post("/v1/auth/login", json={
            "email": user.email, "password": "password123",
        }).get_json()["token"]

        assert first != second
        assert client.patch("/v1/profile", headers={"Authorization": f"Bearer {first}"}, json={"name": "First"}).status_code == 200
        assert client.patch("/v1/profile", headers={"Authorization": f"Bearer {second}"}, json={"name": "Second"}).status_code == 200

        assert client.post("/v1/auth/sign-out", headers={"Authorization": f"Bearer {first}"}).status_code == 204
        assert client.patch("/v1/profile", headers={"Authorization": f"Bearer {first}"}, json={"name": "Nope"}).status_code == 401
        assert client.patch("/v1/profile", headers={"Authorization": f"Bearer {second}"}, json={"name": "Still signed in"}).status_code == 200


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


def test_delete_account_requires_authentication_and_removes_user():
    backend.app.config.update(TESTING=True)
    with backend.app.app_context():
        backend.db.drop_all()
        backend.db.create_all()
        token = "delete-account-token"
        user = backend.User(
            email="delete@example.com",
            password_hash=backend.generate_password_hash("password123"),
            email_verified=True,
            session_token_hash=backend.digest(token),
        )
        backend.db.session.add(user)
        backend.db.session.commit()
        client = backend.app.test_client()

        assert client.delete("/v1/account").status_code == 401
        response = client.delete(
            "/v1/account",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 204
        assert backend.db.session.execute(
            backend.db.select(backend.User).filter_by(email="delete@example.com")
        ).scalar_one_or_none() is None
        assert client.patch(
            "/v1/profile",
            headers={"Authorization": f"Bearer {token}"},
            json={"name": "Should Fail"},
        ).status_code == 401


def test_reset_data_only_deletes_the_authenticated_users_records():
    backend.app.config.update(TESTING=True)
    with backend.app.app_context():
        backend.db.drop_all()
        backend.db.create_all()
        target_token = "target-reset-token"
        other_token = "other-user-token"
        target = backend.User(
            email="target@example.com",
            password_hash=backend.generate_password_hash("password123"),
            email_verified=True,
            session_token_hash=backend.digest(target_token),
            sync_revision=1,
        )
        other = backend.User(
            email="other@example.com",
            password_hash=backend.generate_password_hash("password123"),
            email_verified=True,
            session_token_hash=backend.digest(other_token),
            sync_revision=1,
        )
        backend.db.session.add_all([target, other])
        backend.db.session.flush()
        now = backend.datetime.now(backend.timezone.utc)
        target_tag = backend.Tag(user_id=target.id, client_uuid="target-tag", name="Target")
        other_tag = backend.Tag(user_id=other.id, client_uuid="other-tag", name="Other")
        target_record = backend.SyncRecord(
            user_id=target.id, entity_type="tag", client_uuid="target-tag",
            data={"name": "Target"}, revision=1, updated_at=now,
        )
        other_record = backend.SyncRecord(
            user_id=other.id, entity_type="tag", client_uuid="other-tag",
            data={"name": "Other"}, revision=1, updated_at=now,
        )
        backend.db.session.add_all([target_tag, other_tag, target_record, other_record])
        backend.db.session.commit()
        client = backend.app.test_client()

        assert client.delete("/v1/data").status_code == 401
        response = client.delete(
            "/v1/data",
            headers={"Authorization": f"Bearer {target_token}"},
        )
        assert response.status_code == 204
        assert backend.db.session.execute(
            backend.db.select(backend.Tag).filter_by(user_id=target.id)
        ).scalars().all() == []
        assert backend.db.session.execute(
            backend.db.select(backend.SyncRecord).filter_by(user_id=target.id)
        ).scalars().all() == []
        assert len(backend.db.session.execute(
            backend.db.select(backend.Tag).filter_by(user_id=other.id)
        ).scalars().all()) == 1
        assert len(backend.db.session.execute(
            backend.db.select(backend.SyncRecord).filter_by(user_id=other.id)
        ).scalars().all()) == 1
        assert backend.db.session.get(backend.User, target.id).sync_revision == 0
        assert client.patch(
            "/v1/profile",
            headers={"Authorization": f"Bearer {target_token}"},
            json={"name": "Still Signed In"},
        ).status_code == 200


def test_sync_requires_authentication_and_complete_snapshot():
    backend.app.config.update(TESTING=True)
    with backend.app.app_context():
        backend.db.drop_all()
        backend.db.create_all()
        client = backend.app.test_client()
        assert client.put("/v1/sync", json={}).status_code == 401


def test_sync_projects_changes_into_normalized_domain_tables():
    backend.app.config.update(TESTING=True)
    with backend.app.app_context():
        backend.db.drop_all()
        backend.db.create_all()
        token = "normalized-sync-token"
        user = backend.User(
            email="normalized@example.com",
            password_hash=backend.generate_password_hash("password123"),
            email_verified=True,
            session_token_hash=backend.digest(token),
        )
        backend.db.session.add(user)
        backend.db.session.commit()
        muscle_id = "a5c389af-0d22-4e73-83e8-bcc4b5c416d1"
        changes = [
            {"entity": "settings", "client_uuid": "settings", "operation": "upsert", "data": {
                "weight_unit": "kg", "distance_unit": "km", "rest_timer_notifications_enabled": False,
            }},
            {"entity": "exercise", "client_uuid": "exercise-1", "operation": "upsert", "data": {
                "name": "Bench Press", "created_at": "2026-08-20T12:00:00Z", "tracking_type": "reps|weighted",
                "target_rest_seconds": 180, "primary_muscle_id": muscle_id,
                "primary_muscle_name": "Chest", "primary_muscle_color": "FF0000",
            }},
            {"entity": "tag", "client_uuid": "tag-1", "operation": "upsert", "data": {"name": "Push"}},
            {"entity": "workout", "client_uuid": "workout-1", "operation": "upsert", "data": {
                "name": "Push Day", "created_at": "2026-08-20T12:00:00Z",
                "updated_at": "2026-08-20T12:00:00Z", "tag_ids": ["tag-1"],
            }},
            {"entity": "template_exercise", "client_uuid": "template-exercise-1", "operation": "upsert", "data": {
                "workout_id": "workout-1", "exercise_id": "exercise-1", "position": 0,
            }},
            {"entity": "template_set", "client_uuid": "template-set-1", "operation": "upsert", "data": {
                "template_exercise_id": "template-exercise-1", "number": 1, "reps": 8, "weight": 100,
            }},
            {"entity": "workout_session", "client_uuid": "session-1", "operation": "upsert", "data": {
                "workout_id": "workout-1", "started_at": "2026-08-20T13:00:00Z", "rating": 5,
            }},
            {"entity": "session_exercise", "client_uuid": "session-exercise-1", "operation": "upsert", "data": {
                "session_id": "session-1", "exercise_id": "exercise-1", "position": 0, "name": "Bench Press",
                "tracking_type": "reps", "difficulty_type": "weighted", "primary_muscle_name": "Chest",
                "primary_muscle_color": "FF0000", "target_rest_seconds": 180,
            }},
            {"entity": "session_set", "client_uuid": "session-set-1", "operation": "upsert", "data": {
                "session_exercise_id": "session-exercise-1", "number": 1, "completed": True,
                "completed_at": "2026-08-20T13:05:00Z", "reps": 8, "weight": 100,
            }},
        ]
        response = backend.app.test_client().put(
            "/v1/sync", headers={"Authorization": f"Bearer {token}"}, json={"cursor": 0, "changes": changes},
        )
        assert response.status_code == 200
        assert backend.db.session.get(backend.UserSettings, user.id).weight_unit == "kg"
        exercise = backend.domain_row(backend.Exercise, user.id, "exercise-1")
        assert exercise.name == "Bench Press"
        assert exercise.primary_muscle_id == backend.uuid.UUID(muscle_id)
        workout = backend.domain_row(backend.WorkoutTemplate, user.id, "workout-1")
        assert [tag.name for tag in workout.tags] == ["Push"]
        assert backend.domain_row(backend.TemplateSet, user.id, "template-set-1").planned_reps == 8
        assert backend.domain_row(backend.WorkoutSession, user.id, "session-1").rating == 5
        assert backend.domain_row(backend.SessionSet, user.id, "session-set-1").completed is True

        update = backend.app.test_client().put(
            "/v1/sync", headers={"Authorization": f"Bearer {token}"}, json={"cursor": 9, "changes": [{
                "entity": "tag", "client_uuid": "tag-1", "operation": "upsert", "data": {"name": "Upper Body"},
            }]},
        )
        assert update.status_code == 200
        assert backend.domain_row(backend.Tag, user.id, "tag-1").name == "Upper Body"
