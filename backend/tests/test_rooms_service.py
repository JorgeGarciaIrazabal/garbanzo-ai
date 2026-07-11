"""Unit tests for RoomService."""

import pytest
from sqlalchemy import select

from app.core.security import hash_password
from app.models.room import RoomMember
from app.models.user import User
from app.schemas.room import RoomDetailOut, RoomMemberOut
from app.services.room_service import (
    RoomNotFoundError,
    RoomPermissionError,
    RoomService,
)


@pytest.mark.asyncio
async def test_create_room_adds_owner_as_member(db_session):
    svc = RoomService(db_session)
    room = await svc.create(owner_id="test@example.com", name="My Room")
    assert room.name == "My Room"
    assert room.owner_id == "test@example.com"
    assert len(room.members) == 1
    assert room.members[0].user_id == "test@example.com"
    assert room.members[0].role == "owner"


@pytest.mark.asyncio
async def test_create_room_with_additional_members(db_session):
    # Seed a second user
    db_session.add(
        User(email="alice@example.com", hashed_password=hash_password("pw"))
    )
    await db_session.commit()

    svc = RoomService(db_session)
    room = await svc.create(
        owner_id="test@example.com",
        name="Group",
        member_emails=["alice@example.com"],
    )
    emails = {m.user_id for m in room.members}
    assert emails == {"test@example.com", "alice@example.com"}


@pytest.mark.asyncio
async def test_non_owner_cannot_update(db_session):
    db_session.add(User(email="bob@example.com", hashed_password=hash_password("pw")))
    await db_session.commit()

    svc = RoomService(db_session)
    room = await svc.create(owner_id="test@example.com", name="Room")
    await svc.add_member(
        room_id=room.id, user_id="test@example.com", new_user_id="bob@example.com"
    )

    with pytest.raises(RoomPermissionError):
        await svc.update(room_id=room.id, user_id="bob@example.com", name="Hack")


@pytest.mark.asyncio
async def test_transfer_ownership(db_session):
    db_session.add(User(email="bob@example.com", hashed_password=hash_password("pw")))
    await db_session.commit()

    svc = RoomService(db_session)
    room = await svc.create(owner_id="test@example.com", name="Room")
    await svc.add_member(
        room_id=room.id, user_id="test@example.com", new_user_id="bob@example.com"
    )

    await svc.update(
        room_id=room.id, user_id="test@example.com", owner_id="bob@example.com"
    )

    room = await svc.get(room.id, viewer_id="bob@example.com")
    assert room.owner_id == "bob@example.com"
    roles = {m.user_id: m.role for m in room.members}
    assert roles["bob@example.com"] == "owner"
    assert roles["test@example.com"] == "member"


@pytest.mark.asyncio
async def test_delete_is_soft(db_session):
    svc = RoomService(db_session)
    room = await svc.create(owner_id="test@example.com", name="Room")
    await svc.delete(room.id, "test@example.com")
    assert await svc.get(room.id, viewer_id="test@example.com") is None


@pytest.mark.asyncio
async def test_nonexistent_room_raises(db_session):
    svc = RoomService(db_session)
    with pytest.raises(RoomNotFoundError):
        await svc.delete("nope", "test@example.com")


@pytest.mark.asyncio
async def test_agents_crud(db_session):
    svc = RoomService(db_session)
    room = await svc.create(owner_id="test@example.com", name="Room")
    agent = await svc.add_agent(
        room_id=room.id,
        user_id="test@example.com",
        name="Alice",
        model="llama3.2",
    )
    assert agent.name == "Alice"

    await svc.update_agent(
        room_id=room.id,
        user_id="test@example.com",
        agent_id=agent.id,
        is_active=False,
    )
    agents = await svc.list_agents(room.id)
    assert agents[0].is_active is False

    await svc.delete_agent(room.id, "test@example.com", agent.id)
    assert await svc.list_agents(room.id) == []


@pytest.mark.asyncio
async def test_remove_owner_forbidden(db_session):
    svc = RoomService(db_session)
    room = await svc.create(owner_id="test@example.com", name="Room")
    with pytest.raises(RoomPermissionError):
        await svc.remove_member(
            room_id=room.id,
            user_id="test@example.com",
            target_user_id="test@example.com",
        )


@pytest.mark.asyncio
async def test_search_scopes(db_session):
    db_session.add(User(email="bob@example.com", hashed_password=hash_password("pw")))
    await db_session.commit()

    svc_a = RoomService(db_session)
    await svc_a.create(owner_id="test@example.com", name="Alpha Private")
    await svc_a.create(
        owner_id="test@example.com", name="Alpha Public", is_public=True
    )
    # Room owned by Bob, not shared with test user
    svc_b = RoomService(db_session)
    await svc_b.create(owner_id="bob@example.com", name="Beta")

    # Scope 'mine' → both of test user's rooms match "Alpha"
    hits, total = await svc_a.search("test@example.com", "Alpha", scope="mine")
    assert total == 2

    # Scope 'public' from test user's view → only the public Alpha (Beta is private)
    hits, total = await svc_a.search("test@example.com", "Alpha", scope="public")
    assert total == 1
    assert hits[0].room.name == "Alpha Public"

    # Bob can see his own "Beta" with scope=mine
    hits, total = await svc_b.search("bob@example.com", "Beta", scope="mine")
    assert total == 1


@pytest.mark.asyncio
async def test_member_full_name_in_members_response(db_session):
    db_session.add(
        User(
            email="alice@example.com",
            hashed_password=hash_password("pw"),
            full_name="Alice Smith",
        )
    )
    await db_session.commit()

    svc = RoomService(db_session)
    room = await svc.create(
        owner_id="test@example.com",
        name="Room",
        member_emails=["alice@example.com"],
    )

    # list_members endpoint path
    members = await svc.list_members(room.id)
    out_by_email = {m.user_id: RoomMemberOut.from_model(m) for m in members}
    assert out_by_email["alice@example.com"].full_name == "Alice Smith"
    # The seeded test user has no full_name → nullable field stays None.
    assert out_by_email["test@example.com"].full_name is None

    # RoomDetailOut (get/create/update) path carries it too.
    detail = RoomDetailOut.from_model(
        await svc.get(room.id, viewer_id="test@example.com")
    )
    detail_by_email = {m.user_id: m.full_name for m in detail.members}
    assert detail_by_email["alice@example.com"] == "Alice Smith"
    assert detail_by_email["test@example.com"] is None


@pytest.mark.asyncio
async def test_private_room_not_visible_to_non_member(db_session):
    db_session.add(User(email="bob@example.com", hashed_password=hash_password("pw")))
    await db_session.commit()

    svc = RoomService(db_session)
    room = await svc.create(owner_id="test@example.com", name="Private")
    assert await svc.get(room.id, viewer_id="bob@example.com") is None
    # Direct membership row absent
    row = (
        await db_session.execute(
            select(RoomMember).where(
                RoomMember.room_id == room.id, RoomMember.user_id == "bob@example.com"
            )
        )
    ).scalar_one_or_none()
    assert row is None
