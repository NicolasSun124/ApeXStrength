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


def test_email_content_distinguishes_verification_and_reset():
    verification = backend.email_content("verification", "123456")
    reset = backend.email_content("password_reset", "654321")
    assert "Verify" in verification[0]
    assert "123456" in verification[1]
    assert "Reset" in reset[0]
    assert "654321" in reset[1]

