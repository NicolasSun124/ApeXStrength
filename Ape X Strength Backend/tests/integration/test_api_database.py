from datetime import datetime, timezone

import pytest

import app as backend


pytestmark = pytest.mark.integration


def test_invalid_sync_rolls_back_journal_domain_and_revision(client, authenticated_user):
    user, headers = authenticated_user
    response = client.put(
        "/v1/sync",
        headers=headers,
        json={
            "cursor": 0,
            "changes": [
                {
                    "entity": "tag",
                    "client_uuid": "valid-tag",
                    "operation": "upsert",
                    "data": {"name": "Strength"},
                },
                {
                    "entity": "workout",
                    "client_uuid": "broken-workout",
                    "operation": "upsert",
                    "data": {"tag_ids": ["missing-tag"]},
                },
            ],
        },
    )

    assert response.status_code == 400
    assert "has not been synced" in response.get_json()["error"]
    assert backend.domain_row(backend.Tag, user.id, "valid-tag") is None
    assert backend.db.session.execute(
        backend.db.select(backend.SyncRecord).filter_by(user_id=user.id)
    ).scalars().all() == []
    assert backend.db.session.get(backend.User, user.id).sync_revision == 0


def test_sync_changes_are_isolated_by_authenticated_user(client, app):
    users = []
    for index in range(2):
        token = f"token-{index}"
        user = backend.User(
            email=f"athlete{index}@example.com",
            password_hash=backend.generate_password_hash("password123"),
            email_verified=True,
            session_token_hash=backend.digest(token),
        )
        backend.db.session.add(user)
        users.append((user, token))
    backend.db.session.commit()

    for user, token in users:
        response = client.put(
            "/v1/sync",
            headers={"Authorization": f"Bearer {token}"},
            json={"cursor": 0, "changes": [{
                "entity": "tag", "client_uuid": "same-client-id",
                "operation": "upsert", "data": {"name": user.email},
            }]},
        )
        assert response.status_code == 200

    rows = backend.db.session.execute(
        backend.db.select(backend.Tag).filter_by(client_uuid="same-client-id")
    ).scalars().all()
    assert {row.user_id for row in rows} == {user.id for user, _ in users}
    assert {row.name for row in rows} == {user.email for user, _ in users}


def test_deleting_account_cascades_owned_database_rows(client, authenticated_user):
    user, headers = authenticated_user
    tag = backend.Tag(user_id=user.id, client_uuid="tag-1", name="Strength")
    record = backend.SyncRecord(
        user_id=user.id,
        entity_type="tag",
        client_uuid="tag-1",
        data={"name": "Strength"},
        revision=1,
        updated_at=datetime.now(timezone.utc),
    )
    backend.db.session.add_all([tag, record])
    backend.db.session.commit()

    assert client.delete("/v1/account", headers=headers).status_code == 204
    assert backend.db.session.get(backend.User, user.id) is None
    assert backend.db.session.execute(
        backend.db.select(backend.Tag).filter_by(user_id=user.id)
    ).scalars().all() == []
    assert backend.db.session.execute(
        backend.db.select(backend.SyncRecord).filter_by(user_id=user.id)
    ).scalars().all() == []

