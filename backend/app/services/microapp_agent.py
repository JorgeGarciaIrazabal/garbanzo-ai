"""Relay the headless opencode agent's event stream as ChatResponseChunks.

Ported from ``garbanzo-books/ui/chat.py``: create (or continue) an opencode
session, subscribe to the authenticated V2 ``/api/event`` stream, submit a
durable inbox prompt, and translate opencode's events into the same SSE chunk envelope the
Garbanzo chat endpoint uses, so the existing frontend parser handles them.

The translator (``translate_event``) is a pure function over a small mutable
state object, so tests can feed canned opencode events and assert the emitted
ChatResponseChunk sequence without spawning opencode.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from collections.abc import AsyncIterator
from dataclasses import dataclass, field

import httpx

from app.core.config import Settings, get_settings
from app.schemas.chat import ChatResponseChunk
from app.services.opencode_process import OPENCODE_AUTH

logger = logging.getLogger(__name__)

# Wake the watchdog this often to distinguish "slowly generating" from "dead".
_WATCHDOG_TIMEOUT = 30.0

# V2 sends SSE heartbeat comments every 15s; the stream loop relays them.

# Tool status ranks. opencode does NOT guarantee frame order — a ``completed``
# frame was observed arriving *before* its own ``pending``/``running`` siblings,
# and ``running`` is re-emitted repeatedly for the same callID. Advancing only
# on a strictly higher rank keeps the UI from flickering backwards, while still
# letting a genuine error win over a stale completed.
_TOOL_STATUS_RANK = {"pending": 0, "running": 1, "completed": 2, "error": 3}

# Input keys worth borrowing a label from, in preference order. Tool states are
# only useful to a user if we render *what is being worked on*: a running bash
# call has no ``title`` yet (verified: title is null while running, and only
# populated on completion), so the command has to come from ``input``.
_LABEL_INPUT_KEYS = (
    "command",
    "filePath",
    "path",
    "filename",
    "pattern",
    "query",
    "url",
    "code",
)


@dataclass
class StreamState:
    """Per-turn mutable state threaded through ``translate_event``."""

    sid: str
    prompt_id: str | None = None
    prompt_delivered: bool = False
    seen_events: set[str] = field(default_factory=set)
    ended_text: set[str] = field(default_factory=set)
    tool_inputs: dict[str, dict] = field(default_factory=dict)
    text_len: dict[str, int] = field(default_factory=dict)
    tool_started: set[str] = field(default_factory=set)
    tool_finished: set[str] = field(default_factory=set)
    done: bool = False
    # Highest status rank seen per callID, and the best label/input gathered so
    # far — running frames carry input, completed frames carry the title.
    tool_rank: dict[str, int] = field(default_factory=dict)
    tool_label: dict[str, str] = field(default_factory=dict)
    tool_name: dict[str, str] = field(default_factory=dict)
    tool_started_at: dict[str, int] = field(default_factory=dict)
    # Counters the heartbeat reports so a quiet stretch still shows movement.
    steps: int = 0
    tools_completed: int = 0
    # Most recent human-readable action, carried on heartbeat frames so a
    # client that joins mid-run still learns what the agent is doing.
    last_activity: str | None = None
    # Monotonic clock origin, so elapsed does not depend on wall-clock skew.
    started_monotonic: float = field(default_factory=time.monotonic)


def _tool_input(state_obj: dict) -> dict:
    return state_obj.get("input") or {}


def _basename(value: str) -> str:
    return value.replace("\\", "/").rstrip("/").split("/")[-1]


def describe_tool(tool: str, state_obj: dict, *, title: str | None = None) -> str | None:
    """Human-readable label for one tool state.

    Prefers opencode's own ``title`` (populated on completion, and for ``bash``
    it is the command itself). While a tool is still running that title does not
    exist yet, so the label is derived from ``input`` — otherwise a long bash
    call would show nothing at all for its whole duration, which is exactly the
    blindness this module is trying to remove.
    """
    if title:
        return title
    data = _tool_input(state_obj)
    for key in _LABEL_INPUT_KEYS:
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            text = value.strip()
            if key in ("filePath", "path", "filename"):
                return _basename(text)
            if len(text) > 120:
                return text[:117] + "…"
            return text
    # Deliberately no bare-tool-name fallback: claiming the activity is "bash"
    # tells the user nothing, and it would overwrite a better label already
    # gathered. The client humanizes the tool name when there is no label.
    return None


def _elapsed_s(state: StreamState) -> float:
    return round(time.monotonic() - state.started_monotonic, 1)


def heartbeat_chunk(state: StreamState, *, phase: str = "working") -> ChatResponseChunk:
    """One liveness frame: still alive, how long, and what it last touched."""
    return ChatResponseChunk(
        type="heartbeat",
        content="",
        metadata={
            "heartbeat": {
                "schema_version": 1,
                "phase": phase,
                "elapsed_s": _elapsed_s(state),
                "steps": state.steps,
                "tools_completed": state.tools_completed,
                "tools_running": len(set(state.tool_started) - set(state.tool_finished)),
                "activity": state.last_activity,
            }
        },
    )


def translate_event(ev: dict, state: StreamState) -> list[ChatResponseChunk]:
    """Translate released V2 native events (``type`` + ``data``).

    Only execution completion after our own durable inbox delivery ends a turn;
    a stale idle notification from an earlier turn cannot truncate this prompt.
    Text terminal values reconcile any missed delta without duplicating output.
    """
    if state.done:
        return []
    data = ev.get("data") or {}
    etype = ev.get("type", "")
    event_sid = data.get("sessionID") or (data.get("form") or {}).get("sessionID")
    if event_sid != state.sid:
        return []
    event_id = ev.get("id")
    if event_id:
        if event_id in state.seen_events:
            return []
        state.seen_events.add(event_id)
    if etype == "session.inbox.delivered":
        if data.get("inboxID") == state.prompt_id:
            state.prompt_delivered = True
        return []
    if state.prompt_id and not state.prompt_delivered:
        return []
    if etype == "session.step.started":
        state.steps += 1
        return [heartbeat_chunk(state, phase="step")]
    for kind, chunk_type in (("text", "chunk"), ("reasoning", "thinking")):
        if etype in (f"session.{kind}.delta", f"session.{kind}.ended"):
            key = f"{kind}:{data['assistantMessageID']}:{data['ordinal']}"
            if key in state.ended_text:
                return []
            previous = state.text_len.get(key, 0)
            if etype.endswith(".ended"):
                text = data["text"][previous:]
                state.ended_text.add(key)
            else:
                text = data["delta"]
            state.text_len[key] = previous + len(text)
            return [ChatResponseChunk(type=chunk_type, content=text)] if text else []
    if etype.startswith("session.tool."):
        call_id = data["id"]
        if call_id in state.tool_finished:
            return []
        if etype == "session.tool.input.started":
            state.tool_name[call_id] = data["name"]
            return []
        if etype == "session.tool.input.ended":
            try:
                parsed = json.loads(data["text"])
            except json.JSONDecodeError:
                # V2 reports malformed model arguments before its authoritative
                # failed-tool event. Relay that outcome and allow model recovery.
                logger.debug("Non-JSON tool input for %s; awaiting tool outcome", call_id)
                return []
            if isinstance(parsed, dict):
                state.tool_inputs[call_id] = parsed
            return []
        statuses = {
            "session.tool.called": "running",
            "session.tool.progress": "running",
            "session.tool.success": "completed",
            "session.tool.failed": "error",
        }
        status = statuses.get(etype)
        if status is None:
            return []
        if data.get("input") is not None:
            state.tool_inputs[call_id] = data["input"]
        metadata = data.get("metadata") or {}
        title = metadata.get("title")
        nested = metadata.get("toolCalls") or []
        if not title and nested:
            active = next(
                (call for call in reversed(nested) if call.get("status") == "running"), nested[-1]
            )
            title = describe_tool(
                active.get("tool", "tool"), {"input": active.get("input", {})}
            ) or active.get("tool")
        if status == "completed" and metadata.get("error"):
            status = "error"
        old_label = state.tool_label.get(call_id)
        text_content = "\n".join(
            item["text"] for item in data.get("content", []) if item.get("type") == "text"
        )
        tool_state = {
            "status": status,
            "input": state.tool_inputs.get(call_id, {}),
            "title": title,
            "output": text_content,
            "time": {
                "start": state.tool_started_at.get(call_id, ev.get("created")),
                "end": ev.get("created"),
            },
        }
        if status == "error":
            tool_state["error"] = (data.get("error") or {}).get("message", "Tool failed")
            tool_state["output"] = text_content or tool_state["error"]
        chunks = _translate_tool_part(
            {
                "id": call_id,
                "callID": call_id,
                "tool": state.tool_name.get(call_id, "tool"),
                "state": tool_state,
            },
            call_id,
            state,
        )
        if etype == "session.tool.progress" and title and title != old_label:
            chunks.append(
                ChatResponseChunk(
                    type="tool_execution",
                    metadata={
                        "tool_execution": {
                            "tool_call_id": call_id,
                            "tool_name": state.tool_name.get(call_id, "tool"),
                            "status": "started",
                            "title": title,
                        }
                    },
                )
            )
        return chunks
    if etype in ("permission.asked", "form.created"):
        state.done = True
        return [
            ChatResponseChunk(
                type="error", error="Agent requires interactive approval; this run cannot continue."
            )
        ]
    if etype in ("session.execution.failed", "session.execution.interrupted"):
        state.done = True
        error = (data.get("error") or {}).get(
            "message"
        ) or f"Agent interrupted: {data.get('reason', 'unknown')}"
        return [ChatResponseChunk(type="error", error=error[:500])]
    if etype == "session.execution.succeeded":
        state.done = True
        return [ChatResponseChunk(type="done", metadata={"session_id": state.sid})]
    return []


def _translate_tool_part(part: dict, pid: str, state: StreamState) -> list[ChatResponseChunk]:
    """Translate one ``tool`` part into tool_call / tool_execution / tool_result.

    opencode re-emits a tool's part on every state change (``pending`` →
    ``running`` → ``running`` → ``completed``), and the frames are not ordered:
    a ``completed`` frame was observed arriving *before* its own ``pending`` and
    ``running`` siblings. Both facts are handled here:

    * the ``tool_call`` announcement fires once, on first sight of the callID;
    * a ``tool_execution`` frame is emitted whenever the status rank advances,
      carrying the best label available at that moment (a *running* bash call
      has no ``title`` yet — only its ``input.command``);
    * the terminal ``tool_result`` fires exactly once, when the rank first
      reaches ``completed``/``error``.
    """
    out: list[ChatResponseChunk] = []
    st = part.get("state", {}) or {}
    status = st.get("status", "")
    tool = part.get("tool") or "tool"
    call_id = part.get("callID") or pid

    rank = _TOOL_STATUS_RANK.get(status, -1)
    seen_rank = state.tool_rank.get(call_id, -1)
    if rank < seen_rank:
        return []

    # ``time.start`` only appears on the running/completed frames — the initial
    # pending frame carries ``time: None`` — so keep watching for it instead of
    # sampling it once, or every duration would come back as None.
    started = (st.get("time") or {}).get("start")
    if isinstance(started, int) and call_id not in state.tool_started_at:
        state.tool_started_at[call_id] = started

    first_sight = call_id not in state.tool_started
    if first_sight:
        state.tool_started.add(call_id)
        state.tool_name[call_id] = tool
        args = _tool_input(st)
        label = describe_tool(tool, st, title=st.get("title"))
        if label:
            state.tool_label[call_id] = label
            state.last_activity = label
        out.append(
            ChatResponseChunk(
                type="tool_call",
                tool_calls=[{"id": call_id, "name": tool, "arguments": args}],
            )
        )
        if rank < _TOOL_STATUS_RANK["running"]:
            # Announce a genuine running state exactly once. When the first
            # frame we see is already running/completed (opencode re-emits the
            # part, and frames can arrive out of order), the block below emits
            # the started frame with the better label instead of duplicating it.
            out.append(
                ChatResponseChunk(
                    type="tool_execution",
                    metadata={
                        "tool_execution": {
                            "tool_call_id": call_id,
                            "tool_name": tool,
                            "status": "started",
                            "title": label,
                            "arguments": args,
                        }
                    },
                )
            )

    # Keep the best label for the UI even when a later frame omits it.
    label = describe_tool(tool, st, title=st.get("title"))
    if label:
        state.tool_label[call_id] = label
        state.last_activity = label

    if rank > seen_rank:
        state.tool_rank[call_id] = rank
        if status == "running":
            out.append(
                ChatResponseChunk(
                    type="tool_execution",
                    metadata={
                        "tool_execution": {
                            "tool_call_id": call_id,
                            "tool_name": tool,
                            "status": "started",
                            "title": state.tool_label.get(call_id),
                            "arguments": _tool_input(st),
                        }
                    },
                )
            )

    if status in ("completed", "error") and call_id not in state.tool_finished:
        state.tool_finished.add(call_id)
        state.tool_rank[call_id] = rank
        state.tools_completed += 1
        result = st.get("output")
        if result is None and st.get("error"):
            result = st.get("error")
        started = state.tool_started_at.get(call_id)
        ended = (st.get("time") or {}).get("end")
        duration_ms = (
            ended - started if isinstance(ended, int) and isinstance(started, int) else None
        )
        final_label = state.tool_label.get(call_id)
        out.append(
            ChatResponseChunk(
                type="tool_execution",
                metadata={
                    "tool_execution": {
                        "tool_call_id": call_id,
                        "tool_name": tool,
                        "status": "failed" if status == "error" else "finished",
                        "title": final_label,
                        "duration_ms": duration_ms,
                    }
                },
            )
        )
        out.append(
            ChatResponseChunk(
                type="tool_result",
                tool_result={
                    "tool_call_id": call_id,
                    "tool_name": tool,
                    "result": result,
                    "title": final_label,
                    "duration_ms": duration_ms,
                    "is_error": status == "error",
                },
            )
        )

    return out


def _iter_sse_data(raw: str, buffer: list[str]) -> list[str]:
    """Feed one raw line into an SSE frame buffer; return completed data payloads.

    A blank line terminates a frame. ``data:`` lines accumulate; comment lines
    (starting ':') are ignored. Returns the list of data payloads completed by
    this line (usually 0 or 1).
    """
    completed: list[str] = []
    if raw == "":
        if buffer:
            completed.append("\n".join(buffer))
            buffer.clear()
        return completed
    if raw.startswith(":"):
        return completed
    if raw.startswith("data:"):
        buffer.append(raw[len("data:") :].lstrip())
    return completed


class MicroappAgent:
    """Streams instructions to an opencode workspace and relays its events."""

    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()

    async def stream_instruction(
        self, workspace, instruction: str, session_id: str | None = None
    ) -> AsyncIterator[ChatResponseChunk]:
        base = getattr(workspace, "opencode_base", None)
        if not base or not getattr(workspace, "opencode_ready", False):
            yield ChatResponseChunk(
                type="error",
                error="Agent is not running — start the workspace first.",
            )
            yield ChatResponseChunk(type="done", metadata={})
            return

        model = self._settings.microapps_opencode_model
        provider_id, model_id = model.split("/", 1)
        model_id, separator, variant = model_id.partition("#")
        model_ref = {"providerID": provider_id, "id": model_id}
        if separator:
            model_ref["variant"] = variant

        async with httpx.AsyncClient(base_url=base, timeout=None, auth=OPENCODE_AUTH) as client:
            sid = session_id
            try:
                if not sid:
                    resp = await client.post(
                        "/api/session", json={"title": instruction[:60], "model": model_ref}
                    )
                    resp.raise_for_status()
                    sid = resp.json()["data"]["id"]
                else:
                    resp = await client.post(f"/api/session/{sid}/model", json={"model": model_ref})
                    resp.raise_for_status()
                yield ChatResponseChunk(type="session", metadata={"session_id": sid})
                state = StreamState(sid=sid)
                async with client.stream("GET", "/api/event", timeout=None) as es:
                    es.raise_for_status()
                    lines = es.aiter_lines()
                    buffer: list[str] = []
                    # Opening the response is insufficient: server.connected is
                    # emitted only once the live subscription is installed.
                    async with asyncio.timeout(_WATCHDOG_TIMEOUT):
                        async for line in lines:
                            if any(
                                json.loads(payload).get("type") == "server.connected"
                                for payload in _iter_sse_data(line, buffer)
                            ):
                                break
                        else:
                            raise RuntimeError("Agent event stream closed before subscription")
                    resp = await client.post(
                        f"/api/session/{sid}/prompt", json={"text": instruction}
                    )
                    resp.raise_for_status()
                    state.prompt_id = resp.json()["data"]["id"]
                    failed = False
                    while not state.done:
                        # Keep one pending read across watchdog ticks: cancelling
                        # anext() on timeout would close the underlying stream.
                        read = asyncio.create_task(anext(lines))
                        try:
                            while True:
                                try:
                                    line = await asyncio.wait_for(
                                        asyncio.shield(read), timeout=_WATCHDOG_TIMEOUT
                                    )
                                    break
                                except TimeoutError:
                                    health = await client.get("/api/info", timeout=5.0)
                                    health.raise_for_status()
                                    yield heartbeat_chunk(state, phase="quiet")
                        except StopAsyncIteration as exc:
                            raise RuntimeError(
                                "Agent event stream disconnected before completion."
                            ) from exc
                        finally:
                            if not read.done():
                                read.cancel()
                                await asyncio.gather(read, return_exceptions=True)
                        if line.startswith(":"):
                            yield heartbeat_chunk(state)
                        for payload in _iter_sse_data(line, buffer):
                            for chunk in translate_event(json.loads(payload), state):
                                failed = failed or chunk.type == "error"
                                yield chunk
                    if failed:
                        await self.abort(workspace, sid)
            except asyncio.CancelledError:
                if sid:
                    await self.abort(workspace, sid)
                raise
            except Exception as exc:  # noqa: BLE001
                logger.exception("microapp agent stream failed")
                if sid:
                    await self.abort(workspace, sid)
                yield ChatResponseChunk(
                    type="error",
                    error=str(exc)[:500] or "Agent event stream disconnected before completion.",
                )
                yield ChatResponseChunk(type="done", metadata={"session_id": sid})

    async def abort(self, workspace, session_id: str) -> bool:
        """Abort a running opencode session. Returns True on a 2xx response."""
        base = getattr(workspace, "opencode_base", None)
        if not base:
            return False
        try:
            async with httpx.AsyncClient(base_url=base, timeout=10.0, auth=OPENCODE_AUTH) as client:
                resp = await client.post(f"/api/session/{session_id}/interrupt")
                return resp.status_code < 400
        except Exception:  # noqa: BLE001
            return False


agent = MicroappAgent()
