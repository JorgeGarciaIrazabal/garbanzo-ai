"""Detached opencode runner for delegated workflows (idea 18).

Generalizes the micro-apps agent away from the monorepo workspace: given a
:class:`~app.models.workflow_run.WorkflowRun` whose snapshot directory is
already populated and git-baselined, spawn an ``opencode serve`` inside it,
relay its event stream into ``WorkflowRun.progress``, and on completion write
the summary back into the originating conversation and push a notification.

The run is deliberately **detached** — :func:`launch` starts an asyncio task
that outlives the HTTP request that created it, which is the whole reason the
progress lives in the database instead of the request's SSE stream. A client
that disappears mid-run comes back to a complete timeline.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
import re
import subprocess
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

from app.core.config import Settings, get_settings
from app.models.message import Message
from app.models.workflow_run import WorkflowRun
from app.services import workflow_watchers
from app.services.mcp_service import build_opencode_mcp_config
from app.services.microapp_agent import MicroappAgent
from app.services.opencode_config import DEFAULT_PERMISSION, build_config, write_config
from app.services.opencode_process import default_spawn, pick_free_port, terminate, wait_ready
from app.services.workflow_service import WorkflowService, absorb_into_baseline, exclude_from_diff

logger = logging.getLogger(__name__)

# Hard ceiling on one delegated run, used only when settings don't say
# otherwise. Long enough for a real refactor, short enough that a wedged
# opencode can't hold a snapshot (and a port) forever. The value that actually
# protects against a hang is ``workflow_idle_timeout_seconds`` below — a run
# that keeps producing signal is allowed to keep going.
MAX_RUN_SECONDS = 15 * 60

# Fallback for the idle watchdog. A run is failed when *nothing at all* has
# arrived for this long: no opencode event, no heartbeat, no text. opencode
# emits ``server.heartbeat`` every ~10 s on the bus we already hold open, and
# we forward those as heartbeat chunks, so a healthy run resets this timer
# even while the model is thinking or a tool is running long.
DEFAULT_IDLE_TIMEOUT_SECONDS = 600.0

# How often buffered progress chunks are flushed to the DB. Per-token writes
# would hammer Postgres; a second of latency is invisible in a minutes-long run.
_FLUSH_INTERVAL = 1.0

# How often the idle watchdog samples the activity stamp.
_IDLE_POLL_SECONDS = 5.0

# Tasks by run id, so a shutdown (or a future cancel endpoint) can reach them.
_RUNNING: dict[str, asyncio.Task] = {}


@dataclass
class _OpencodeEndpoint:
    """Duck-types the bits of ``Workspace`` that ``MicroappAgent`` reads."""

    opencode_base: str
    opencode_ready: bool = True


def _configured(settings: Settings, field: str) -> int | None:
    """Value of ``field`` only when it was explicitly set on ``settings``.

    A pydantic ``BaseSettings`` field always reads back as *something*, so a
    plain ``getattr`` cannot distinguish "the operator set this" from "this is
    the built-in default". ``model_fields_set`` records which fields were
    actually provided, which is what lets an explicit configuration override
    the module constant while the constant still works as the default and as
    the seam tests monkeypatch.
    """
    try:
        provided = settings.model_fields_set
    except AttributeError:  # pragma: no cover — non-pydantic stand-in
        return None
    if field not in provided:
        return None
    value = getattr(settings, field, None)
    return int(value) if isinstance(value, int | float) and value else None


async def _idle_watchdog(activity: dict[str, float], idle_timeout: float) -> None:
    """Fail the run when nothing has arrived for ``idle_timeout`` seconds.

    ``activity["at"]`` is refreshed on every chunk the agent stream produces —
    including the heartbeat opencode emits every ~10 s — so this fires only on
    genuine silence, never merely because a turn is long or a tool is slow.
    """
    while True:
        await asyncio.sleep(_IDLE_POLL_SECONDS)
        if time.monotonic() - activity.get("at", 0.0) >= idle_timeout:
            # Returning (not raising) is what signals the caller: this task is
            # raced against the run body, so completing first is the timeout.
            return


def launch(run_id: str) -> asyncio.Task:
    """Start ``run_id`` as a detached task and return it.

    Callers must NOT await the returned task inside a request handler — that
    would re-couple the run's lifetime to the client's connection.
    """
    task = asyncio.create_task(_run(run_id))
    _RUNNING[run_id] = task
    task.add_done_callback(lambda _t: _RUNNING.pop(run_id, None))
    return task


def active_run_ids() -> list[str]:
    return list(_RUNNING)


def is_running(run_id: str) -> bool:
    task = _RUNNING.get(run_id)
    return task is not None and not task.done()


def cancel(run_id: str) -> bool:
    """Cancel a live run. Returns True when one was actually running.

    Cancelling the task drives ``_run`` into its ``except CancelledError``
    handler, which records ``cancelled`` on the row and kills the opencode
    child through the same ``finally`` that every other exit path uses — so a
    cancelled run leaves no orphaned process or snapshot behind.
    """
    task = _RUNNING.get(run_id)
    if task is None or task.done():
        return False
    task.cancel()
    return True


async def _run(run_id: str) -> None:
    """Execute one workflow end to end. Never raises — failures land on the row."""
    from app.db import session as db_session  # late import: tests swap the maker

    settings = get_settings()
    async with db_session.async_session_maker() as db:
        service = WorkflowService(db)
        run = await db.get(WorkflowRun, run_id)
        if run is None or not run.workdir:
            logger.warning("workflow %s vanished before it could run", run_id)
            return

        workdir = Path(run.workdir)
        instruction = run.instruction
        attachment_paths = (run.scope or {}).get("attachment_paths") or []
        if attachment_paths:
            available = "\n".join(f"- `{path}`" for path in attachment_paths)
            instruction = (
                "Files attached to the message that launched this workflow are "
                "available as input copies in the workspace:\n"
                f"{available}\n\n{instruction}"
            )
        mode = (run.scope or {}).get("mode", "folder")
        conversation_id = run.conversation_id
        user_id = run.user_id
        proc: subprocess.Popen | None = None
        summary_parts: list[str] = []
        status = "done"
        error: str | None = None

        # Refreshed by _stream_into_progress on every chunk (including
        # heartbeats). Read by the idle watchdog to distinguish a quiet run
        # from a dead one.
        activity: dict[str, float] = {"at": time.monotonic()}
        # Filled in by _run_stream once opencode is spawned, so the outer
        # finally can always terminate the child even if the run was cancelled
        # or killed by the watchdog mid-flight.
        proc_holder: dict[str, subprocess.Popen | None] = {"proc": None}
        # An explicitly configured setting wins; otherwise the module constant
        # (the documented, monkeypatchable seam) applies. Using pydantic's
        # default value unconditionally would make the constant unreachable and
        # silently ignore any test or caller that overrides it.
        ceiling = float(_configured(settings, "workflow_max_run_seconds") or MAX_RUN_SECONDS)
        idle_timeout = float(
            _configured(settings, "workflow_idle_timeout_seconds") or DEFAULT_IDLE_TIMEOUT_SECONDS
        )

        try:
            # The watchdog must be able to interrupt the run, so it is raced
            # against the body rather than merely observed: whichever finishes
            # first decides the outcome. (A watchdog that only raised inside
            # its own task would be a no-op — nobody would be awaiting it.)
            run_body = asyncio.create_task(
                _run_stream(
                    db=db,
                    service=service,
                    run_id=run_id,
                    user_id=user_id,
                    run=run,
                    workdir=workdir,
                    instruction=instruction,
                    settings=settings,
                    summary_parts=summary_parts,
                    activity=activity,
                    proc_holder=proc_holder,
                )
            )
            idler = asyncio.create_task(_idle_watchdog(activity, idle_timeout))
            done, _pending = await asyncio.wait(
                {run_body, idler},
                timeout=ceiling,
                return_when=asyncio.FIRST_COMPLETED,
            )
            if run_body in done:
                run_body.result()  # re-raises the run's own failure
                error = None
            elif idler in done:
                # Nothing at all arrived for the idle window: the agent stopped
                # making progress rather than merely taking a long time.
                run_body.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await run_body
                status = "error"
                error = (
                    f"The agent stopped responding — no activity for "
                    f"{int(idle_timeout) // 60} minutes, so the run was ended."
                )
            else:
                # Neither finished within the ceiling: genuinely too much work.
                run_body.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await run_body
                status = "error"
                error = f"The workflow exceeded its {int(ceiling) // 60} minute maximum runtime."
            idler.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await idler
            proc = proc_holder.get("proc")
        except asyncio.CancelledError:
            status = "cancelled"
            error = "The workflow was cancelled."
            raise
        except Exception as exc:  # noqa: BLE001 — a failed run must still be recorded
            logger.exception("workflow %s failed", run_id)
            status = "error"
            error = str(exc)[:500]
        finally:
            await asyncio.to_thread(terminate, proc)
            summary = "".join(summary_parts).strip() or None
            await service.finish(run_id, status=status, summary=summary, error=error)
            if status != "cancelled":
                await _report_completion(
                    db=db,
                    user_id=user_id,
                    run_id=run_id,
                    conversation_id=conversation_id,
                    instruction=instruction,
                    summary=summary,
                    status=status,
                    error=error,
                )
            # Research output is durable in ``summary`` and downloadable from
            # the API, so its empty scratch workdir has no diff lifecycle and
            # can be released immediately on every terminal outcome.
            if mode == "research":
                await db.refresh(run)
                await service.cleanup(run)


def seed_opencode_config(
    workdir: Path,
    settings: Settings,
    mcp: dict[str, dict] | None = None,
    tools: dict[str, bool] | None = None,
) -> None:
    """Write the run's ``opencode.json``, keeping it out of the returned diff.

    The user confirmed this run, so the agent may edit files and run commands —
    inside the snapshot copy, never the user's actual folder.

    If *we* seeded the config it's plumbing, and writing it into the user's
    project would be a surprise, so it's excluded from the diff. A project that
    already ships its own ``opencode.json`` keeps it — but must still end up
    with a permission envelope (see :func:`_ensure_permission_envelope`).
    """
    if write_config(workdir, build_config(settings, mcp=mcp, tools=tools)):
        exclude_from_diff(workdir, ["opencode.json"])
        return
    _ensure_permission_envelope(workdir, mcp=mcp, tools=tools)


def _ensure_permission_envelope(
    workdir: Path,
    *,
    mcp: dict[str, dict] | None = None,
    tools: dict[str, bool] | None = None,
) -> None:
    """Give a project-shipped ``opencode.json`` a permission envelope.

    The run is detached — nobody is there to answer a permission prompt, so a
    project config without a ``permission`` block leaves opencode waiting on
    its first edit/bash approval until the time budget kills the run. Inject
    the default allow envelope when the block is missing; a project that
    declares its own permissions keeps them. The patched file is committed on
    top of the baseline so the injection never reaches the user's folder
    through the auto-applied diff.
    """
    cfg_path = workdir / "opencode.json"
    try:
        config = json.loads(cfg_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return  # unreadable or not plain JSON — leave the project's file alone
    if not isinstance(config, dict):
        return
    changed = False
    if "permission" not in config:
        config["permission"] = dict(DEFAULT_PERMISSION)
        changed = True
    if mcp:
        existing_mcp = config.setdefault("mcp", {})
        if isinstance(existing_mcp, dict):
            existing_mcp.update(mcp)
            changed = True
    if tools:
        existing_tools = config.setdefault("tools", {})
        if isinstance(existing_tools, dict):
            existing_tools.update(tools)
            changed = True
    if not changed:
        return
    cfg_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    absorb_into_baseline(workdir, ["opencode.json"])


def _start_opencode(
    workdir: Path,
    settings: Settings,
) -> tuple[subprocess.Popen | None, str]:
    """Seed the config and spawn ``opencode serve`` in ``workdir`` (blocking)."""
    seed_opencode_config(workdir, settings)
    port = pick_free_port()
    base = f"http://127.0.0.1:{port}"
    proc = default_spawn(
        [
            settings.microapps_opencode_bin,
            "serve",
            "--hostname",
            "127.0.0.1",
            "--port",
            str(port),
        ],
        str(workdir),
        {**os.environ},
    )
    if not wait_ready(base, proc):
        terminate(proc)
        return None, base
    return proc, base


_MCP_NAME_UNSAFE = re.compile(r"[^a-zA-Z0-9_-]")


def _mcp_config_name(name: str, server_id: str) -> str:
    """Stable, collision-resistant OpenCode prefix for an MCP server."""
    clean = _MCP_NAME_UNSAFE.sub("_", name).strip("_-") or "mcp"
    return f"{clean}_{server_id.replace('-', '')[:8]}"


async def _opencode_mcp_config(
    db,
    user_id: str,
    allowed_tool_keys: list[str] | None,
) -> tuple[dict[str, dict], dict[str, bool]]:
    """Translate the conversation's MCP allowance into OpenCode config.

    Thin wrapper over :func:`mcp_service.build_opencode_mcp_config`, which is
    shared with the micro-apps workspace so both agent surfaces seed the same
    servers the chat itself can use.
    """
    return await build_opencode_mcp_config(db, user_id, allowed_tool_keys)


async def _run_stream(
    *,
    db,
    service: WorkflowService,
    run_id: str,
    user_id: str,
    run,
    workdir: Path,
    instruction: str,
    settings: Settings,
    summary_parts: list[str],
    activity: dict[str, float],
    proc_holder: dict[str, subprocess.Popen | None],
) -> None:
    """Seed the config, spawn opencode, and relay its stream into progress.

    Runs as its own task so the caller can race it against the idle watchdog
    and the hard ceiling. The spawned process is published into ``proc_holder``
    before streaming starts, so those abort paths can still kill it.
    """
    mcp, tool_rules = await _opencode_mcp_config(
        db,
        user_id,
        (run.scope or {}).get("mcp_tools", []),
    )
    await asyncio.to_thread(
        seed_opencode_config,
        workdir,
        settings,
        mcp,
        tool_rules,
    )
    proc, base = await asyncio.to_thread(_start_opencode, workdir, settings)
    proc_holder["proc"] = proc
    if proc is None:
        raise RuntimeError(
            "opencode did not become ready — is the 'opencode' binary installed and Ollama running?"
        )
    await _stream_into_progress(
        service=service,
        run_id=run_id,
        endpoint=_OpencodeEndpoint(opencode_base=base),
        instruction=instruction,
        summary_parts=summary_parts,
        settings=settings,
        activity=activity,
    )


async def _stream_into_progress(
    *,
    service: WorkflowService,
    run_id: str,
    endpoint: _OpencodeEndpoint,
    instruction: str,
    summary_parts: list[str],
    settings: Settings,
    activity: dict[str, float] | None = None,
) -> None:
    """Relay opencode's events into the run's persisted progress list.

    ``activity`` is a one-key mutable stamp (``{"at": monotonic}``) refreshed on
    every chunk. The caller's idle watchdog reads it to tell "working quietly"
    from "wedged", so it must be touched for heartbeats too — that is precisely
    the case it exists for.
    """
    agent = MicroappAgent(settings)
    buffer: list[dict] = []
    last_flush = time.monotonic()

    async for chunk in agent.stream_instruction(endpoint, instruction):
        if activity is not None:
            activity["at"] = time.monotonic()
        if chunk.type == "session" and chunk.metadata:
            session_id = chunk.metadata.get("session_id")
            if session_id:
                await service.set_session(run_id, str(session_id))
            continue
        if chunk.type == "done":
            break
        if chunk.type == "error":
            raise RuntimeError(chunk.error or "The agent reported an error.")
        if chunk.type == "chunk" and chunk.content:
            summary_parts.append(chunk.content)

        buffer.append(chunk.model_dump(exclude_none=True))
        now = time.monotonic()
        if now - last_flush >= _FLUSH_INTERVAL:
            await service.append_progress(run_id, buffer)
            buffer = []
            last_flush = now

    if buffer:
        await service.append_progress(run_id, buffer)


async def _report_completion(
    *,
    db,
    user_id: str,
    run_id: str,
    conversation_id: str | None,
    instruction: str,
    summary: str | None,
    status: str,
    error: str | None,
) -> None:
    """Post the summary into the conversation and push a notification.

    Mirrors ``scheduled_action_job``: the result has to land somewhere durable,
    because by the time a minutes-long run finishes the user has usually moved
    on from the stream that started it.
    """
    body = summary or error or "The workflow finished."
    if conversation_id:
        headline = "✅ Workflow finished" if status == "done" else "⚠️ Workflow failed"
        try:
            db.add(
                Message(
                    id=str(uuid.uuid4()),
                    conversation_id=conversation_id,
                    role="assistant",
                    content=f"{headline}\n\n{body}",
                    meta={"workflow_run_id": run_id, "workflow_status": status},
                )
            )
            await db.commit()
        except Exception:
            logger.exception("could not post workflow %s summary to its conversation", run_id)
            await db.rollback()

    # A push is only useful when the user *isn't* watching. If their app has
    # been polling this run, the progress line already showed the result and
    # the conversation reloaded — buzzing them as well is pure noise.
    watched = workflow_watchers.is_watched(run_id)
    workflow_watchers.forget(run_id)
    if watched:
        logger.info("workflow %s finished while watched — skipping push", run_id)
        return

    # Import late so tests that never touch FCM don't pay for firebase setup.
    from app.services.fcm_service import send_to_user

    excerpt = body.strip()
    if len(excerpt) > 200:
        excerpt = excerpt[:200] + "…"
    try:
        await send_to_user(
            db,
            user_id,
            title="Workflow finished" if status == "done" else "Workflow failed",
            body=excerpt or instruction[:200],
            channel="chat_responses",
            data={"conversation_id": conversation_id or "", "workflow_run_id": run_id},
        )
    except Exception:
        logger.exception("could not notify user about workflow %s", run_id)
