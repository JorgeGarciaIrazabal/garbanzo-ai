"""Endpoint tests for sharing styles / prompt templates with friends (Idea 9)."""

from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.user import User

pytestmark = pytest.mark.asyncio

_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)

ME = "test@example.com"  # seeded by conftest
ANA = "ana@example.com"


def _install(db_session, viewer: str):
    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": viewer, "token_payload": {}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user


def _clear():
    for dep in (get_db, get_settings, get_current_user):
        app.dependency_overrides.pop(dep, None)


async def _request(db_session, viewer: str, method: str, url: str, **kw) -> Any:
    _install(db_session, viewer)
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            return await getattr(c, method)(url, **kw)
    finally:
        _clear()


async def _befriend(db_session, email: str) -> None:
    db_session.add(User(email=email, hashed_password=hash_password("pw")))
    await db_session.commit()
    resp = await _request(db_session, email, "post", "/api/v1/friends/requests", json={"email": ME})
    request_id = resp.json()["id"]
    await _request(db_session, ME, "post", f"/api/v1/friends/requests/{request_id}/accept")


async def _create_template(db_session, owner: str, name="Concise", content="Be brief.") -> str:
    resp = await _request(
        db_session,
        owner,
        "post",
        "/api/v1/system-prompts/templates",
        json={"name": name, "description": "short answers", "content": content},
    )
    assert resp.status_code in (200, 201), resp.text
    return resp.json()["id"]


async def _create_style(db_session, owner: str, template_id: str | None = None) -> str:
    body: dict[str, Any] = {"name": "Deep Work", "model_id": "llama3:8b", "thinking_level": "high"}
    if template_id:
        body["system_prompt_template_id"] = template_id
    resp = await _request(db_session, owner, "post", "/api/v1/styles", json=body)
    assert resp.status_code in (200, 201), resp.text
    return resp.json()["id"]


class TestShareCreation:
    async def test_share_prompt_with_friend(self, db_session):
        await _befriend(db_session, ANA)
        template_id = await _create_template(db_session, ME)

        resp = await _request(
            db_session,
            ME,
            "post",
            "/api/v1/shares",
            json={"kind": "prompt", "item_id": template_id, "recipient_email": ANA},
        )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        assert body["kind"] == "prompt"
        assert body["payload"]["content"] == "Be brief."

        incoming = (await _request(db_session, ANA, "get", "/api/v1/shares/incoming")).json()
        assert len(incoming) == 1
        assert incoming[0]["sender_email"] == ME

    async def test_share_requires_friendship(self, db_session):
        db_session.add(User(email=ANA, hashed_password=hash_password("pw")))
        await db_session.commit()
        template_id = await _create_template(db_session, ME)

        resp = await _request(
            db_session,
            ME,
            "post",
            "/api/v1/shares",
            json={"kind": "prompt", "item_id": template_id, "recipient_email": ANA},
        )
        assert resp.status_code == 400

    async def test_cannot_share_someone_elses_item(self, db_session):
        await _befriend(db_session, ANA)
        template_id = await _create_template(db_session, ANA)

        resp = await _request(
            db_session,
            ME,
            "post",
            "/api/v1/shares",
            json={"kind": "prompt", "item_id": template_id, "recipient_email": ANA},
        )
        assert resp.status_code == 400

    async def test_share_notifies_recipient(self, db_session):
        from app.services.notification_service import NotificationService

        await _befriend(db_session, ANA)
        template_id = await _create_template(db_session, ME)
        await _request(
            db_session,
            ME,
            "post",
            "/api/v1/shares",
            json={"kind": "prompt", "item_id": template_id, "recipient_email": ANA},
        )

        notes = await NotificationService(db_session).list_for_user(ANA)
        assert any("shared" in n.body for n in notes)


class TestShareAccept:
    async def _share_prompt(self, db_session) -> str:
        await _befriend(db_session, ANA)
        template_id = await _create_template(db_session, ME)
        resp = await _request(
            db_session,
            ME,
            "post",
            "/api/v1/shares",
            json={"kind": "prompt", "item_id": template_id, "recipient_email": ANA},
        )
        return resp.json()["id"]

    async def test_accept_creates_copy_and_clears_share(self, db_session):
        share_id = await self._share_prompt(db_session)

        resp = await _request(db_session, ANA, "post", f"/api/v1/shares/{share_id}/accept")
        assert resp.status_code == 200, resp.text
        created_id = resp.json()["created_id"]

        # Recipient now owns a template with the shared content.
        templates = (
            await _request(db_session, ANA, "get", "/api/v1/system-prompts/templates")
        ).json()
        mine = [t for t in templates if t["id"] == created_id]
        assert mine and mine[0]["content"] == "Be brief."

        assert (await _request(db_session, ANA, "get", "/api/v1/shares/incoming")).json() == []

    async def test_snapshot_survives_sender_edits(self, db_session):
        """Copy-on-accept: the sender deleting the original after sharing
        must not affect what the recipient accepts."""
        await _befriend(db_session, ANA)
        template_id = await _create_template(db_session, ME)
        share_id = (
            await _request(
                db_session,
                ME,
                "post",
                "/api/v1/shares",
                json={"kind": "prompt", "item_id": template_id, "recipient_email": ANA},
            )
        ).json()["id"]

        await _request(db_session, ME, "delete", f"/api/v1/system-prompts/templates/{template_id}")

        resp = await _request(db_session, ANA, "post", f"/api/v1/shares/{share_id}/accept")
        assert resp.status_code == 200, resp.text

    async def test_accept_style_recreates_prompt_too(self, db_session):
        await _befriend(db_session, ANA)
        template_id = await _create_template(db_session, ME, name="Persona", content="Act X.")
        style_id = await _create_style(db_session, ME, template_id)
        share_id = (
            await _request(
                db_session,
                ME,
                "post",
                "/api/v1/shares",
                json={"kind": "style", "item_id": style_id, "recipient_email": ANA},
            )
        ).json()["id"]

        resp = await _request(db_session, ANA, "post", f"/api/v1/shares/{share_id}/accept")
        assert resp.status_code == 200, resp.text
        created_id = resp.json()["created_id"]

        styles = (await _request(db_session, ANA, "get", "/api/v1/styles")).json()
        mine = [s for s in styles if s["id"] == created_id]
        assert mine, styles
        assert mine[0]["name"] == "Deep Work"
        assert mine[0]["is_default"] is False
        assert mine[0]["system_prompt_template_id"] is not None

        templates = (
            await _request(db_session, ANA, "get", "/api/v1/system-prompts/templates")
        ).json()
        assert any(t["name"] == "Persona" and t["content"] == "Act X." for t in templates)

    async def test_only_recipient_can_accept_or_decline(self, db_session):
        share_id = await self._share_prompt(db_session)
        assert (
            await _request(db_session, ME, "post", f"/api/v1/shares/{share_id}/accept")
        ).status_code == 404
        assert (
            await _request(db_session, ME, "post", f"/api/v1/shares/{share_id}/decline")
        ).status_code == 404

    async def test_decline_deletes_without_copy(self, db_session):
        share_id = await self._share_prompt(db_session)
        resp = await _request(db_session, ANA, "post", f"/api/v1/shares/{share_id}/decline")
        assert resp.status_code == 204
        assert (await _request(db_session, ANA, "get", "/api/v1/shares/incoming")).json() == []
