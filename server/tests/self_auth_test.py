import uuid

from app.core.security import create_access_token, decode_access_token


def test_check_encryption():
    sample_token = create_access_token(uuid.UUID("a0a0a0a0-a0a0-a0a0-a0a0-a0a0a0a0a0a0"))
    print(f"{sample_token}")
    assert decode_access_token(sample_token) ==  uuid.UUID("a0a0a0a0-a0a0-a0a0-a0a0-a0a0a0a0a0a0")


def test_check_authentication():
    sample_token = create_access_token(uuid.UUID("a0a0a0a0-a0a0-a0a0-a0a0-a0a0a0a0a0a0"))
    print(f"{sample_token}")
    assert decode_access_token(sample_token) ==  uuid.UUID("a0a0a0a0-a0a0-a0a0-a0a0-a0a0a0a0a0a0")


