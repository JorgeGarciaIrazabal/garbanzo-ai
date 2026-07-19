"""Tests for FriendshipService — friend graph business logic (Idea 5)."""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.models.friendship import Friendship
from app.models.user import User
from app.services.friendship_service import FriendshipService


@pytest.mark.asyncio
class TestFriendshipServiceSendRequest:
    async def test_send_creates_pending_request(self, db_session: AsyncSession):
        """Basic request creation between two users."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")

        assert fr.status == "pending"
        assert fr.requester_email == "alice@example.com"
        assert fr.addressee_email == "bob@example.com"

    async def test_send_self_raises(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com"])

        svc = FriendshipService(db_session)
        with pytest.raises(ValueError, match="cannot befriend yourself"):
            await svc.send_request("alice@example.com", "alice@example.com")

    async def test_unknown_email_raises(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com"])

        svc = FriendshipService(db_session)
        with pytest.raises(ValueError, match="No account with that email"):
            await svc.send_request("alice@example.com", "ghost@example.com")

    async def test_duplicate_same_direction_raises(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        await svc.send_request("alice@example.com", "bob@example.com")

        with pytest.raises(ValueError, match="Friend request already sent"):
            await svc.send_request("alice@example.com", "bob@example.com")

    async def test_reverse_pending_becomes_accepted(self, db_session: AsyncSession):
        """Bob already requested Alice; Alice's request should accept Bob's."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        # Bob asks Alice first
        bob_req = await svc.send_request("bob@example.com", "alice@example.com")
        assert bob_req.status == "pending"

        # Alice "asks" Bob — should flip Bob's row to accepted
        alice_req = await svc.send_request("alice@example.com", "bob@example.com")

        assert alice_req.id == bob_req.id  # same row reused
        assert alice_req.status == "accepted"
        assert alice_req.requester_email == "bob@example.com"  # original requester preserved

    async def test_already_friends_raises(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")
        await svc.accept(fr.id, "bob@example.com")

        with pytest.raises(ValueError, match="already friends"):
            await svc.send_request("alice@example.com", "bob@example.com")

    async def test_blocked_pair_rejects_silently(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        await svc.block("alice@example.com", "bob@example.com")

        # Bob tries to send — should get same generic error, not "you're blocked"
        with pytest.raises(ValueError, match="Unable to send"):
            await svc.send_request("bob@example.com", "alice@example.com")

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()


@pytest.mark.asyncio
class TestFriendshipServiceAcceptDecline:
    async def test_accept_flips_status(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")
        accepted = await svc.accept(fr.id, "bob@example.com")

        assert accepted is not None
        assert accepted.status == "accepted"

    async def test_accept_wrong_user_returns_none(self, db_session: AsyncSession):
        await self._seed_users(
            db_session, ["alice@example.com", "bob@example.com", "carol@example.com"]
        )

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")

        # Carol can't accept Alice's request to Bob
        result = await svc.accept(fr.id, "carol@example.com")
        assert result is None

    async def test_accept_nonexistent_returns_none(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com"])

        svc = FriendshipService(db_session)
        result = await svc.accept("does-not-exist", "alice@example.com")
        assert result is None

    async def test_decline_deletes_row(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")

        deleted = await svc.decline(fr.id, "bob@example.com")
        assert deleted is True

        row = await db_session.get(Friendship, fr.id)
        assert row is None

    async def test_decline_wrong_user_returns_false(self, db_session: AsyncSession):
        await self._seed_users(
            db_session, ["alice@example.com", "bob@example.com", "carol@example.com"]
        )

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")

        deleted = await svc.decline(fr.id, "carol@example.com")
        assert deleted is False

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()


@pytest.mark.asyncio
class TestFriendshipServiceRemove:
    async def test_remove_accepted_friend(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")
        await svc.accept(fr.id, "bob@example.com")

        removed = await svc.remove("alice@example.com", "bob@example.com")
        assert removed is True

        row = await db_session.get(Friendship, fr.id)
        assert row is None

    async def test_remove_own_outgoing_pending(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")

        removed = await svc.remove("alice@example.com", "bob@example.com")
        assert removed is True

        row = await db_session.get(Friendship, fr.id)
        assert row is None

    async def test_remove_incoming_pending_returns_false(self, db_session: AsyncSession):
        """Incoming pending requests must be declined via id, not removed via email."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        await svc.send_request("bob@example.com", "alice@example.com")

        removed = await svc.remove("alice@example.com", "bob@example.com")
        assert removed is False

    async def test_remove_blocked_returns_false(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        await svc.block("alice@example.com", "bob@example.com")

        removed = await svc.remove("alice@example.com", "bob@example.com")
        assert removed is False

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()


@pytest.mark.asyncio
class TestFriendshipServiceBlockUnblock:
    async def test_block_creates_blocked_row(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        blocked = await svc.block("alice@example.com", "bob@example.com")

        assert blocked.status == "blocked"
        assert blocked.requester_email == "alice@example.com"  # blocker is requester

    async def test_block_replaces_existing_friendship(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")
        await svc.accept(fr.id, "bob@example.com")

        blocked = await svc.block("alice@example.com", "bob@example.com")
        assert blocked.status == "blocked"

    async def test_block_replaces_pending_request(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        await svc.send_request("bob@example.com", "alice@example.com")

        blocked = await svc.block("alice@example.com", "bob@example.com")
        assert blocked.status == "blocked"
        assert blocked.requester_email == "alice@example.com"

    async def test_block_self_raises(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com"])

        svc = FriendshipService(db_session)
        with pytest.raises(ValueError, match="cannot block yourself"):
            await svc.block("alice@example.com", "alice@example.com")

    async def test_block_unknown_email_raises(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com"])

        svc = FriendshipService(db_session)
        with pytest.raises(ValueError, match="No account with that email"):
            await svc.block("alice@example.com", "ghost@example.com")

    async def test_unblock_removes_own_block(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        await svc.block("alice@example.com", "bob@example.com")

        unblocked = await svc.unblock("alice@example.com", "bob@example.com")
        assert unblocked is True

        row = await svc._pair_row("alice@example.com", "bob@example.com")
        assert row is None

    async def test_unblock_only_own_block(self, db_session: AsyncSession):
        """Bob blocked Alice first; Alice can't unblock it."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        await svc.block("bob@example.com", "alice@example.com")

        unblocked = await svc.unblock("alice@example.com", "bob@example.com")
        assert unblocked is False

    async def test_unblock_nonexistent_returns_false(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        unblocked = await svc.unblock("alice@example.com", "bob@example.com")
        assert unblocked is False

    async def test_is_blocked_either_direction(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        await svc.block("alice@example.com", "bob@example.com")

        assert await svc.is_blocked("alice@example.com", "bob@example.com") is True
        assert await svc.is_blocked("bob@example.com", "alice@example.com") is True

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()


@pytest.mark.asyncio
class TestFriendshipServiceListSearch:
    async def test_list_relationships_categorizes_correctly(self, db_session: AsyncSession):
        await self._seed_users(
            db_session,
            ["alice@example.com", "bob@example.com", "carol@example.com", "dave@example.com"],
        )

        svc = FriendshipService(db_session)
        # Bob accepted Alice
        fr1 = await svc.send_request("alice@example.com", "bob@example.com")
        await svc.accept(fr1.id, "bob@example.com")
        # Carol sent to Alice (incoming)
        await svc.send_request("carol@example.com", "alice@example.com")
        # Alice sent to Dave (outgoing)
        await svc.send_request("alice@example.com", "dave@example.com")
        # Alice blocked Eve (need to seed Eve)
        await self._seed_users(db_session, ["eve@example.com"])
        await svc.block("alice@example.com", "eve@example.com")

        friends, incoming, outgoing, blocked = await svc.list_relationships("alice@example.com")

        assert len(friends) == 1
        assert friends[0].email == "bob@example.com"
        assert len(incoming) == 1
        assert incoming[0].requester_email == "carol@example.com"
        assert len(outgoing) == 1
        assert outgoing[0].addressee_email == "dave@example.com"
        assert len(blocked) == 1
        assert blocked[0].email == "eve@example.com"

    async def test_blocks_against_viewer_are_hidden(self, db_session: AsyncSession):
        """Bob blocked Alice — Alice's list should NOT show that block."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        await svc.block("bob@example.com", "alice@example.com")

        _, _, _, blocked = await svc.list_relationships("alice@example.com")
        assert blocked == []

    async def test_search_only_in_accepted_friends(self, db_session: AsyncSession):
        await self._seed_users(
            db_session, ["alice@example.com", "bob@example.com", "carol@example.com"]
        )

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")
        await svc.accept(fr.id, "bob@example.com")
        # Carol is only pending incoming — not a friend yet
        await svc.send_request("carol@example.com", "alice@example.com")

        results = await svc.search("alice@example.com", "bob")
        assert len(results) == 1
        assert results[0].email == "bob@example.com"

        results = await svc.search("alice@example.com", "carol")
        assert results == []

    async def test_are_friends(self, db_session: AsyncSession):
        await self._seed_users(
            db_session, ["alice@example.com", "bob@example.com", "carol@example.com"]
        )

        svc = FriendshipService(db_session)
        fr = await svc.send_request("alice@example.com", "bob@example.com")
        await svc.accept(fr.id, "bob@example.com")

        assert await svc.are_friends("alice@example.com", "bob@example.com") is True
        assert await svc.are_friends("alice@example.com", "carol@example.com") is False

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()


@pytest.mark.asyncio
class TestFriendshipServiceCaseInsensitivity:
    async def test_emails_normalized_to_lowercase(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])

        svc = FriendshipService(db_session)
        fr = await svc.send_request("Alice@Example.com", "BOB@EXAMPLE.COM")
        assert fr.requester_email == "alice@example.com"
        assert fr.addressee_email == "bob@example.com"

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()
