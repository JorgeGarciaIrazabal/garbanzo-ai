"""Friend graph operations (Idea 5: "Friends").

All methods take the *viewer's* email and enforce that the viewer is a
party to whatever row they touch. Raises ``ValueError`` with a user-safe
message for business-rule violations; endpoints translate those to 400s.
"""

import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.friendship import Friendship
from app.models.user import User


@dataclass
class FriendEntry:
    """An accepted friend from the viewer's perspective."""

    email: str
    full_name: str | None
    friendship_id: str
    since: datetime


class FriendshipService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def send_request(self, requester: str, addressee: str) -> Friendship:
        """Create a pending request — or, if the addressee already asked the
        requester, accept that existing request instead of mirroring it."""
        requester = requester.lower().strip()
        addressee = addressee.lower().strip()
        if requester == addressee:
            raise ValueError("You cannot befriend yourself.")

        user = await self.db.get(User, addressee)
        if user is None:
            # Exact-match existence confirmation is deliberate and the only
            # disclosure this API makes (no enumeration via search).
            raise ValueError("No account with that email.")

        existing = await self._pair_row(requester, addressee)
        if existing is not None:
            if existing.status == "blocked":
                # Don't disclose the block — same message as a plain failure.
                raise ValueError("Unable to send a friend request to that email.")
            if existing.status == "accepted":
                raise ValueError("You are already friends.")
            # Pending: same direction is a duplicate; reverse direction means
            # both want it — accept.
            if existing.requester_email == requester:
                raise ValueError("Friend request already sent.")
            existing.status = "accepted"
            await self.db.flush()
            return existing

        friendship = Friendship(
            id=str(uuid.uuid4()),
            requester_email=requester,
            addressee_email=addressee,
            status="pending",
        )
        self.db.add(friendship)
        await self.db.flush()
        return friendship

    async def accept(self, request_id: str, viewer: str) -> Friendship | None:
        """Accept a pending request addressed to the viewer."""
        row = await self.db.get(Friendship, request_id)
        if row is None or row.addressee_email != viewer or row.status != "pending":
            return None
        row.status = "accepted"
        await self.db.flush()
        return row

    async def decline(self, request_id: str, viewer: str) -> bool:
        """Decline (delete) a pending request addressed to the viewer."""
        row = await self.db.get(Friendship, request_id)
        if row is None or row.addressee_email != viewer or row.status != "pending":
            return False
        await self.db.delete(row)
        await self.db.flush()
        return True

    async def remove(self, viewer: str, other_email: str) -> bool:
        """Remove an accepted friend, or cancel the viewer's own outgoing
        pending request, to ``other_email``. Blocked rows stay put."""
        other_email = other_email.lower().strip()
        row = await self._pair_row(viewer, other_email)
        if row is None or row.status == "blocked":
            return False
        if row.status == "pending" and row.requester_email != viewer:
            # An incoming pending request is declined via its id, not here.
            return False
        await self.db.delete(row)
        await self.db.flush()
        return True

    async def block(self, viewer: str, other_email: str) -> Friendship:
        """Block ``other_email``: any existing relationship (friendship or
        pending request, either direction) is replaced by a blocked row with
        the viewer as requester — that orientation records who did the
        blocking, so only they can undo it."""
        viewer = viewer.lower().strip()
        other_email = other_email.lower().strip()
        if viewer == other_email:
            raise ValueError("You cannot block yourself.")

        user = await self.db.get(User, other_email)
        if user is None:
            # Same deliberate exact-match disclosure as send_request.
            raise ValueError("No account with that email.")

        row = await self._pair_row(viewer, other_email)
        if row is not None:
            if row.status == "blocked" and row.requester_email != viewer:
                # They blocked the viewer first; don't let this call flip
                # ownership of the block (and don't disclose it exists).
                return row
            row.status = "blocked"
            row.requester_email = viewer
            row.addressee_email = other_email
        else:
            row = Friendship(
                id=str(uuid.uuid4()),
                requester_email=viewer,
                addressee_email=other_email,
                status="blocked",
            )
            self.db.add(row)
        await self.db.flush()
        return row

    async def unblock(self, viewer: str, other_email: str) -> bool:
        """Remove the viewer's own block on ``other_email``."""
        row = await self._pair_row(viewer, other_email.lower().strip())
        if row is None or row.status != "blocked" or row.requester_email != viewer:
            return False
        await self.db.delete(row)
        await self.db.flush()
        return True

    async def is_blocked(self, a: str, b: str) -> bool:
        """Whether a block exists between the two users, either direction."""
        row = await self._pair_row(a.lower().strip(), b.lower().strip())
        return row is not None and row.status == "blocked"

    async def list_relationships(
        self, viewer: str
    ) -> tuple[list[FriendEntry], list[Friendship], list[Friendship], list[FriendEntry]]:
        """Return (accepted friends, incoming pending, outgoing pending,
        users the viewer has blocked). Blocks *against* the viewer are never
        surfaced anywhere."""
        rows = (
            await self.db.execute(
                select(Friendship, User)
                .join(
                    User,
                    or_(
                        (User.email == Friendship.requester_email)
                        & (Friendship.addressee_email == viewer),
                        (User.email == Friendship.addressee_email)
                        & (Friendship.requester_email == viewer),
                    ),
                )
                .where(
                    or_(
                        Friendship.requester_email == viewer,
                        Friendship.addressee_email == viewer,
                    )
                )
                .order_by(Friendship.created_at)
            )
        ).all()
        friends: list[FriendEntry] = []
        incoming: list[Friendship] = []
        outgoing: list[Friendship] = []
        blocked: list[FriendEntry] = []
        for friendship, other in rows:
            if friendship.status == "accepted":
                friends.append(
                    FriendEntry(
                        email=other.email,
                        full_name=other.full_name,
                        friendship_id=friendship.id,
                        since=friendship.created_at,
                    )
                )
            elif friendship.status == "pending":
                if friendship.addressee_email == viewer:
                    incoming.append(friendship)
                else:
                    outgoing.append(friendship)
            elif friendship.requester_email == viewer:
                # Blocked, and the viewer is the blocker (block() keeps the
                # blocker as requester). Blocks against the viewer stay
                # invisible by design.
                blocked.append(
                    FriendEntry(
                        email=other.email,
                        full_name=other.full_name,
                        friendship_id=friendship.id,
                        since=friendship.created_at,
                    )
                )
        return friends, incoming, outgoing, blocked

    async def search(self, viewer: str, query: str) -> list[FriendEntry]:
        """Search only among the viewer's accepted friends (no enumeration
        of the wider user table — the privacy guard)."""
        friends, _in, _out, _blocked = await self.list_relationships(viewer)
        q = query.lower().strip()
        if not q:
            return friends
        return [f for f in friends if q in f.email.lower() or q in (f.full_name or "").lower()]

    async def are_friends(self, a: str, b: str) -> bool:
        row = await self._pair_row(a.lower().strip(), b.lower().strip())
        return row is not None and row.status == "accepted"

    async def _pair_row(self, a: str, b: str) -> Friendship | None:
        """The single row between two users, whichever direction."""
        return (
            await self.db.execute(
                select(Friendship).where(
                    or_(
                        (Friendship.requester_email == a) & (Friendship.addressee_email == b),
                        (Friendship.requester_email == b) & (Friendship.addressee_email == a),
                    )
                )
            )
        ).scalar_one_or_none()
