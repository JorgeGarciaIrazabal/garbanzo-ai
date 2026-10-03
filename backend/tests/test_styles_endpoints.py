"""Integration tests for /api/v1/styles endpoints (Idea 2, "Styles" —
subtask 2). Mirrors ``test_scheduled_actions_endpoints.py`` in structure.
"""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import create_access_token, get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.system_prompt import SystemPromptTemplate
from app.models.user import User
from app.services.style_service import StyleService
from app.services.system_prompt_service import SystemPromptService

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _token(email: str) -> str:
    return create_access_token({"sub": email}, _TEST_SETTINGS)


def _install_overrides(db_session, email: str = "test@example.com"):
    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": email, "token_payload": {"sub": email}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_settings, None)
    app.dependency_overrides.pop(get_current_user, None)


async def _client() -> AsyncClient:
    transport = ASGITransport(app=app)
    return AsyncClient(transport=transport, base_url="http://test")


def _auth(email: str = "test@example.com") -> dict[str, str]:
    return {"Authorization": f"Bearer {_token(email)}"}


class TestInlineInstructions:
    async def test_create_then_edit_instructions_in_one_request(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as client:
                created = await client.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={
                        "name": "Coach",
                        "model_id": "qwen3",
                        "system_prompt_content": "Ask questions.",
                        "is_default": True,
                    },
                )
                assert created.status_code == 201, created.text
                body = created.json()
                assert body["is_default"] is True
                assert "system_prompt_content" not in body
                original_id = body["system_prompt_template_id"]
                original = await db_session.get(SystemPromptTemplate, original_id)
                assert original.content == "Ask questions."
                assert original.user_id == "test@example.com"
                assert original.name == "Coach"
                changed = await client.patch(
                    f"/api/v1/styles/{body['id']}",
                    headers=_auth(),
                    json={"name": "New coach", "system_prompt_content": "Give examples."},
                )
                assert changed.status_code == 200, changed.text
                replacement_id = changed.json()["system_prompt_template_id"]
                assert replacement_id != original_id
                replacement = await db_session.get(SystemPromptTemplate, replacement_id)
                assert replacement.name == "New coach"
                assert replacement.content == "Give examples."
                await db_session.refresh(original)
                assert original.content == "Ask questions."
                assert changed.json()["is_default"] is True
        finally:
            _clear_overrides()

    @pytest.mark.parametrize("content", [None, ""])
    async def test_patch_empty_or_null_clears_instructions(self, db_session, content):
        style = await StyleService(db_session).create(
            user_id="test@example.com",
            name="Clear",
            model_id="qwen3",
            system_prompt_content="Instructions",
        )
        _install_overrides(db_session)
        try:
            async with await _client() as client:
                response = await client.patch(
                    f"/api/v1/styles/{style.id}",
                    headers=_auth(),
                    json={"system_prompt_content": content},
                )
            assert response.status_code == 200, response.text
            assert response.json()["system_prompt_template_id"] is None
        finally:
            _clear_overrides()

    @pytest.mark.parametrize("method", ["post", "patch"])
    @pytest.mark.parametrize("template_id", [None, "some-template"])
    async def test_explicit_prompt_sources_conflict_422(self, db_session, method, template_id):
        _install_overrides(db_session)
        try:
            async with await _client() as client:
                response = await client.request(
                    method,
                    "/api/v1/styles" if method == "post" else "/api/v1/styles/missing",
                    headers=_auth(),
                    json={
                        "name": "Conflict",
                        "system_prompt_template_id": template_id,
                        "system_prompt_content": "Instructions",
                    },
                )
            assert response.status_code == 422, response.text
        finally:
            _clear_overrides()

    @pytest.mark.parametrize("content", [42, ["instructions"]])
    async def test_content_requires_string_422(self, db_session, content):
        _install_overrides(db_session)
        try:
            async with await _client() as client:
                response = await client.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={"name": "Invalid", "system_prompt_content": content},
                )
            assert response.status_code == 422, response.text
        finally:
            _clear_overrides()

    async def test_inline_content_cannot_modify_builtin_403(self, db_session):
        await SystemPromptService(db_session).seed_builtin_templates()
        service = StyleService(db_session)
        await service.seed_builtin_styles()
        builtin = next(iter(await service.list_for_user("test@example.com")))
        _install_overrides(db_session)
        try:
            async with await _client() as client:
                response = await client.patch(
                    f"/api/v1/styles/{builtin.id}",
                    headers=_auth(),
                    json={"system_prompt_content": None},
                )
            assert response.status_code == 403, response.text
        finally:
            _clear_overrides()


class TestCreate:
    async def test_create_minimal_201(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={"name": "Quick Answers", "model_id": "llama3.2"},
                )
            assert resp.status_code == 201, resp.text
            body = resp.json()
            assert body["name"] == "Quick Answers"
            assert body["model_id"] == "llama3.2"
            assert body["thinking_level"] is None
            assert body["system_prompt_template_id"] is None
            assert body["is_default"] is False
        finally:
            _clear_overrides()

    async def test_create_with_thinking_level_201(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={"name": "Deep Work", "model_id": "qwen3", "thinking_level": "high"},
                )
            assert resp.status_code == 201, resp.text
            assert resp.json()["thinking_level"] == "high"
        finally:
            _clear_overrides()

    async def test_create_rejects_invalid_thinking_level_422(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={"name": "x", "model_id": "llama3.2", "thinking_level": "bogus"},
                )
            assert resp.status_code == 422
        finally:
            _clear_overrides()

    async def test_create_missing_name_422(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={"model_id": "llama3.2"},
                )
            assert resp.status_code == 422
        finally:
            _clear_overrides()

    async def test_create_with_unknown_template_400(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={
                        "name": "x",
                        "model_id": "llama3.2",
                        "system_prompt_template_id": "does-not-exist",
                    },
                )
            assert resp.status_code == 400
        finally:
            _clear_overrides()

    async def test_second_default_unsets_first(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                first = await c.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={"name": "a", "model_id": "llama3.2", "is_default": True},
                )
                second = await c.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={"name": "b", "model_id": "llama3.2", "is_default": True},
                )
                refreshed = await c.get(f"/api/v1/styles/{first.json()['id']}", headers=_auth())
            assert refreshed.json()["is_default"] is False
            assert second.json()["is_default"] is True
        finally:
            _clear_overrides()


class TestList:
    async def test_list_returns_only_callers_styles(self, db_session):
        from app.services.style_service import StyleService

        svc = StyleService(db_session)
        await svc.create(user_id="test@example.com", name="mine", model_id="llama3.2")
        db_session.add(User(email="other@example.com", hashed_password=hash_password("x")))
        await db_session.commit()
        await svc.create(user_id="other@example.com", name="theirs", model_id="llama3.2")

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.get("/api/v1/styles", headers=_auth())
            assert resp.status_code == 200
            names = [s["name"] for s in resp.json()]
            assert names == ["mine"]
        finally:
            _clear_overrides()


class TestGet:
    async def test_get_existing(self, db_session):
        from app.services.style_service import StyleService

        svc = StyleService(db_session)
        style = await svc.create(user_id="test@example.com", name="x", model_id="llama3.2")

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.get(f"/api/v1/styles/{style.id}", headers=_auth())
            assert resp.status_code == 200
            assert resp.json()["id"] == style.id
        finally:
            _clear_overrides()

    async def test_get_missing_404(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.get("/api/v1/styles/missing", headers=_auth())
            assert resp.status_code == 404
        finally:
            _clear_overrides()

    async def test_get_other_users_style_404(self, db_session):
        from app.services.style_service import StyleService

        db_session.add(User(email="other@example.com", hashed_password=hash_password("x")))
        await db_session.commit()
        svc = StyleService(db_session)
        style = await svc.create(user_id="other@example.com", name="theirs", model_id="llama3.2")

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.get(f"/api/v1/styles/{style.id}", headers=_auth())
            assert resp.status_code == 404
        finally:
            _clear_overrides()


class TestPatch:
    async def test_update_name_and_model(self, db_session):
        from app.services.style_service import StyleService

        svc = StyleService(db_session)
        style = await svc.create(user_id="test@example.com", name="orig", model_id="llama3.2")

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    f"/api/v1/styles/{style.id}",
                    headers=_auth(),
                    json={"name": "renamed", "model_id": "qwen3"},
                )
            assert resp.status_code == 200
            body = resp.json()
            assert body["name"] == "renamed"
            assert body["model_id"] == "qwen3"
        finally:
            _clear_overrides()

    async def test_update_thinking_level_to_null_resets(self, db_session):
        from app.services.style_service import StyleService

        svc = StyleService(db_session)
        style = await svc.create(
            user_id="test@example.com", name="x", model_id="llama3.2", thinking_level="medium"
        )

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    f"/api/v1/styles/{style.id}",
                    headers=_auth(),
                    json={"thinking_level": None},
                )
            assert resp.status_code == 200
            assert resp.json()["thinking_level"] is None
        finally:
            _clear_overrides()

    async def test_update_omitted_thinking_level_leaves_unchanged(self, db_session):
        from app.services.style_service import StyleService

        svc = StyleService(db_session)
        style = await svc.create(
            user_id="test@example.com", name="x", model_id="llama3.2", thinking_level="medium"
        )

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    f"/api/v1/styles/{style.id}",
                    headers=_auth(),
                    json={"name": "renamed"},
                )
            assert resp.status_code == 200
            assert resp.json()["thinking_level"] == "medium"
        finally:
            _clear_overrides()

    async def test_update_rejects_invalid_thinking_level_422(self, db_session):
        from app.services.style_service import StyleService

        svc = StyleService(db_session)
        style = await svc.create(user_id="test@example.com", name="x", model_id="llama3.2")

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    f"/api/v1/styles/{style.id}",
                    headers=_auth(),
                    json={"thinking_level": "bogus"},
                )
            assert resp.status_code == 422
        finally:
            _clear_overrides()

    async def test_update_missing_404(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    "/api/v1/styles/missing",
                    headers=_auth(),
                    json={"name": "x"},
                )
            assert resp.status_code == 404
        finally:
            _clear_overrides()

    async def test_update_other_users_style_404(self, db_session):
        from app.services.style_service import StyleService

        db_session.add(User(email="other@example.com", hashed_password=hash_password("x")))
        await db_session.commit()
        svc = StyleService(db_session)
        style = await svc.create(user_id="other@example.com", name="theirs", model_id="llama3.2")

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    f"/api/v1/styles/{style.id}",
                    headers=_auth(),
                    json={"name": "hijacked"},
                )
            assert resp.status_code == 404
        finally:
            _clear_overrides()

    async def test_update_with_unknown_template_400(self, db_session):
        from app.services.style_service import StyleService

        svc = StyleService(db_session)
        style = await svc.create(user_id="test@example.com", name="x", model_id="llama3.2")

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    f"/api/v1/styles/{style.id}",
                    headers=_auth(),
                    json={"system_prompt_template_id": "does-not-exist"},
                )
            assert resp.status_code == 400
        finally:
            _clear_overrides()


class TestDelete:
    async def test_delete_existing_204(self, db_session):
        from app.services.style_service import StyleService

        svc = StyleService(db_session)
        style = await svc.create(user_id="test@example.com", name="x", model_id="llama3.2")

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.delete(f"/api/v1/styles/{style.id}", headers=_auth())
            assert resp.status_code == 204
        finally:
            _clear_overrides()

    async def test_delete_missing_404(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.delete("/api/v1/styles/missing", headers=_auth())
            assert resp.status_code == 404
        finally:
            _clear_overrides()

    async def test_delete_other_users_style_404(self, db_session):
        from app.services.style_service import StyleService

        db_session.add(User(email="other@example.com", hashed_password=hash_password("x")))
        await db_session.commit()
        svc = StyleService(db_session)
        style = await svc.create(user_id="other@example.com", name="theirs", model_id="llama3.2")

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.delete(f"/api/v1/styles/{style.id}", headers=_auth())
            assert resp.status_code == 404
        finally:
            _clear_overrides()


class TestTemplateReference:
    async def test_create_with_own_template_201(self, db_session):
        tpl = SystemPromptTemplate(
            id="tpl-1", user_id="test@example.com", name="mine", content="Be terse."
        )
        db_session.add(tpl)
        await db_session.commit()

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/styles",
                    headers=_auth(),
                    json={
                        "name": "x",
                        "model_id": "llama3.2",
                        "system_prompt_template_id": "tpl-1",
                    },
                )
            assert resp.status_code == 201, resp.text
            assert resp.json()["system_prompt_template_id"] == "tpl-1"
        finally:
            _clear_overrides()

    async def test_deleting_template_survives_as_null_reference(self, db_session):
        from app.services.style_service import StyleService

        tpl = SystemPromptTemplate(
            id="tpl-2", user_id="test@example.com", name="mine", content="Be terse."
        )
        db_session.add(tpl)
        await db_session.commit()
        svc = StyleService(db_session)
        style = await svc.create(
            user_id="test@example.com",
            name="Deep Work",
            model_id="qwen3",
            system_prompt_template_id="tpl-2",
        )

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                await c.delete("/api/v1/system-prompts/templates/tpl-2", headers=_auth())
                # All requests in this test share one session object (see
                # _install_overrides), which has expire_on_commit=False —
                # unlike separate production requests, it would otherwise
                # keep serving the pre-cascade in-memory Style attributes.
                # An explicit async-safe refresh stands in for what a fresh
                # per-request session would see cold.
                await db_session.refresh(style)
                resp = await c.get(f"/api/v1/styles/{style.id}", headers=_auth())
            assert resp.status_code == 200
            body = resp.json()
            assert body["system_prompt_template_id"] is None
            assert body["model_id"] == "qwen3"
        finally:
            _clear_overrides()


async def _seed_builtins(db_session):
    """Helper: run the built-in template then style seeding, mirroring startup."""
    from app.services.style_service import StyleService
    from app.services.system_prompt_service import SystemPromptService

    await SystemPromptService(db_session).seed_builtin_templates()
    await StyleService(db_session).seed_builtin_styles()


class TestBuiltinStyles:
    async def test_list_includes_builtins(self, db_session):
        await _seed_builtins(db_session)
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.get("/api/v1/styles", headers=_auth())
            assert resp.status_code == 200, resp.text
            body = resp.json()
            assert any(s["is_builtin"] for s in body)
            assert "Concise" in {s["name"] for s in body if s["is_builtin"]}
        finally:
            _clear_overrides()

    async def test_patch_builtin_returns_403(self, db_session):
        await _seed_builtins(db_session)
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                listed = await c.get("/api/v1/styles", headers=_auth())
                builtin = next(s for s in listed.json() if s["is_builtin"])
                resp = await c.patch(
                    f"/api/v1/styles/{builtin['id']}",
                    headers=_auth(),
                    json={"name": "hijacked"},
                )
            assert resp.status_code == 403
        finally:
            _clear_overrides()

    async def test_delete_builtin_returns_403(self, db_session):
        await _seed_builtins(db_session)
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                listed = await c.get("/api/v1/styles", headers=_auth())
                builtin = next(s for s in listed.json() if s["is_builtin"])
                resp = await c.delete(f"/api/v1/styles/{builtin['id']}", headers=_auth())
            assert resp.status_code == 403
        finally:
            _clear_overrides()
