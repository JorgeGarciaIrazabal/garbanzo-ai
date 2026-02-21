from datetime import datetime
from typing import Annotated, Any, Dict

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import Settings, get_settings
from app.core.security import (
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.schemas.auth import LoginRequest, TokenResponse
from app.schemas.user import UserCreate, UserOut

router = APIRouter()

# Simple in-memory user store (replace with database in production)
# Format: {email: {"hashed_password": str, "full_name": str, "created_at": datetime}}
users_db: Dict[str, Dict[str, Any]] = {}


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def register(
    user_data: UserCreate,
    settings: Annotated[Settings, Depends(get_settings)],
) -> UserOut:
    email = user_data.email.lower()
    if email in users_db:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    now = datetime.utcnow()
    user_dict = {
        "email": email,
        "hashed_password": hash_password(user_data.password),
        "full_name": user_data.full_name,
        "created_at": now,
    }
    users_db[email] = user_dict

    return UserOut(
        email=email,
        full_name=user_data.full_name,
        created_at=now,
    )


@router.post("/login", response_model=TokenResponse)
async def login(
    login_data: LoginRequest,
    settings: Annotated[Settings, Depends(get_settings)],
) -> TokenResponse:
    email = login_data.email.lower()
    user = users_db.get(email)
    if not user or not verify_password(login_data.password, user["hashed_password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token = create_access_token(
        data={"sub": email},
        settings=settings,
    )
    return TokenResponse(access_token=access_token)


@router.get("/me", response_model=UserOut)
async def get_me(
    current_user: Annotated[Dict[str, Any], Depends(get_current_user)],
) -> UserOut:
    email = current_user["email"]
    user = users_db.get(email)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return UserOut(
        email=email,
        full_name=user.get("full_name"),
        created_at=user["created_at"],
    )
