"""Relay the headless opencode agent's event stream as ChatResponseChunks.

Ported from ``garbanzo-books/ui/chat.py``: create (or continue) an opencode
session, fire the prompt asynchronously, subscribe to the global ``/event``
stream, and translate opencode's events into the same SSE chunk envelope the
Garbanzo chat endpoint uses, so the existing frontend parser handles them.

The translator (``translate_event``) is a pure function over a small mutable
state object, so tests can feed canned opencode events and assert the emitted
ChatResponseChunk sequence without spawning opencode.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import AsyncIterator
from dataclasses import dataclass, field

import httpx

from app.core.config import Settings, get_settings
from app.schemas.chat import ChatResponseChunk

logger = logging.getLogger(__name__)

# Wake the watchdog this often to distinguish "slowly generating" from "dead".
_WATCHDOG_TIMEOUT = 30.0


@dataclass
class StreamState:
    """Per-turn mutable state threaded through ``translate_event``."""

    sid: str
    role_by_msg: dict[str, str] = field(default_factory=dict)
    text_len: dict[str, int] = field(default_factory=dict)
    tool_started: set[str] = field(default_factory=set)
    tool_finished: set[str] = field(default_factory=set)
    done: bool = False


def _tool_input(state_obj: dict) -> dict:
    return state_obj.get("input") or {}


def translate_event(ev: dict, state: StreamState) -> list[ChatResponseChunk]:
    """Translate one opencode event dict into zero or more ChatResponseChunks.

    Event mapping:
      - message.part.updated / text      → chunk (incremental delta)
      - message.part.updated / reasoning → thinking (incremental delta)
      - message.part.updated / tool      → tool_call (on start) + tool_result
        (on completion/error)
      - session.error                    → error (terminal)
      - session.idle                     → done  (terminal, metadata.session_id)
    """
    out: list[ChatResponseChunk] = []
    props = ev.get("properties", {}) or {}
    part = props.get("part", {}) or {}
    ev_sid = (
        props.get("sessionID")
        or part.get("sessionID")
        or (props.get("info", {}) or {}).get("sessionID")
    )
    if ev_sid and ev_sid != state.sid:
        return out  # a different session's event on the global stream

    etype = ev.get("type")

    if etype == "message.updated":
        info = props.get("info", {}) or {}
        if info.get("id"):
            state.role_by_msg[info["id"]] = info.get("role")
        return out

    if etype == "message.part.updated":
        role = state.role_by_msg.get(part.get("messageID"))
        ptype = part.get("type")
        pid = part.get("id") or ""

        if ptype == "text" and part.get("text") and role != "user":
            full = part["text"]
            prev = state.text_len.get(pid, 0)
            if len(full) > prev:
                out.append(ChatResponseChunk(type="chunk", content=full[prev:]))
                state.text_len[pid] = len(full)

        elif ptype == "reasoning" and part.get("text") and role != "user":
            full = part["text"]
            prev = state.text_len.get(pid, 0)
            if len(full) > prev:
                out.append(ChatResponseChunk(type="thinking", content=full[prev:]))
                state.text_len[pid] = len(full)

        elif ptype == "tool":
            st = part.get("state", {}) or {}
            status = st.get("status", "")
            tool = part.get("tool") or "tool"
            call_id = part.get("callID") or pid
            if call_id not in state.tool_started:
                state.tool_started.add(call_id)
                out.append(
                    ChatResponseChunk(
                        type="tool_call",
                        tool_calls=[{"id": call_id, "name": tool, "arguments": _tool_input(st)}],
                    )
                )
            if status in ("completed", "error") and call_id not in state.tool_finished:
                state.tool_finished.add(call_id)
                result = st.get("output")
                if result is None and st.get("error"):
                    result = st.get("error")
                out.append(
                    ChatResponseChunk(
                        type="tool_result",
                        tool_result={
                            "tool_call_id": call_id,
                            "tool_name": tool,
                            "result": result,
                        },
                    )
                )
        return out

    if etype == "session.error":
        err = props.get("error")
        out.append(ChatResponseChunk(type="error", error=str(err)[:500]))
        state.done = True
        return out

    if etype == "session.idle":
        out.append(ChatResponseChunk(type="done", metadata={"session_id": state.sid}))
        state.done = True
        return out

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
        provider_id, model_id = (model.split("/", 1) + [model])[:2]

        async with httpx.AsyncClient(base_url=base, timeout=None) as client:
            sid = session_id
            try:
                if not sid:
                    resp = await client.post("/session", json={"title": instruction[:60]})
                    sid = resp.json()["id"]
                yield ChatResponseChunk(type="session", metadata={"session_id": sid})

                state = StreamState(sid=sid)
                async with client.stream("GET", "/event", timeout=None) as es:
                    await client.post(
                        f"/session/{sid}/prompt_async",
                        json={
                            "model": {"providerID": provider_id, "modelID": model_id},
                            "parts": [{"type": "text", "text": instruction}],
                        },
                    )
                    lines = es.aiter_lines()
                    buffer: list[str] = []
                    while True:
                        try:
                            line = await asyncio.wait_for(anext(lines), timeout=_WATCHDOG_TIMEOUT)
                        except TimeoutError:
                            # Silent: is opencode alive or dead?
                            try:
                                await client.get("/config", timeout=5.0)
                            except Exception:  # noqa: BLE001
                                yield ChatResponseChunk(
                                    type="error",
                                    error="Agent stopped responding (opencode crashed).",
                                )
                                break
                            continue
                        except (StopAsyncIteration, httpx.ReadError):
                            break

                        for payload in _iter_sse_data(line, buffer):
                            try:
                                ev = json.loads(payload)
                            except (json.JSONDecodeError, ValueError):
                                continue
                            for chunk in translate_event(ev, state):
                                yield chunk
                        if state.done:
                            break
                if not state.done:
                    yield ChatResponseChunk(type="done", metadata={"session_id": sid})
            except Exception as exc:  # noqa: BLE001
                logger.exception("microapp agent stream failed")
                yield ChatResponseChunk(type="error", error=str(exc)[:500])
                yield ChatResponseChunk(type="done", metadata={"session_id": sid})

    async def abort(self, workspace, session_id: str) -> bool:
        """Abort a running opencode session. Returns True on a 2xx response."""
        base = getattr(workspace, "opencode_base", None)
        if not base:
            return False
        try:
            async with httpx.AsyncClient(base_url=base, timeout=10.0) as client:
                resp = await client.post(f"/session/{session_id}/abort")
                return resp.status_code < 400
        except Exception:  # noqa: BLE001
            return False


agent = MicroappAgent()
