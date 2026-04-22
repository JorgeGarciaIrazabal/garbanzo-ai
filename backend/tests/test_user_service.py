"""Tests for UserService."""

import pytest

from app.core.security import hash_password
from app.services.user_service import UserService

pytestmark = pytest.mark.asyncio


async def test_get_by_email_seeded_user(db_session):
    svc = UserService(db_session)
    user = await svc.get_by_email("test@example.com")
    assert user is not None
    assert user.email == "test@example.com"


async def test_get_by_email_missing(db_session):
    svc = UserService(db_session)
    assert await svc.get_by_email("nope@example.com") is None


async def test_create_adds_user(db_session):
    svc = UserService(db_session)
    created = await svc.create(
        email="new@example.com",
        hashed_password=hash_password("pw"),
        full_name="New User",
    )
    assert created.email == "new@example.com"
    assert created.full_name == "New User"
    # Commit so it shows up in a follow-up query.
    await db_session.commit()

    fetched = await svc.get_by_email("new@example.com")
    assert fetched is not None
    assert fetched.full_name == "New User"


async def test_create_without_name(db_session):
    svc = UserService(db_session)
    created = await svc.create(
        email="noname@example.com",
        hashed_password=hash_password("pw"),
    )
    assert created.full_name is None
