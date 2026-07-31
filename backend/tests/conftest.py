"""Shared fixtures for backend tests.

Each test runs against a fresh in-memory SQLite database. The module-level
``engine`` and ``async_session_maker`` in ``app.db.session`` are swapped to
this per-test test engine *before each test*, so every code path — whether it
uses the ``get_db`` FastAPI dependency or imports ``async_session_maker``
directly (e.g. ``get_current_admin_user``, background auto-titling,
push-on-disconnect) — sees the same in-memory SQLite DB instead of the real
PostgreSQL ``DATABASE_URL``. No test ever touches the real DB; a fresh CI
Postgres with no tables behaves identically to a dev machine with running
migrations.

``StaticPool`` makes all connections within one engine share a single
underlying in-memory DB, so the ``db_session`` fixture and
``async_session_maker`` users see the same data. A brand-new engine is built
per test (so pytest-asyncio's per-test event loop owns it cleanly) and
disposed at teardown.
"""

from collections.abc import AsyncGenerator

import pytest
import pytest_asyncio
from pgvector.sqlalchemy import Vector
from sqlalchemy import JSON, event
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db import session as db_session_module
from app.db.base import Base
from app.models.available_model import AvailableModel  # noqa: F401 — register model
from app.models.conversation import Conversation  # noqa: F401 — register model
from app.models.device_token import DeviceToken  # noqa: F401 — register model
from app.models.friendship import Friendship  # noqa: F401 — register model
from app.models.knowledge_base import (  # noqa: F401 — register models
    KnowledgeChunk,
    KnowledgeDocument,
)
from app.models.mcp_server import MCPServer  # noqa: F401 — register model
from app.models.memory import UserMemory  # noqa: F401 — register model
from app.models.message import Message  # noqa: F401 — register model
from app.models.notification import (  # noqa: F401 — register models
    Notification,
    NotificationPreferences,
)
from app.models.report import Report  # noqa: F401 — register model
from app.models.room import (  # noqa: F401 — register models
    Room,
    RoomAgent,
    RoomAudioNote,
    RoomMember,
    RoomMessage,
)
from app.models.scheduled_action import ScheduledAction  # noqa: F401 — register model
from app.models.shared_item import SharedItem  # noqa: F401 — register model
from app.models.style import Style  # noqa: F401 — register model
from app.models.system_prompt import SystemPromptTemplate  # noqa: F401 — register model
from app.models.user import User  # noqa: F401 — register model

TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"
JSONB_TO_JSON = {JSONB: JSON}

# ---------------------------------------------------------------------------
# JSONB → JSON patching (run once at import, before the first test starts)
# ---------------------------------------------------------------------------
_original_types: dict[str, type] = {}


def _patch_jsonb_columns() -> None:
    """Replace PG-specific column types with SQLite-compatible ones in place."""
    for table in Base.metadata.tables.values():
        for col in table.columns:
            if isinstance(col.type, Vector):
                key = f"{table.name}.{col.name}"
                _original_types[key] = col.type
                # none_as_null mirrors pgvector semantics: a Python None must
                # become SQL NULL (so `IS NULL` matches), not JSON 'null'.
                col.type = JSON(none_as_null=True)
            elif isinstance(col.type, JSONB):
                key = f"{table.name}.{col.name}"
                _original_types[key] = col.type
                col.type = JSON()


_patch_jsonb_columns()


@pytest.fixture()
def settings() -> Settings:
    """Return a ``Settings`` instance suitable for testing."""
    return Settings(
        secret_key="test-secret-key-do-not-use-in-prod",
        database_url=TEST_DATABASE_URL,
        access_token_expire_minutes=30,
    )


def _build_test_engine():
    """Create a fresh in-memory SQLite engine for a single test's event loop.

    ``StaticPool`` shares one underlying in-memory DB across all connections
    opened from this engine, so ``async_session_maker`` users (which open
    their own sessions) see the same rows ``db_session`` commits. Because the
    engine is created fresh per test on that test's own event loop and
    disposed at teardown, there's no cross-loop connection reuse (which would
    otherwise surface as silent stale state, e.g. FK CASCADE pragmas being
    lost between tests).
    """
    return create_async_engine(
        TEST_DATABASE_URL,
        echo=False,
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )


def _enable_fk_pragma(engine) -> None:
    """Enable SQLite foreign key enforcement (per-connection) for an engine.

    SQLite ignores FK constraint actions (CASCADE / SET NULL) unless
    ``PRAGMA foreign_keys=ON`` is set per-connection — it's off by default.
    Postgres (dev/prod) always enforces them, so this makes the in-memory test
    DB match: models relying on ON DELETE SET NULL (e.g.
    Style.system_prompt_template_id) would otherwise silently keep a dangling
    id in tests.
    """

    @event.listens_for(engine.sync_engine, "connect")
    def _enable_sqlite_fk(dbapi_connection, connection_record):  # noqa: ARG001
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


@pytest_asyncio.fixture()
async def db_session() -> AsyncGenerator[AsyncSession]:
    """Yield an ``AsyncSession`` backed by a per-test in-memory SQLite DB.

    Tables are created fresh for every test, and the module-level
    ``app.db.session.engine`` / ``async_session_maker`` are swapped to this
    test's engine so code paths that bypass ``get_db`` (e.g.
    ``get_current_admin_user``, background auto-titling) hit the same
    in-memory test DB rather than the real PostgreSQL ``DATABASE_URL``.
    A test user is seeded so conversation FK constraints pass.
    """
    engine = _build_test_engine()
    _enable_fk_pragma(engine)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_maker = async_sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autocommit=False,
        autoflush=False,
    )

    # Swap the module-level engine + session maker in place so any code path
    # that has imported (or will import) them from ``app.db.session`` resolves
    # to this test's SQLite engine. ``from x import async_session_maker``
    # captured at a module's import time sees the OLD reference — those
    # callers must be patched individually (see existing per-test monkeypatch
    # patterns in tests/* for examples). Importantly, ``app.db.session.get_db``
    # itself looks the name up at call time, so it picks up the swap.
    db_session_module.engine = engine
    db_session_module.async_session_maker = session_maker

    async with session_maker() as session:
        from app.core.security import hash_password

        user = User(
            email="test@example.com",
            hashed_password=hash_password("password123"),
        )
        session.add(user)
        await session.commit()

        yield session

    # Dispose while the test's event loop is still alive so aiosqlite's
    # background connection thread shuts down cleanly (prevents
    # "Event loop is closed" PytestUnhandledThreadExceptionWarning).
    await engine.dispose()


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
