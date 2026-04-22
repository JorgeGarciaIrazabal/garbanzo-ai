"""Integration tests for /api/v1/scheduled-actions endpoints."""

from datetime import UTC, datetime, timedelta
from unittest.mock import patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import create_access_token, get_current_user
from app.db.session import get_db
from app.main import app

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
    app.dependency_overrides.pop(get_current_user, None)


class _SchedulerStub:
    """No-op stand-ins so endpoint tests don't touch the real scheduler."""

    calls: list[tuple[str, str]] = []

    @classmethod
    def reset(cls):
        cls.calls.clear()

    @classmethod
    def register(cls, action):
        cls.calls.append(("register", action.id))

    @classmethod
    def unregister(cls, action_id):
        cls.calls.append(("unregister", action_id))


@pytest.fixture(autouse=True)
def _patch_scheduler():
    _SchedulerStub.reset()
    with (
        patch(
            "app.api.v1.endpoints.scheduled_actions.register_scheduled_action",
            side_effect=_SchedulerStub.register,
        ),
        patch(
            "app.api.v1.endpoints.scheduled_actions.unregister_scheduled_action",
            side_effect=_SchedulerStub.unregister,
        ),
    ):
        yield


async def _client():
    transport = ASGITransport(app=app)
    return AsyncClient(transport=transport, base_url="http://test")


class TestCreate:
    async def test_create_recurring_201(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/scheduled-actions",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                    json={
                        "prompt": "Daily ping",
                        "cron_expr": "0 9 * * *",
                        "title": "Morning",
                    },
                )
            assert resp.status_code == 201, resp.text
            body = resp.json()
            assert body["prompt"] == "Daily ping"
            assert body["cron_expr"] == "0 9 * * *"
            assert body["next_run"] is not None
            # Scheduler was invoked exactly once for this action.
            assert _SchedulerStub.calls[-1] == ("register", body["id"])
        finally:
            _clear_overrides()

    async def test_create_one_off_201(self, db_session):
        _install_overrides(db_session)
        future = (datetime.now(tz=UTC) + timedelta(days=1)).isoformat()
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/scheduled-actions",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                    json={"prompt": "Ping", "run_at": future},
                )
            assert resp.status_code == 201, resp.text
            body = resp.json()
            assert body["run_at"] is not None
            assert body["cron_expr"] is None
        finally:
            _clear_overrides()

    async def test_create_both_triggers_422(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/scheduled-actions",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                    json={
                        "prompt": "x",
                        "cron_expr": "0 9 * * *",
                        "run_at": datetime.now(tz=UTC).isoformat(),
                    },
                )
            assert resp.status_code == 422
        finally:
            _clear_overrides()

    async def test_create_neither_trigger_422(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/scheduled-actions",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                    json={"prompt": "x"},
                )
            assert resp.status_code == 422
        finally:
            _clear_overrides()

    async def test_create_invalid_cron_400(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/scheduled-actions",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                    json={"prompt": "x", "cron_expr": "nonsense"},
                )
            assert resp.status_code == 400
        finally:
            _clear_overrides()


class TestList:
    async def test_list_returns_only_callers_actions(self, db_session):
        # Seed one action for the test user via the service.
        from app.services.scheduled_action_service import ScheduledActionService

        svc = ScheduledActionService(db_session)
        await svc.create(
            user_id="test@example.com", prompt="mine", cron_expr="0 9 * * *"
        )
        # Seed an action for a different user — must not surface.
        from app.core.security import hash_password
        from app.models.user import User

        db_session.add(User(email="other@example.com", hashed_password=hash_password("x")))
        await db_session.commit()
        await svc.create(
            user_id="other@example.com", prompt="theirs", cron_expr="0 9 * * *"
        )

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.get(
                    "/api/v1/scheduled-actions",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                )
            assert resp.status_code == 200
            prompts = [a["prompt"] for a in resp.json()]
            assert prompts == ["mine"]
        finally:
            _clear_overrides()


class TestGet:
    async def test_get_existing(self, db_session):
        from app.services.scheduled_action_service import ScheduledActionService

        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id="test@example.com", prompt="x", cron_expr="0 9 * * *"
        )

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.get(
                    f"/api/v1/scheduled-actions/{action.id}",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                )
            assert resp.status_code == 200
            assert resp.json()["id"] == action.id
        finally:
            _clear_overrides()

    async def test_get_missing_404(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.get(
                    "/api/v1/scheduled-actions/missing",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                )
            assert resp.status_code == 404
        finally:
            _clear_overrides()


class TestPatch:
    async def test_toggle_inactive_unregisters(self, db_session):
        from app.services.scheduled_action_service import ScheduledActionService

        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id="test@example.com", prompt="x", cron_expr="0 9 * * *"
        )

        _install_overrides(db_session)
        _SchedulerStub.reset()
        try:
            async with await _client() as c:
                resp = await c.patch(
                    f"/api/v1/scheduled-actions/{action.id}",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                    json={"is_active": False},
                )
            assert resp.status_code == 200
            assert resp.json()["is_active"] is False
            assert ("unregister", action.id) in _SchedulerStub.calls
        finally:
            _clear_overrides()

    async def test_update_swaps_cron_to_run_at(self, db_session):
        from app.services.scheduled_action_service import ScheduledActionService

        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id="test@example.com", prompt="x", cron_expr="0 9 * * *"
        )

        _install_overrides(db_session)
        future = (datetime.now(tz=UTC) + timedelta(days=1)).isoformat()
        try:
            async with await _client() as c:
                resp = await c.patch(
                    f"/api/v1/scheduled-actions/{action.id}",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                    json={"cron_expr": None, "run_at": future},
                )
            assert resp.status_code == 200
            body = resp.json()
            assert body["cron_expr"] is None
            assert body["run_at"] is not None
        finally:
            _clear_overrides()

    async def test_update_invalid_state_400(self, db_session):
        from app.services.scheduled_action_service import ScheduledActionService

        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id="test@example.com", prompt="x", cron_expr="0 9 * * *"
        )

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    f"/api/v1/scheduled-actions/{action.id}",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                    json={"cron_expr": None},
                )
            assert resp.status_code == 400
        finally:
            _clear_overrides()

    async def test_update_missing_404(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    "/api/v1/scheduled-actions/missing",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                    json={"is_active": False},
                )
            assert resp.status_code == 404
        finally:
            _clear_overrides()


class TestDelete:
    async def test_delete_existing_204_and_unregisters(self, db_session):
        from app.services.scheduled_action_service import ScheduledActionService

        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id="test@example.com", prompt="x", cron_expr="0 9 * * *"
        )

        _install_overrides(db_session)
        _SchedulerStub.reset()
        try:
            async with await _client() as c:
                resp = await c.delete(
                    f"/api/v1/scheduled-actions/{action.id}",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                )
            assert resp.status_code == 204
            assert ("unregister", action.id) in _SchedulerStub.calls
        finally:
            _clear_overrides()

    async def test_delete_missing_404(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.delete(
                    "/api/v1/scheduled-actions/missing",
                    headers={"Authorization": f"Bearer {_token('test@example.com')}"},
                )
            assert resp.status_code == 404
        finally:
            _clear_overrides()
