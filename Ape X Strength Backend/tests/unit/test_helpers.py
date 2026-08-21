from datetime import datetime, timezone
from unittest.mock import patch
import uuid

import pytest

import app as backend


def test_digest_is_stable_and_does_not_store_the_secret():
    result = backend.digest("session-secret")
    assert result == backend.digest("session-secret")
    assert result != "session-secret"
    assert len(result) == 64


def test_generate_code_is_zero_padded():
    with patch.object(backend.secrets, "randbelow", return_value=42):
        assert backend.generate_code() == "000042"


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("2026-08-20T12:30:00Z", datetime(2026, 8, 20, 12, 30, tzinfo=timezone.utc)),
        (None, "fallback"),
    ],
)
def test_parsed_datetime(value, expected):
    assert backend.parsed_datetime(value, "fallback") == expected


def test_parsed_datetime_rejects_malformed_input():
    with pytest.raises(backend.DomainProjectionError, match="Invalid date"):
        backend.parsed_datetime("not-a-date")


def test_seed_uuid_is_deterministic_and_namespaced():
    first = backend.deterministic_seed_uuid("apexstrength:muscle:biceps")
    assert first == backend.deterministic_seed_uuid("apexstrength:muscle:biceps")
    assert first != backend.deterministic_seed_uuid("apexstrength:muscle:triceps")
    assert isinstance(first, uuid.UUID)


@pytest.mark.parametrize("change, message", [
    ({"entity": "unknown", "client_uuid": str(uuid.uuid4()), "operation": "delete"}, "entity"),
    ({"entity": "tag", "client_uuid": "not-a-uuid", "operation": "delete"}, "client_uuid"),
    ({"entity": "workout_session", "client_uuid": str(uuid.uuid4()), "operation": "upsert",
      "data": {"rating": 6}}, "rating"),
    ({"entity": "template_set", "client_uuid": str(uuid.uuid4()), "operation": "upsert",
      "data": {"template_exercise_id": str(uuid.uuid4()), "reps": -1}}, "reps"),
    ({"entity": "exercise", "client_uuid": str(uuid.uuid4()), "operation": "upsert",
      "data": {"tracking_type": "anything", "target_rest_seconds": 120}}, "tracking_type"),
    ({"entity": "exercise", "client_uuid": str(uuid.uuid4()), "operation": "upsert",
      "data": {"tracking_type": "reps_weighted", "target_rest_seconds": 86401}}, "target_rest_seconds"),
    ({"entity": "settings", "client_uuid": "settings", "operation": "upsert",
      "data": {"weight_unit": "stone"}}, "weight_unit"),
    ({"entity": "exercise", "client_uuid": str(uuid.uuid4()), "operation": "upsert",
      "data": {"tracking_type": "reps_weighted", "primary_muscle_color": "#FF0000"}}, "primary_muscle_color"),
])
def test_sync_change_validation_rejects_invalid_values(change, message):
    with pytest.raises(backend.DomainProjectionError, match=message):
        backend.validate_sync_change(change)


def test_sync_change_validation_accepts_supported_values():
    backend.validate_sync_change({
        "entity": "session_set",
        "client_uuid": str(uuid.uuid4()),
        "operation": "upsert",
        "data": {
            "session_exercise_id": str(uuid.uuid4()), "number": 1,
            "reps": 0, "time_seconds": 0, "distance": 0, "weight": 0,
        },
    })


def test_email_content_distinguishes_verification_and_reset():
    verification = backend.email_content("verification", "123456")
    reset = backend.email_content("password_reset", "654321")
    assert "Verify" in verification[0]
    assert "123456" in verification[1]
    assert "Reset" in reset[0]
    assert "654321" in reset[1]
