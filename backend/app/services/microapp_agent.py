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
import time
from collections.abc import AsyncIterator
from dataclasses import dataclass, field

import httpx

from app.core.config import Settings, get_settings
from app.schemas.chat import ChatResponseChunk

logger = logging.getLogger(__name__)

# Wake the watchdog this often to distinguish "slowly generating" from "dead".
_WATCHDOG_TIMEOUT = 30.0

# opencode emits its own ``server.heartbeat`` on the /event bus every ~10 s,
# verified against 1.18.30 (frames at 10/20/30/40/50 s during a busy turn).
# We surface it as a heartbeat chunk instead of dropping it: it is the cheapest
# honest liveness signal in the system, and it is what keeps a quiet turn from
# looking wedged — or from tripping an idle timeout upstream.
_HEARTBEAT_EVENT = "server.heartbeat"

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
)


@dataclass
class StreamState:
    """Per-turn mutable state threaded through ``translate_event``."""

    sid: str
    role_by_msg: dict[str, str] = field(default_factory=dict)
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
    """Translate one opencode event dict into zero or more ChatResponseChunks.

    Event mapping:
      - message.part.updated / text      → chunk (incremental delta)
      - message.part.updated / reasoning → thinking (incremental delta)
      - message.part.updated / tool      → tool_call (on start) + tool_execution
        (status/title/duration as it runs) + tool_result (on completion/error)
      - message.part.updated / step-start|step-finish → step counter (feeds the
        heartbeat, and marks genuine forward progress)
      - server.heartbeat                 → heartbeat (liveness only, every ~10 s)
      - session.error                    → error (terminal)
      - session.idle                     → done  (terminal, metadata.session_id)

    Every branch that represents real forward progress should also refresh
    ``last_activity`` — the heartbeat reports it so a client joining a quiet
    stretch still sees what the agent last did.
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

    if etype == _HEARTBEAT_EVENT:
        # opencode's own liveness tick. Not filtered per-session above (it
        # carries no sessionID) and not a "comment line" — it is a real event
        # frame that used to be discarded, leaving long turns indistinguishable
        # from a hung process. Forward it verbatim as a heartbeat.
        return [heartbeat_chunk(state)]

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

        elif ptype in ("step-start", "step-finish"):
            # Step boundaries are the agent's own notion of "a unit of work".
            # Counting them gives the heartbeat a number that moves even when
            # the model is thinking and no tool has run for minutes.
            if ptype == "step-start":
                state.steps += 1
                out.append(heartbeat_chunk(state, phase="step"))

        elif ptype == "tool":
            out.extend(_translate_tool_part(part, pid, state))
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
                            # Nothing on the bus for 30 s. opencode's own
                            # heartbeat normally arrives every ~10 s, so a gap
                            # this long means either a stalled socket or a dead
                            # process. Probe /config to tell them apart — and if
                            # it answers, emit a heartbeat rather than staying
                            # silent, so the caller's idle watchdog can see that
                            # the process is alive even though the bus is quiet.
                            try:
                                await client.get("/config", timeout=5.0)
                            except Exception:  # noqa: BLE001
                                yield ChatResponseChunk(
                                    type="error",
                                    error="Agent stopped responding (opencode crashed).",
                                )
                                break
                            yield heartbeat_chunk(state, phase="quiet")
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
