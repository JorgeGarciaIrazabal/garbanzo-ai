"""Server-authoritative UI submissions using the existing chat tool dispatch."""

import json
import math
import uuid
from datetime import date

from fastapi import HTTPException
from jsonschema import Draft202012Validator, ValidationError
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.message import Message
from app.models.ui_submission import UISubmissionRecord
from app.schemas.visual_ui import Presentation, UISubmission
from app.services import workflow_runner
from app.services.chat_service import ChatService
from app.services.detached_chat_stream import DetachedChatStream
from app.services.room_service import RoomService
from app.services.workflow_service import WorkflowService
from app.topics.topic_ingestion_service import enqueue_message_event


def validate_values(component: dict, values: dict) -> dict:
    """Only user-editable fields may be substituted into saved tool arguments."""
    if len(json.dumps(values, allow_nan=False).encode()) > 16_000:
        raise ValueError("Submitted values exceed 16 KB")
    if component["component"] == "Choices":
        if set(values) != {"choice"} or not any(
            type(values["choice"]) is type(o["value"]) and values["choice"] == o["value"]
            for o in component["options"]
        ):
            raise ValueError("Choose one of the displayed options")
        return values
    fields = {f["name"]: f for f in component["fields"]}
    if not set(values) <= set(fields):
        raise ValueError("Submission contains unknown fields")
    resolved = {}
    for name, field in fields.items():
        value = values.get(name, field.get("value"))
        if value is None or value == "":
            if field.get("required"):
                raise ValueError(f"{field['label']} is required")
            continue
        kind = field["type"]
        if kind == "number":
            if type(value) not in (int, float) or not math.isfinite(value):
                raise ValueError(f"{field['label']} must be a finite number")
        elif kind == "checkbox":
            if not isinstance(value, bool):
                raise ValueError(f"{field['label']} must be a checkbox value")
            if field.get("required") and not value:
                raise ValueError(f"{field['label']} is required")
        else:
            if not isinstance(value, str) or len(value) > 2000:
                raise ValueError(f"{field['label']} must be text of at most 2000 characters")
            if field.get("required") and not value.strip():
                raise ValueError(f"{field['label']} is required")
            if kind == "date":
                date.fromisoformat(value)
            if kind == "select" and value not in field["options"]:
                raise ValueError(f"{field['label']} must be a displayed option")
        resolved[name] = value
    return resolved


def submission_out(record: UISubmissionRecord) -> dict:
    return {
        "action_id": record.action_id,
        "submission_id": record.id,
        "status": record.status,
        "values": record.values,
        "result": record.result,
    }


class UIActionService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.chat = ChatService(db)

    async def source(self, conversation_id: str, user_id: str, tool_call_id: str):
        conversation = await self.chat.conversations.get(
            conversation_id, user_id, include_messages=False
        )
        if conversation is None:
            raise HTTPException(404, "Conversation not found")
        source = await self.db.scalar(
            select(Message).where(
                Message.conversation_id == conversation_id,
                Message.role == "tool_result",
                Message.meta["tool_call_id"].as_string() == tool_call_id,
                Message.meta["tool_name"].as_string() == "render_ui",
            )
        )
        if source is None:
            raise HTTPException(404, "Presentation not found")
        result = (source.meta or {}).get("result")
        if not isinstance(result, dict) or result.get("ok") is not True:
            raise HTTPException(422, "Presentation is invalid")
        presentation = Presentation.model_validate(result["presentation"])
        return conversation, source, presentation

    async def state(self, conversation_id: str, user_id: str, tool_call_id: str) -> dict:
        conversation, source, _ = await self.source(conversation_id, user_id, tool_call_id)
        records = (
            await self.db.scalars(
                select(UISubmissionRecord).where(
                    UISubmissionRecord.message_id == source.id,
                )
            )
        ).all()
        return {
            "available": await self.available(conversation, source),
            "submissions": [submission_out(r) for r in records],
        }

    async def available(self, conversation, source) -> bool:
        if conversation.id in ChatService._active_streams:
            return False
        if conversation.is_primary and source.session_epoch != conversation.session_epoch:
            return False
        newer = await self.db.scalar(
            select(Message.id)
            .where(
                Message.conversation_id == conversation.id,
                Message.seq > source.seq,
                Message.role == "user",
            )
            .limit(1)
        )
        return newer is None

    async def submit(self, conversation_id: str, user_id: str, data: UISubmission) -> dict:
        conversation, source, presentation = await self.source(
            conversation_id, user_id, data.tool_call_id
        )
        if presentation.surface_id != data.surface_id:
            raise HTTPException(422, "Surface does not match the saved presentation")
        action = next((a for a in presentation.actions if a.id == data.action_id), None)
        if action is None:
            raise HTTPException(422, "Action does not exist in this presentation")
        component = next(c for c in presentation.components if c.get("action") == action.id)
        try:
            values = validate_values(component, data.values)
        except ValueError as exc:
            raise HTTPException(422, str(exc)) from exc
        existing = await self.db.scalar(
            select(UISubmissionRecord).where(
                UISubmissionRecord.message_id == source.id,
                UISubmissionRecord.action_id == action.id,
            )
        )
        if existing:
            if existing.values != values:
                raise HTTPException(409, "This action has already been submitted")
            return submission_out(existing)
        if not await self.available(conversation, source):
            raise HTTPException(409, "This presentation is no longer available for submission")
        lookup = {}
        args = {key: value for key, value in action.arguments.items() if key not in action.bindings}
        args.update(
            {key: values[field] for key, field in action.bindings.items() if field in values}
        )
        if action.kind == "tool":
            tools, lookup = await self.chat._resolve_tools_for_conversation(conversation)
            descriptor = next(
                (t["function"] for t in tools if t["function"]["name"] == action.tool), None
            )
            if descriptor is None or action.tool not in lookup:
                raise HTTPException(403, "This tool is not enabled for this conversation")
            try:
                Draft202012Validator(descriptor.get("parameters", {})).validate(args)
            except ValidationError as exc:
                raise HTTPException(422, f"Invalid tool arguments: {exc.message}") from exc
        source_id, action_id = source.id, action.id
        record = UISubmissionRecord(
            id=data.submission_id,
            message_id=source_id,
            action_id=action_id,
            status="pending",
            values=values,
        )
        self.db.add(record)
        try:
            # Claim before executing anything, including tools with their own commits
            # or external effects. A crash leaves pending, which never auto-retries.
            await self.db.commit()
        except IntegrityError as exc:
            await self.db.rollback()
            existing = await self.db.scalar(
                select(UISubmissionRecord).where(
                    UISubmissionRecord.message_id == source_id,
                    UISubmissionRecord.action_id == action_id,
                )
            )
            if existing is None or existing.values != values:
                raise HTTPException(409, "Submission conflicts with an existing request") from exc
            return submission_out(existing)
        try:
            if action.kind == "follow_up":
                # Save the user turn and the completed claim in the same commit.
                # Replays only read this record; clients never send another turn.
                if component["component"] == "Choices":
                    option = next(
                        o
                        for o in component["options"]
                        if type(o["value"]) is type(values["choice"])
                        and o["value"] == values["choice"]
                    )
                    details = f"{option['label']}: {option['value']}"
                else:
                    details = "\n".join(
                        f"{field['label']}: {values[field['name']]}"
                        for field in component["fields"]
                        if field["name"] in values
                    )
                message = Message(
                    id=str(uuid.uuid4()),
                    conversation_id=conversation_id,
                    role="user",
                    content=action.prompt + "\n\n" + details,
                    session_epoch=conversation.session_epoch,
                    meta={"ui_submission_id": data.submission_id},
                )
                self.db.add(message)
                conversation.updated_at = func.now()
                await self.db.flush()
                await enqueue_message_event(self.db, conversation, message, "create")
                result = {
                    "ok": True,
                    "message_id": message.id,
                    "conversation_id": conversation_id,
                }
            else:
                result = await self.chat._execute_tool_call(
                    {"id": data.submission_id, "name": action.tool, "arguments": args},
                    lookup,
                    conversation,
                )
                if result.get("ok") and result.get("proposal"):
                    result = await self.apply_proposal(
                        result["proposal"], conversation, user_id, data.tool_call_id
                    )
            # Some tools roll back on failure; reload the durable claim explicitly.
            record = await self.db.get(
                UISubmissionRecord, data.submission_id, populate_existing=True
            )
            record.status = "completed" if result.get("ok", True) else "failed"
            record.result = result
            await self.db.commit()
            if action.kind == "follow_up":
                self.start_follow_up(conversation_id, user_id, result["message_id"])
        except Exception as exc:
            await self.db.rollback()
            record = await self.db.get(UISubmissionRecord, data.submission_id)
            record.status = "failed"
            record.result = {"ok": False, "error": str(exc)}
            await self.db.commit()
        return submission_out(record)

    def start_follow_up(self, conversation_id: str, user_id: str, message_id: str) -> None:
        stream = DetachedChatStream(
            lambda service: service.respond_to_saved_message(conversation_id, user_id, message_id),
            provider_name=self.chat.provider_name,
        )
        # The existing detached producer owns its session and persists results.
        # No HTTP consumer or unbounded queue is needed for this submission.
        stream.mark_disconnected()

    async def apply_proposal(self, proposal, conversation, user_id, tool_call_id) -> dict:
        """The form submission supplies the confirmation for existing proposal tools."""
        kind, payload = proposal["type"], proposal["payload"]
        if kind == "create_room":
            rooms = RoomService(self.db)
            room = await rooms.create(
                owner_id=user_id,
                name=payload["name"],
                description=payload.get("description"),
                member_emails=payload.get("member_emails"),
            )
            for agent in payload.get("agents", []):
                await rooms.add_agent(room.id, user_id, **agent)
            return {"ok": True, "name": room.name, "route": f"/rooms/{room.id}"}
        if kind == "set_conversation_style":
            await self.chat.conversations.update(
                conversation.id,
                user_id,
                model=payload.get("model"),
                thinking_level=payload.get("thinking_level"),
                set_thinking_level=payload.get("thinking_level") is not None,
                system_prompt=payload.get("system_prompt"),
            )
            return {"ok": True}
        if kind == "delegate_workflow":
            workflows = WorkflowService(self.db)
            run = await workflows.create(
                user_id=user_id,
                instruction=payload["instruction"],
                conversation_id=conversation.id,
                tool_call_id=tool_call_id,
                mode="research",
                mcp_tools=await workflows.conversation_mcp_tools(conversation.id, user_id),
                attached_files=await workflows.conversation_attachments(
                    conversation.id, user_id, tool_call_id
                ),
            )
            await workflows.start_snapshot(run)
            workflow_runner.launch(run.id)
            return {"ok": True, "run_id": run.id}
        raise ValueError(f"Unsupported proposal: {kind}")
