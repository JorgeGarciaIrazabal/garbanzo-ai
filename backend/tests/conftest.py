"""Shared fixtures for backend tests."""

import pytest
import pytest_asyncio
from sqlalchemy import JSON
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.db.base import Base
from app.models.conversation import Conversation  # noqa: F401 — register model
from app.models.mcp_server import MCPServer  # noqa: F401 — register model
from app.models.memory import UserMemory  # noqa: F401 — register model
from app.models.message import Message  # noqa: F401 — register model
from app.models.user import User  # noqa: F401 — register model

# Use in-memory SQLite for tests (no PostgreSQL required).
TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"


# Map PostgreSQL JSONB → generic JSON so SQLite can handle it.
JSONB_TO_JSON = {JSONB: JSON}


@pytest.fixture()
def settings() -> Settings:
    """Return a ``Settings`` instance suitable for testing."""
    return Settings(
        secret_key="test-secret-key-do-not-use-in-prod",
        database_url=TEST_DATABASE_URL,
        access_token_expire_minutes=30,
    )


@pytest_asyncio.fixture()
async def db_session():
    """Yield an ``AsyncSession`` backed by an in-memory SQLite database.

    Tables are created fresh for every test so tests stay isolated.
    """
    engine = create_async_engine(TEST_DATABASE_URL, echo=False)

    # Temporarily swap JSONB columns to JSON for table creation.
    _patch_jsonb_columns()

    # Import all models to ensure tables are registered
    import app.models.memory  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_maker = async_sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autocommit=False,
        autoflush=False,
    )

    async with session_maker() as session:
        # Seed a test user so that conversation FK constraints pass.
        from app.core.security import hash_password

        user = User(
            email="test@example.com",
            hashed_password=hash_password("password123"),
        )
        session.add(user)
        await session.commit()

        yield session

    # Clean up any remaining references before disposal
    _unpatch_jsonb_columns()


@pytest_asyncio.fixture()
async def test_user_email(db_session: AsyncSession) -> str:
    """Return the test user email."""
    return "test@example.com"


@pytest_asyncio.fixture()
async def test_conversation(db_session: AsyncSession, test_user_email: str):
    """Create and return a test conversation."""
    import uuid

    conv = Conversation(
        id=str(uuid.uuid4()),
        user_id=test_user_email,
        title="Test Conversation",
        model="llama3.2",
    )
    db_session.add(conv)
    await db_session.commit()
    await db_session.refresh(conv)
    return conv


# ---------------------------------------------------------------------------
# JSONB → JSON patching helpers
# ---------------------------------------------------------------------------
_original_types: dict[str, type] = {}


def _patch_jsonb_columns():
    """Replace JSONB column types with JSON across all mapped tables."""
    for table in Base.metadata.tables.values():
        for col in table.columns:
            if isinstance(col.type, JSONB):
                key = f"{table.name}.{col.name}"
                _original_types[key] = col.type
                col.type = JSON()


def _unpatch_jsonb_columns():
    """Restore original JSONB types."""
    for table in Base.metadata.tables.values():
        for col in table.columns:
            key = f"{table.name}.{col.name}"
            if key in _original_types:
                col.type = _original_types.pop(key)
