from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.security import (
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.db.session import get_db
from app.schemas.auth import LoginRequest, TokenResponse
from app.schemas.user import UserCreate, UserOut
from app.services.user_service import UserService

router = APIRouter()


def get_user_service(db: Annotated[AsyncSession, Depends(get_db)]) -> UserService:
    return UserService(db)


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

    return UserOut(email=email, full_name=user_data.full_name, created_at=user.created_at)


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

    access_token = create_access_token(data={"sub": email}, settings=settings)
    return TokenResponse(access_token=access_token)


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

    return UserOut(email=user.email, full_name=user.full_name, created_at=user.created_at)
