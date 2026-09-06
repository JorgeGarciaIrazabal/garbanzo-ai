import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWTError

from app.core.config import Settings, get_settings

security = HTTPBearer()


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against a bcrypt hash."""
    try:
        password_bytes = plain_password.encode("utf-8")
        hash_bytes = hashed_password.encode("utf-8")
        return bcrypt.checkpw(password_bytes, hash_bytes)
    except Exception:
        return False


def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    # Note: Passwords > 72 bytes are rejected at the API schema level
    password_bytes = password.encode("utf-8")
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode("utf-8")


def create_access_token(
    data: dict[str, Any],
    settings: Settings,
    expires_delta: timedelta | None = None,
) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(UTC) + expires_delta
    else:
        expire = datetime.now(UTC) + timedelta(minutes=settings.access_token_expire_minutes)
    to_encode.update({"exp": expire, "type": "access"})
    encoded_jwt = jwt.encode(to_encode, settings.secret_key, algorithm="HS256")
    return encoded_jwt


def create_refresh_token(
    data: dict[str, Any],
    settings: Settings,
    expires_delta: timedelta | None = None,
) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(UTC) + expires_delta
    else:
        expire = datetime.now(UTC) + timedelta(days=settings.refresh_token_expire_days)
    # jti ensures every rotated refresh token is byte-distinct even when
    # issued within the same second, and gives us a handle for future
    # server-side revocation.
    to_encode.update({"exp": expire, "type": "refresh", "jti": uuid.uuid4().hex})
    encoded_jwt = jwt.encode(to_encode, settings.secret_key, algorithm="HS256")
    return encoded_jwt


def create_microapps_panel_token(email: str, slug: str, settings: Settings) -> str:
    """Short-lived token for the micro-apps panel reverse proxy.

    Uses a dedicated ``type`` claim so it can never authenticate a normal API
    request (``get_current_user`` only accepts type=access), and vice versa —
    an access token pasted into the proxy is rejected there.
    """
    expire = datetime.now(UTC) + timedelta(hours=12)
    payload = {"sub": email, "slug": slug, "type": "microapps-panel", "exp": expire}
    return jwt.encode(payload, settings.secret_key, algorithm="HS256")


def verify_microapps_panel_token(token: str, settings: Settings) -> str | None:
    """Return the workspace slug for a valid panel token, else None."""
    payload = decode_token(token, settings)
    if payload is None or payload.get("type") != "microapps-panel":
        return None
    return payload.get("slug")


def decode_token(token: str, settings: Settings) -> dict[str, Any] | None:
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=["HS256"])
        return payload
    except PyJWTError:
        return None


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    settings: Settings = Depends(get_settings),
) -> dict[str, Any]:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    payload = decode_token(credentials.credentials, settings)
    if payload is None:
        raise credentials_exception

    # Refresh tokens must never authenticate a normal API request.
    # Tokens issued before the type claim existed are treated as access tokens
    # for backwards compatibility with already-issued sessions.
    token_type = payload.get("type", "access")
    if token_type != "access":
        raise credentials_exception

    email: str = payload.get("sub")
    if email is None:
        raise credentials_exception

    return {"email": email, "token_payload": payload}


async def get_current_admin_user(
    current_user: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    """Require the current user to be an admin.

    Performs a DB lookup to check the ``is_admin`` flag. Raises 403 if the
    user is missing or not an admin. Returns the same dict as
    ``get_current_user`` with ``is_admin=True`` added.
    """
    from app.db.session import async_session_maker
    from app.services.user_service import UserService

    async with async_session_maker() as db:
        svc = UserService(db)
        user = await svc.get_by_email(current_user["email"])

    if user is None or not getattr(user, "is_admin", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin privileges required",
        )

    return {**current_user, "is_admin": True}
