"""Integration tests for /api/v1/system-prompts endpoints."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.services.system_prompt_service import SystemPromptService

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _install_overrides(db_session, email: str = "test@example.com"):
    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": email, "token_payload": {}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_current_user, None)


async def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def test_list_templates_empty(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get("/api/v1/system-prompts/templates")
        assert resp.status_code == 200
        assert resp.json() == []
    finally:
        _clear_overrides()


async def test_create_and_list_template(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.post(
                "/api/v1/system-prompts/templates",
                json={
                    "name": "Test",
                    "content": "You are helpful.",
                    "description": "A test prompt",
                },
            )
            assert resp.status_code == 201
            created = resp.json()
            assert created["name"] == "Test"

            listed = await c.get("/api/v1/system-prompts/templates")
            names = {t["name"] for t in listed.json()}
            assert "Test" in names
    finally:
        _clear_overrides()


async def test_update_template(db_session):
    svc = SystemPromptService(db_session)
    tpl = await svc.create_template(
        user_id="test@example.com", name="old", content="c"
    )

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.patch(
                f"/api/v1/system-prompts/templates/{tpl.id}",
                json={"name": "new"},
            )
        assert resp.status_code == 200
        assert resp.json()["name"] == "new"
    finally:
        _clear_overrides()


async def test_update_missing_404(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.patch(
                "/api/v1/system-prompts/templates/missing",
                json={"name": "x"},
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_delete_template(db_session):
    svc = SystemPromptService(db_session)
    tpl = await svc.create_template(
        user_id="test@example.com", name="trash", content="c"
    )

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.delete(f"/api/v1/system-prompts/templates/{tpl.id}")
        assert resp.status_code == 204
    finally:
        _clear_overrides()


async def test_user_default_get_returns_none_initially(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get("/api/v1/system-prompts/user-default")
        assert resp.status_code == 200
        assert resp.json() == {"default_system_prompt": None}
    finally:
        _clear_overrides()


async def test_user_default_set_and_clear(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.put(
                "/api/v1/system-prompts/user-default",
                json={"default_system_prompt": "Be brief."},
            )
            assert resp.status_code == 200
            assert resp.json()["default_system_prompt"] == "Be brief."

            # Clearing sends empty-ish string; endpoint normalizes to None.
            resp = await c.put(
                "/api/v1/system-prompts/user-default",
                json={"default_system_prompt": "   "},
            )
            assert resp.status_code == 200
            assert resp.json()["default_system_prompt"] is None
    finally:
        _clear_overrides()
