"""Tests for ShareService — sharing styles/prompts with friends (Idea 9)."""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.models.shared_item import SharedItem
from app.models.style import Style
from app.models.system_prompt import SystemPromptTemplate
from app.models.user import User
from app.services.share_service import ShareService


@pytest.mark.asyncio
class TestShareServiceShare:
    async def test_share_prompt_template_with_friend(self, db_session: AsyncSession):
        """Share a user-created prompt template with an accepted friend."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        template = await self._create_template(
            db_session, "alice@example.com", "My Template", "Be helpful"
        )
        svc = ShareService(db_session)

        shared = await svc.share("alice@example.com", "bob@example.com", "prompt", template.id)

        assert shared.kind == "prompt"
        assert shared.sender_email == "alice@example.com"
        assert shared.recipient_email == "bob@example.com"
        assert shared.payload["name"] == "My Template"
        assert shared.payload["content"] == "Be helpful"

    async def test_share_builtin_prompt_template(self, db_session: AsyncSession):
        """Built-in templates (user_id=None) can be shared by anyone."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        template = SystemPromptTemplate(
            id="builtin-1",
            user_id=None,  # built-in
            name="Built-in Helper",
            content="You are a helpful assistant.",
            is_builtin=True,
        )
        db_session.add(template)
        await db_session.commit()

        svc = ShareService(db_session)
        shared = await svc.share("alice@example.com", "bob@example.com", "prompt", "builtin-1")

        assert shared.payload["name"] == "Built-in Helper"

    async def test_share_style_with_friend(self, db_session: AsyncSession):
        """Share a style (with optional linked prompt) with a friend."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        template = await self._create_template(
            db_session, "alice@example.com", "My Prompt", "Content"
        )
        style = Style(
            id="style-1",
            user_id="alice@example.com",
            name="My Style",
            model_id="llama3.2",
            system_prompt_template_id=template.id,
        )
        db_session.add(style)
        await db_session.commit()

        svc = ShareService(db_session)
        shared = await svc.share("alice@example.com", "bob@example.com", "style", "style-1")

        assert shared.kind == "style"
        assert shared.payload["name"] == "My Style"
        assert shared.payload["model_id"] == "llama3.2"
        assert shared.payload["prompt"] is not None
        assert shared.payload["prompt"]["name"] == "My Prompt"

    async def test_share_style_without_prompt(self, db_session: AsyncSession):
        """Style without linked prompt template shares correctly."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        style = Style(
            id="style-2",
            user_id="alice@example.com",
            name="Plain Style",
            model_id="mistral",
            system_prompt_template_id=None,
        )
        db_session.add(style)
        await db_session.commit()

        svc = ShareService(db_session)
        shared = await svc.share("alice@example.com", "bob@example.com", "style", "style-2")

        assert shared.payload["prompt"] is None

    async def test_share_non_friend_raises(self, db_session: AsyncSession):
        """Cannot share with someone who isn't an accepted friend."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        # No friendship established

        template = await self._create_template(db_session, "alice@example.com", "T", "C")
        svc = ShareService(db_session)

        with pytest.raises(ValueError, match="only share with your friends"):
            await svc.share("alice@example.com", "bob@example.com", "prompt", template.id)

    async def test_share_unknown_template_raises(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        svc = ShareService(db_session)
        with pytest.raises(ValueError, match="Prompt template not found"):
            await svc.share("alice@example.com", "bob@example.com", "prompt", "missing-id")

    async def test_share_unknown_style_raises(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        svc = ShareService(db_session)
        with pytest.raises(ValueError, match="Style not found"):
            await svc.share("alice@example.com", "bob@example.com", "style", "missing-id")

    async def test_share_unknown_kind_raises(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        svc = ShareService(db_session)
        with pytest.raises(ValueError, match="Unknown share kind"):
            await svc.share("alice@example.com", "bob@example.com", "invalid", "x")

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()

    async def _befriend(self, db: AsyncSession, a: str, b: str):
        from app.services.friendship_service import FriendshipService

        svc = FriendshipService(db)
        fr = await svc.send_request(a, b)
        await svc.accept(fr.id, b)

    async def _create_template(
        self, db: AsyncSession, owner: str, name: str, content: str
    ) -> SystemPromptTemplate:
        t = SystemPromptTemplate(
            id=f"template-{name}",
            user_id=owner,
            name=name,
            content=content,
            is_builtin=False,
        )
        db.add(t)
        await db.commit()
        return t


@pytest.mark.asyncio
class TestShareServiceAccept:
    async def test_accept_prompt_creates_user_template(self, db_session: AsyncSession):
        """Accepting a shared prompt creates a new template owned by the recipient."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        template = await self._create_template(
            db_session, "alice@example.com", "Shared Template", "Shared content"
        )
        svc = ShareService(db_session)
        shared = await svc.share("alice@example.com", "bob@example.com", "prompt", template.id)

        kind, created_id = await svc.accept(shared.id, "bob@example.com")

        assert kind == "prompt"
        assert created_id is not None

        # Verify the new template exists and belongs to Bob
        new_template = await db_session.get(SystemPromptTemplate, created_id)
        assert new_template is not None
        assert new_template.user_id == "bob@example.com"
        assert new_template.name == "Shared Template"
        assert new_template.content == "Shared content"
        assert new_template.is_builtin is False

        # Shared item should be deleted after accept
        assert await db_session.get(SharedItem, shared.id) is None

    async def test_accept_style_creates_style_and_optional_template(self, db_session: AsyncSession):
        """Accepting a shared style creates a new style (and template if included)."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        prompt_template = await self._create_template(
            db_session, "alice@example.com", "Prompt", "Be concise"
        )
        style = Style(
            id="style-1",
            user_id="alice@example.com",
            name="Shared Style",
            model_id="llama3.2",
            system_prompt_template_id=prompt_template.id,
        )
        db_session.add(style)
        await db_session.commit()

        svc = ShareService(db_session)
        shared = await svc.share("alice@example.com", "bob@example.com", "style", "style-1")

        kind, created_id = await svc.accept(shared.id, "bob@example.com")

        assert kind == "style"
        assert created_id is not None

        new_style = await db_session.get(Style, created_id)
        assert new_style is not None
        assert new_style.user_id == "bob@example.com"
        assert new_style.name == "Shared Style"
        assert new_style.model_id == "llama3.2"
        assert new_style.system_prompt_template_id is not None

        # The linked template should also be created for Bob
        new_template = await db_session.get(
            SystemPromptTemplate, new_style.system_prompt_template_id
        )
        assert new_template is not None
        assert new_template.user_id == "bob@example.com"

    async def test_accept_wrong_recipient_returns_none(self, db_session: AsyncSession):
        await self._seed_users(
            db_session, ["alice@example.com", "bob@example.com", "carol@example.com"]
        )
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        template = await self._create_template(db_session, "alice@example.com", "T", "C")
        svc = ShareService(db_session)
        shared = await svc.share("alice@example.com", "bob@example.com", "prompt", template.id)

        result = await svc.accept(shared.id, "carol@example.com")
        assert result is None

    async def test_accept_nonexistent_returns_none(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com"])
        svc = ShareService(db_session)
        result = await svc.accept("missing-id", "alice@example.com")
        assert result is None

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()

    async def _befriend(self, db: AsyncSession, a: str, b: str):
        from app.services.friendship_service import FriendshipService

        svc = FriendshipService(db)
        fr = await svc.send_request(a, b)
        await svc.accept(fr.id, b)

    async def _create_template(
        self, db: AsyncSession, owner: str, name: str, content: str
    ) -> SystemPromptTemplate:
        t = SystemPromptTemplate(
            id=f"template-{name}",
            user_id=owner,
            name=name,
            content=content,
            is_builtin=False,
        )
        db.add(t)
        await db.commit()
        return t


@pytest.mark.asyncio
class TestShareServiceDecline:
    async def test_decline_removes_shared_item(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        template = await self._create_template(db_session, "alice@example.com", "T", "C")
        svc = ShareService(db_session)
        shared = await svc.share("alice@example.com", "bob@example.com", "prompt", template.id)

        declined = await svc.decline(shared.id, "bob@example.com")
        assert declined is True

        assert await db_session.get(SharedItem, shared.id) is None

    async def test_decline_wrong_recipient_returns_false(self, db_session: AsyncSession):
        await self._seed_users(
            db_session, ["alice@example.com", "bob@example.com", "carol@example.com"]
        )
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        template = await self._create_template(db_session, "alice@example.com", "T", "C")
        svc = ShareService(db_session)
        shared = await svc.share("alice@example.com", "bob@example.com", "prompt", template.id)

        declined = await svc.decline(shared.id, "carol@example.com")
        assert declined is False

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()

    async def _befriend(self, db: AsyncSession, a: str, b: str):
        from app.services.friendship_service import FriendshipService

        svc = FriendshipService(db)
        fr = await svc.send_request(a, b)
        await svc.accept(fr.id, b)

    async def _create_template(
        self, db: AsyncSession, owner: str, name: str, content: str
    ) -> SystemPromptTemplate:
        t = SystemPromptTemplate(
            id=f"template-{name}",
            user_id=owner,
            name=name,
            content=content,
            is_builtin=False,
        )
        db.add(t)
        await db.commit()
        return t


@pytest.mark.asyncio
class TestShareServiceListIncoming:
    async def test_list_incoming_returns_pending_shares(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        await self._befriend(db_session, "alice@example.com", "bob@example.com")

        template = await self._create_template(db_session, "alice@example.com", "T1", "C1")
        svc = ShareService(db_session)
        await svc.share("alice@example.com", "bob@example.com", "prompt", template.id)
        await svc.share("alice@example.com", "bob@example.com", "prompt", template.id)

        incoming = await svc.list_incoming("bob@example.com")
        assert len(incoming) == 2
        assert all(i.recipient_email == "bob@example.com" for i in incoming)

    async def test_list_incoming_empty_for_no_shares(self, db_session: AsyncSession):
        await self._seed_users(db_session, ["alice@example.com"])
        svc = ShareService(db_session)
        incoming = await svc.list_incoming("alice@example.com")
        assert incoming == []

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()

    async def _befriend(self, db: AsyncSession, a: str, b: str):
        from app.services.friendship_service import FriendshipService

        svc = FriendshipService(db)
        fr = await svc.send_request(a, b)
        await svc.accept(fr.id, b)

    async def _create_template(
        self, db: AsyncSession, owner: str, name: str, content: str
    ) -> SystemPromptTemplate:
        t = SystemPromptTemplate(
            id=f"template-{name}",
            user_id=owner,
            name=name,
            content=content,
            is_builtin=False,
        )
        db.add(t)
        await db.commit()
        return t
