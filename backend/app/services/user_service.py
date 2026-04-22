"""Service for user lookup and profile mutations."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


class UserService:
    """Thin wrapper over user queries, removing duplication from auth endpoints."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_email(self, email: str) -> User | None:
        result = await self.db.execute(select(User).where(User.email == email))
        return result.scalar_one_or_none()

    async def create(self, email: str, hashed_password: str, full_name: str | None = None) -> User:
        user = User(email=email, hashed_password=hashed_password, full_name=full_name)
        self.db.add(user)
        await self.db.flush()
        return user

    async def update_profile(
        self,
        user: User,
        *,
        full_name: str | None = None,
        email: str | None = None,
        default_model: str | None = None,
        update_full_name: bool = False,
        update_email: bool = False,
        update_default_model: bool = False,
    ) -> User:
        """Apply a partial update to the authenticated user's profile.

        Booleans disambiguate "absent" from "set to None" for nullable fields.
        Relies on ON UPDATE CASCADE for FKs so email changes propagate to all
        referencing tables (conversations, memories, etc.) within the same tx.
        """
        if update_full_name:
            user.full_name = full_name
        if update_default_model:
            user.default_model = default_model
        if update_email and email is not None and email != user.email:
            user.email = email
        await self.db.flush()
        return user

    async def update_password(self, user: User, hashed_password: str) -> None:
        user.hashed_password = hashed_password
        await self.db.flush()
