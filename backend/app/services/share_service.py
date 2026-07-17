"""Sharing styles / prompt templates with friends (Idea 9).

Copy-on-accept: sharing snapshots the item into ``SharedItem.payload``; the
recipient accepting materializes their own copy from the snapshot. There is
never a live reference between the two accounts, so later edits or deletes
on either side don't affect the other.
"""

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.shared_item import SharedItem
from app.models.style import Style
from app.models.system_prompt import SystemPromptTemplate
from app.services.friendship_service import FriendshipService


class ShareService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.friendships = FriendshipService(db)

    @staticmethod
    def _prompt_payload(template: SystemPromptTemplate) -> dict:
        return {
            "name": template.name,
            "description": template.description,
            "content": template.content,
        }

    async def share(self, sender: str, recipient: str, kind: str, item_id: str) -> SharedItem:
        """Snapshot ``item_id`` and queue it for ``recipient``. Only accepted
        friends can share with each other."""
        recipient = recipient.lower().strip()
        if not await self.friendships.are_friends(sender, recipient):
            raise ValueError("You can only share with your friends.")

        if kind == "prompt":
            template = await self._readable_template(sender, item_id)
            if template is None:
                raise ValueError("Prompt template not found.")
            payload = self._prompt_payload(template)
        elif kind == "style":
            style = (
                await self.db.execute(
                    select(Style).where(Style.id == item_id, Style.user_id == sender)
                )
            ).scalar_one_or_none()
            if style is None:
                raise ValueError("Style not found.")
            payload = {
                "name": style.name,
                "model_id": style.model_id,
                "thinking_level": style.thinking_level,
                "prompt": None,
            }
            if style.system_prompt_template_id:
                template = await self._readable_template(sender, style.system_prompt_template_id)
                if template is not None:
                    payload["prompt"] = self._prompt_payload(template)
        else:
            raise ValueError("Unknown share kind.")

        item = SharedItem(
            id=str(uuid.uuid4()),
            sender_email=sender,
            recipient_email=recipient,
            kind=kind,
            payload=payload,
        )
        self.db.add(item)
        await self.db.flush()
        return item

    async def list_incoming(self, recipient: str) -> list[SharedItem]:
        return list(
            (
                await self.db.execute(
                    select(SharedItem)
                    .where(SharedItem.recipient_email == recipient)
                    .order_by(SharedItem.created_at)
                )
            )
            .scalars()
            .all()
        )

    async def accept(self, share_id: str, recipient: str) -> tuple[str, str] | None:
        """Materialize the snapshot as the recipient's own copy. Returns
        ``(kind, created_id)``, or None when the share isn't theirs."""
        item = await self.db.get(SharedItem, share_id)
        if item is None or item.recipient_email != recipient:
            return None

        if item.kind == "prompt":
            created_id = await self._create_template(recipient, item.payload)
        else:
            prompt = item.payload.get("prompt")
            template_id = await self._create_template(recipient, prompt) if prompt else None
            style = Style(
                id=str(uuid.uuid4()),
                user_id=recipient,
                name=item.payload["name"],
                model_id=item.payload["model_id"],
                thinking_level=item.payload.get("thinking_level"),
                system_prompt_template_id=template_id,
                is_default=False,
            )
            self.db.add(style)
            created_id = style.id

        kind = item.kind
        await self.db.delete(item)
        await self.db.flush()
        return kind, created_id

    async def decline(self, share_id: str, recipient: str) -> bool:
        item = await self.db.get(SharedItem, share_id)
        if item is None or item.recipient_email != recipient:
            return False
        await self.db.delete(item)
        await self.db.flush()
        return True

    async def _readable_template(
        self, viewer: str, template_id: str
    ) -> SystemPromptTemplate | None:
        """A template the viewer may share: their own or a built-in."""
        template = await self.db.get(SystemPromptTemplate, template_id)
        if template is None:
            return None
        if template.user_id is not None and template.user_id != viewer:
            return None
        return template

    async def _create_template(self, owner: str, payload: dict) -> str:
        template = SystemPromptTemplate(
            id=str(uuid.uuid4()),
            user_id=owner,
            name=payload["name"],
            description=payload.get("description"),
            content=payload["content"],
            is_builtin=False,
        )
        self.db.add(template)
        await self.db.flush()
        return template.id
