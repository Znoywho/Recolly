import logging
import os
import secrets

from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

DATABASE_URL = os.environ["POSTGRES_DATABASE_URL"]


def _jwt_secret() -> str:
    secret = os.getenv("JWT_SECRET")
    if not secret:
        # Dev fallback only: issued tokens stop working after a restart.
        logger.warning("JWT_SECRET is not set; using a random secret for this process")
        secret = secrets.token_urlsafe(32)
    return secret


class Config:
    POSTGRES_DATABASE_URI = DATABASE_URL
    APP_VERSION = "1.0.0"

    # Backend JWTs (A1-A3).
    JWT_SECRET = _jwt_secret()
    ACCESS_TOKEN_TTL_SECONDS = int(os.getenv("ACCESS_TOKEN_TTL_SECONDS", "900"))
    REFRESH_TOKEN_TTL_DAYS = int(os.getenv("REFRESH_TOKEN_TTL_DAYS", "30"))

    # OAuth "Web application" client whose ID Flutter passes as serverClientId.
    GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
    GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
    # "" for Android server auth codes, "postmessage" for codes from the web popup flow.
    GOOGLE_REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI", "")
    # Fernet key for stored Google refresh tokens. Generate one with:
    # python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
    TOKEN_ENCRYPTION_KEY = os.getenv("TOKEN_ENCRYPTION_KEY", "")
    # Public HTTPS base URL that Google can reach for push notifications (G5), e.g. a tunnel.
    # Empty: no watch channel, two-way sync pulls only on POST /calendar/sync.
    WEBHOOK_BASE_URL = os.getenv("WEBHOOK_BASE_URL", "").rstrip("/")

    # Optional; only reported by GET /health for now.
    REDIS_URL = os.getenv("REDIS_URL", "")
