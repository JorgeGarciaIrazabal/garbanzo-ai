from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.schemas.auth import LoginRequest, RefreshRequest, TokenResponse
from app.schemas.user import PasswordUpdate, UserCreate, UserOut, UserUpdate
from app.services.user_service import UserService

router = APIRouter()


def get_user_service(db: Annotated[AsyncSession, Depends(get_db)]) -> UserService:
    return UserService(db)


def _to_user_out(user: Any) -> UserOut:
    return UserOut(
        email=user.email,
        full_name=user.full_name,
        created_at=user.created_at,
        is_admin=getattr(user, "is_admin", False),
        is_disabled=getattr(user, "is_disabled", False),
        default_model=getattr(user, "default_model", None),
    )


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def register(
    user_data: UserCreate,
    users: Annotated[UserService, Depends(get_user_service)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> UserOut:
    email = user_data.email.lower()
    existing = await users.get_by_email(email)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    user = await users.create(
        email=email,
        hashed_password=hash_password(user_data.password),
        full_name=user_data.full_name,
    )

    return _to_user_out(user)


@router.post("/login", response_model=TokenResponse)
async def login(
    login_data: LoginRequest,
    users: Annotated[UserService, Depends(get_user_service)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> TokenResponse:
    email = login_data.email.lower()
    user = await users.get_by_email(email)
    if not user or not verify_password(login_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Already-issued tokens remain valid — disabled-user check is only applied at login.
    if getattr(user, "is_disabled", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account disabled",
        )

    access_token = create_access_token(data={"sub": email}, settings=settings)
    refresh_token = create_refresh_token(data={"sub": email}, settings=settings)
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    payload: RefreshRequest,
    users: Annotated[UserService, Depends(get_user_service)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> TokenResponse:
    """Exchange a refresh token for a new access+refresh token pair.

    Refresh tokens are rotated on every call so a leaked token is usable
    only until the next legitimate refresh.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired refresh token",
        headers={"WWW-Authenticate": "Bearer"},
    )

    decoded = decode_token(payload.refresh_token, settings)
    if decoded is None or decoded.get("type") != "refresh":
        raise credentials_exception

    email = decoded.get("sub")
    if not email:
        raise credentials_exception

    user = await users.get_by_email(email)
    if user is None or getattr(user, "is_disabled", False):
        raise credentials_exception

    access_token = create_access_token(data={"sub": email}, settings=settings)
    new_refresh_token = create_refresh_token(data={"sub": email}, settings=settings)
    return TokenResponse(access_token=access_token, refresh_token=new_refresh_token)


@router.get("/me", response_model=UserOut)
async def get_me(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    users: Annotated[UserService, Depends(get_user_service)],
) -> UserOut:
    user = await users.get_by_email(current_user["email"])
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return _to_user_out(user)


@router.patch("/me", response_model=UserOut)
async def update_me(
    payload: UserUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    users: Annotated[UserService, Depends(get_user_service)],
) -> UserOut:
    """Partial update of the current user's profile.

    Email changes propagate through ON UPDATE CASCADE. The existing JWT is
    bound to the old email and will stop working after a successful change —
    clients must re-authenticate.
    """
    user = await users.get_by_email(current_user["email"])
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    raw = payload.model_dump(exclude_unset=True)

    new_email: str | None = None
    update_email = "email" in raw
    if update_email:
        new_email = (raw["email"] or "").lower().strip() or None
        if not new_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email cannot be empty",
            )
        if new_email != user.email:
            taken = await users.get_by_email(new_email)
            if taken is not None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Email already registered",
                )

    await users.update_profile(
        user,
        full_name=raw.get("full_name"),
        email=new_email,
        default_model=raw.get("default_model"),
        update_full_name="full_name" in raw,
        update_email=update_email,
        update_default_model="default_model" in raw,
    )

    return _to_user_out(user)


@router.post("/me/password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    payload: PasswordUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    users: Annotated[UserService, Depends(get_user_service)],
) -> None:
    user = await users.get_by_email(current_user["email"])
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    if not verify_password(payload.current_password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect",
        )

    await users.update_password(user, hash_password(payload.new_password))
