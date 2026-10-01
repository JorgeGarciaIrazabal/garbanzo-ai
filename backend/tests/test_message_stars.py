"""Owner-scoped message bookmark API and persistence checks."""

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.models.message import Message

pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def star_client(db_session):
    async def database():
        yield db_session

    user = {"email": "test@example.com", "token_payload": {}}

    async def current_user():
        return user

    old = dict(app.dependency_overrides)
    app.dependency_overrides[get_db] = database
    app.dependency_overrides[get_current_user] = current_user
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            yield client, user
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(old)


async def seed_message(
    db_session, conversation_id, *, role="assistant", message_id="bookmark", seq=1
):
    message = Message(
        id=message_id,
        conversation_id=conversation_id,
        role=role,
        content="Keep this useful answer",
        meta={"tokens_generated": 42},
        seq=seq,
    )
    db_session.add(message)
    await db_session.commit()
    return message


@pytest.mark.parametrize("role", ["user", "assistant"])
async def test_star_idempotence_reload_pagination_and_unstar(
    star_client, db_session, test_conversation, role
):
    client, _user = star_client
    message = await seed_message(db_session, test_conversation.id, role=role)
    url = f"/api/v1/chat/conversations/{test_conversation.id}/messages/{message.id}/star"
    for _ in range(2):
        response = await client.patch(url, json={"is_starred": True})
        assert response.status_code == 200, response.text
        assert response.json() == {"id": message.id, "is_starred": True}
    await db_session.refresh(message)
    assert message.is_starred
    assert message.content == "Keep this useful answer"
    assert message.meta == {"tokens_generated": 42}
    newer = await seed_message(db_session, test_conversation.id, message_id="newer", seq=2)
    for path in [
        f"/api/v1/chat/conversations/{test_conversation.id}?message_limit=2",
        f"/api/v1/chat/conversations/{test_conversation.id}/messages?before={newer.id}&limit=1",
    ]:
        response = await client.get(path)
        assert response.status_code == 200, response.text
        saved = next(m for m in response.json()["messages"] if m["id"] == message.id)
        assert saved["is_starred"] is True
    response = await client.patch(url, json={"is_starred": False})
    assert response.status_code == 200
    assert response.json()["is_starred"] is False
    await db_session.refresh(message)
    assert message.is_starred is False


@pytest.mark.parametrize(
    "case", ["other_owner", "deleted", "wrong_conversation", "missing_message"]
)
async def test_star_unavailable_message_returns_404(
    star_client, db_session, test_conversation, case
):
    client, user = star_client
    message = await seed_message(db_session, test_conversation.id)
    conversation_id, message_id = test_conversation.id, message.id
    if case == "other_owner":
        user["email"] = "other@example.com"
    elif case == "deleted":
        test_conversation.is_deleted = True
        await db_session.commit()
    elif case == "wrong_conversation":
        conversation_id = "different-conversation"
    else:
        message_id = "does-not-exist"
    response = await client.patch(
        f"/api/v1/chat/conversations/{conversation_id}/messages/{message_id}/star",
        json={"is_starred": True},
    )
    assert response.status_code == 404
    assert (
        await db_session.scalar(select(Message.is_starred).where(Message.id == message.id)) is False
    )


@pytest.mark.parametrize("role", ["system", "tool_call", "tool_result"])
async def test_star_rejects_machinery(star_client, db_session, test_conversation, role):
    client, _user = star_client
    message = await seed_message(db_session, test_conversation.id, role=role)
    response = await client.patch(
        f"/api/v1/chat/conversations/{test_conversation.id}/messages/{message.id}/star",
        json={"is_starred": True},
    )
    assert response.status_code == 404


@pytest.mark.parametrize(
    "payload", [{}, {"is_starred": None}, {"is_starred": "yes"}, {"is_starred": 1}]
)
async def test_star_requires_an_explicit_boolean(star_client, test_conversation, payload):
    client, _user = star_client
    response = await client.patch(
        f"/api/v1/chat/conversations/{test_conversation.id}/messages/bookmark/star",
        json=payload,
    )
    assert response.status_code == 422
