"""Endpoint tests for the friends graph (Idea 5, subtask 1)."""

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


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _seed_user(db, email: str, full_name: str | None = None) -> None:
    db.add(User(email=email, hashed_password=hash_password("pw"), full_name=full_name))
    await db.commit()


async def _request(db_session, viewer: str, method: str, url: str, **kw) -> Any:
    _install(db_session, viewer)
    try:
        async with _client() as c:
            return await getattr(c, method)(url, **kw)
    finally:
        _clear()


class TestSendRequest:
    async def test_send_creates_pending(self, db_session):
        await _seed_user(db_session, "ana@example.com", "Ana")
        resp = await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": "ana@example.com"}
        )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        assert body["status"] == "pending"
        assert body["requester_email"] == ME
        assert body["addressee_email"] == "ana@example.com"

    async def test_unknown_email_400(self, db_session):
        resp = await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": "ghost@example.com"}
        )
        assert resp.status_code == 400

    async def test_self_request_400(self, db_session):
        resp = await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": ME}
        )
        assert resp.status_code == 400

    async def test_duplicate_request_400(self, db_session):
        await _seed_user(db_session, "ana@example.com")
        await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": "ana@example.com"}
        )
        resp = await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": "ana@example.com"}
        )
        assert resp.status_code == 400

    async def test_reverse_pending_becomes_accepted(self, db_session):
        """If Ana already asked me, my request to Ana accepts hers instead of
        creating a mirror row."""
        await _seed_user(db_session, "ana@example.com")
        resp = await _request(
            db_session,
            "ana@example.com",
            "post",
            "/api/v1/friends/requests",
            json={"email": ME},
        )
        assert resp.status_code == 201
        resp = await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": "ana@example.com"}
        )
        assert resp.status_code == 201
        assert resp.json()["status"] == "accepted"


class TestAcceptDecline:
    async def _incoming(self, db_session) -> str:
        await _seed_user(db_session, "ana@example.com")
        resp = await _request(
            db_session,
            "ana@example.com",
            "post",
            "/api/v1/friends/requests",
            json={"email": ME},
        )
        return resp.json()["id"]

    async def test_accept(self, db_session):
        request_id = await self._incoming(db_session)
        resp = await _request(
            db_session, ME, "post", f"/api/v1/friends/requests/{request_id}/accept"
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["status"] == "accepted"

    async def test_only_addressee_can_accept(self, db_session):
        request_id = await self._incoming(db_session)
        # The requester (ana) can't accept her own request.
        resp = await _request(
            db_session,
            "ana@example.com",
            "post",
            f"/api/v1/friends/requests/{request_id}/accept",
        )
        assert resp.status_code == 404

    async def test_decline_deletes_and_allows_retry(self, db_session):
        request_id = await self._incoming(db_session)
        resp = await _request(
            db_session, ME, "post", f"/api/v1/friends/requests/{request_id}/decline"
        )
        assert resp.status_code == 204
        # Ana can ask again after a decline.
        resp = await _request(
            db_session,
            "ana@example.com",
            "post",
            "/api/v1/friends/requests",
            json={"email": ME},
        )
        assert resp.status_code == 201


class TestFriendNotifications:
    async def _notifications(self, db, user: str):
        from app.services.notification_service import NotificationService

        return await NotificationService(db).list_for_user(user)

    async def test_request_notifies_addressee(self, db_session):
        await _seed_user(db_session, "ana@example.com")
        resp = await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": "ana@example.com"}
        )
        assert resp.status_code == 201
        notes = await self._notifications(db_session, "ana@example.com")
        assert len(notes) == 1
        assert notes[0].channel == "friend_updates"
        assert ME in notes[0].body

    async def test_accept_notifies_requester(self, db_session):
        await _seed_user(db_session, "ana@example.com")
        resp = await _request(
            db_session, "ana@example.com", "post", "/api/v1/friends/requests", json={"email": ME}
        )
        request_id = resp.json()["id"]
        await _request(db_session, ME, "post", f"/api/v1/friends/requests/{request_id}/accept")

        notes = await self._notifications(db_session, "ana@example.com")
        assert any(n.title == "Friend request accepted" and ME in n.body for n in notes)

    async def test_disabled_channel_suppresses_notification(self, db_session):
        from app.services.notification_service import NotificationService

        await _seed_user(db_session, "ana@example.com")
        await NotificationService(db_session).update_preferences(
            "ana@example.com", friend_updates_enabled=False
        )
        await db_session.commit()

        resp = await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": "ana@example.com"}
        )
        assert resp.status_code == 201
        assert await self._notifications(db_session, "ana@example.com") == []


class TestListSearchRemove:
    async def _befriend(self, db_session, email: str, full_name: str | None = None) -> None:
        await _seed_user(db_session, email, full_name)
        resp = await _request(
            db_session, email, "post", "/api/v1/friends/requests", json={"email": ME}
        )
        request_id = resp.json()["id"]
        await _request(db_session, ME, "post", f"/api/v1/friends/requests/{request_id}/accept")

    async def test_list_sections(self, db_session):
        await self._befriend(db_session, "ana@example.com", "Ana")
        await _seed_user(db_session, "bo@example.com")
        await _seed_user(db_session, "cy@example.com")
        # Outgoing: me → bo. Incoming: cy → me.
        await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": "bo@example.com"}
        )
        await _request(
            db_session, "cy@example.com", "post", "/api/v1/friends/requests", json={"email": ME}
        )

        resp = await _request(db_session, ME, "get", "/api/v1/friends")
        assert resp.status_code == 200
        body = resp.json()
        assert [f["email"] for f in body["friends"]] == ["ana@example.com"]
        assert body["friends"][0]["full_name"] == "Ana"
        assert [r["requester_email"] for r in body["incoming_requests"]] == ["cy@example.com"]
        assert [r["addressee_email"] for r in body["outgoing_requests"]] == ["bo@example.com"]

    async def test_search_only_accepted_friends(self, db_session):
        await self._befriend(db_session, "ana@example.com", "Ana Banana")
        # Pending (not accepted) must never surface in search.
        await _seed_user(db_session, "anatole@example.com")
        await _request(
            db_session,
            ME,
            "post",
            "/api/v1/friends/requests",
            json={"email": "anatole@example.com"},
        )

        resp = await _request(db_session, ME, "get", "/api/v1/friends/search", params={"q": "ana"})
        assert resp.status_code == 200
        assert [f["email"] for f in resp.json()] == ["ana@example.com"]

        resp = await _request(
            db_session, ME, "get", "/api/v1/friends/search", params={"q": "banana"}
        )
        assert [f["email"] for f in resp.json()] == ["ana@example.com"]

    async def test_remove_friend(self, db_session):
        await self._befriend(db_session, "ana@example.com")
        resp = await _request(db_session, ME, "delete", "/api/v1/friends/ana@example.com")
        assert resp.status_code == 204
        resp = await _request(db_session, ME, "get", "/api/v1/friends")
        assert resp.json()["friends"] == []

    async def test_remove_unknown_404(self, db_session):
        resp = await _request(db_session, ME, "delete", "/api/v1/friends/ghost@example.com")
        assert resp.status_code == 404


class TestBlocking:
    ANA = "ana@example.com"

    async def _block(self, db_session, viewer: str, target: str):
        return await _request(db_session, viewer, "post", f"/api/v1/friends/{target}/block")

    async def test_block_replaces_friendship_and_hides_both_sides(self, db_session):
        await _seed_user(db_session, self.ANA, "Ana")
        # Become friends first.
        resp = await _request(
            db_session, self.ANA, "post", "/api/v1/friends/requests", json={"email": ME}
        )
        request_id = resp.json()["id"]
        await _request(db_session, ME, "post", f"/api/v1/friends/requests/{request_id}/accept")

        resp = await self._block(db_session, ME, self.ANA)
        assert resp.status_code == 204

        # Blocker sees the entry only under `blocked`.
        body = (await _request(db_session, ME, "get", "/api/v1/friends")).json()
        assert body["friends"] == []
        assert [b["email"] for b in body["blocked"]] == [self.ANA]

        # The blocked side sees nothing at all.
        body = (await _request(db_session, self.ANA, "get", "/api/v1/friends")).json()
        assert body["friends"] == []
        assert body["blocked"] == []

    async def test_blocked_user_cannot_send_request(self, db_session):
        await _seed_user(db_session, self.ANA)
        await self._block(db_session, ME, self.ANA)

        resp = await _request(
            db_session, self.ANA, "post", "/api/v1/friends/requests", json={"email": ME}
        )
        assert resp.status_code == 400
        # Generic message: must not disclose the block.
        assert "block" not in resp.json()["detail"].lower()

    async def test_unblock_allows_requests_again(self, db_session):
        await _seed_user(db_session, self.ANA)
        await self._block(db_session, ME, self.ANA)

        resp = await _request(db_session, ME, "delete", f"/api/v1/friends/{self.ANA}/block")
        assert resp.status_code == 204

        resp = await _request(
            db_session, ME, "post", "/api/v1/friends/requests", json={"email": self.ANA}
        )
        assert resp.status_code == 201

    async def test_only_blocker_can_unblock(self, db_session):
        await _seed_user(db_session, self.ANA)
        await self._block(db_session, ME, self.ANA)

        resp = await _request(db_session, self.ANA, "delete", f"/api/v1/friends/{ME}/block")
        assert resp.status_code == 404

    async def test_block_back_does_not_steal_the_block(self, db_session):
        """If Ana blocked me first, my own block call succeeds (204, no
        disclosure) but must not flip ownership so that Ana loses hers."""
        await _seed_user(db_session, self.ANA)
        await self._block(db_session, self.ANA, ME)

        resp = await self._block(db_session, ME, self.ANA)
        assert resp.status_code == 204

        # Ana still owns the block: it lists under her `blocked`, not mine.
        body = (await _request(db_session, self.ANA, "get", "/api/v1/friends")).json()
        assert [b["email"] for b in body["blocked"]] == [ME]
        body = (await _request(db_session, ME, "get", "/api/v1/friends")).json()
        assert body["blocked"] == []

    async def test_remove_friend_does_not_touch_blocked_row(self, db_session):
        await _seed_user(db_session, self.ANA)
        await self._block(db_session, ME, self.ANA)

        resp = await _request(db_session, ME, "delete", f"/api/v1/friends/{self.ANA}")
        assert resp.status_code == 404
        body = (await _request(db_session, ME, "get", "/api/v1/friends")).json()
        assert [b["email"] for b in body["blocked"]] == [self.ANA]

    async def test_blocked_pair_cannot_share_a_room(self, db_session):
        await _seed_user(db_session, self.ANA)
        await self._block(db_session, ME, self.ANA)

        # Room creation with a blocked invitee fails.
        resp = await _request(
            db_session,
            ME,
            "post",
            "/api/v1/rooms",
            json={"name": "Test room", "member_emails": [self.ANA]},
        )
        assert resp.status_code == 403
        assert "block" not in resp.text.lower()

        # Adding a blocked user to an existing room fails too — in either
        # direction (the blocked side can't pull the blocker in).
        resp = await _request(db_session, ME, "post", "/api/v1/rooms", json={"name": "Mine"})
        room_id = resp.json()["id"]
        resp = await _request(
            db_session,
            ME,
            "post",
            f"/api/v1/rooms/{room_id}/members",
            json={"user_id": self.ANA},
        )
        assert resp.status_code == 403

        resp = await _request(db_session, self.ANA, "post", "/api/v1/rooms", json={"name": "Hers"})
        room_id = resp.json()["id"]
        resp = await _request(
            db_session,
            self.ANA,
            "post",
            f"/api/v1/rooms/{room_id}/members",
            json={"user_id": ME},
        )
        assert resp.status_code == 403

    async def test_block_unknown_email_400(self, db_session):
        resp = await self._block(db_session, ME, "ghost@example.com")
        assert resp.status_code == 400

    async def test_block_self_400(self, db_session):
        resp = await self._block(db_session, ME, ME)
        assert resp.status_code == 400
