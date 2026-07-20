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
import logging
import os
import subprocess
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

from app.core.config import Settings, get_settings
from app.models.message import Message
from app.models.workflow_run import WorkflowRun
from app.services.microapp_agent import MicroappAgent
from app.services.opencode_config import build_config, write_config
from app.services.opencode_process import default_spawn, pick_free_port, terminate, wait_ready
from app.services.workflow_service import WorkflowService, exclude_from_diff

logger = logging.getLogger(__name__)

# Hard ceiling on one delegated run. Long enough for a real refactor, short
# enough that a wedged opencode can't hold a snapshot (and a port) forever.
MAX_RUN_SECONDS = 15 * 60

# How often buffered progress chunks are flushed to the DB. Per-token writes
# would hammer Postgres; a second of latency is invisible in a minutes-long run.
_FLUSH_INTERVAL = 1.0

# Tasks by run id, so a shutdown (or a future cancel endpoint) can reach them.
_RUNNING: dict[str, asyncio.Task] = {}


@dataclass
class _OpencodeEndpoint:
    """Duck-types the bits of ``Workspace`` that ``MicroappAgent`` reads."""

    opencode_base: str
    opencode_ready: bool = True


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
        conversation_id = run.conversation_id
        user_id = run.user_id
        proc: subprocess.Popen | None = None
        summary_parts: list[str] = []
        status = "done"
        error: str | None = None

        try:
            async with asyncio.timeout(MAX_RUN_SECONDS):
                proc, base = await asyncio.to_thread(_start_opencode, workdir, settings)
                if proc is None:
                    raise RuntimeError(
                        "opencode did not become ready — is the 'opencode' binary "
                        "installed and Ollama running?"
                    )
                await _stream_into_progress(
                    service=service,
                    run_id=run_id,
                    endpoint=_OpencodeEndpoint(opencode_base=base),
                    instruction=instruction,
                    summary_parts=summary_parts,
                    settings=settings,
                )
        except TimeoutError:
            status = "error"
            error = f"The workflow exceeded its {MAX_RUN_SECONDS // 60} minute time budget."
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


def seed_opencode_config(workdir: Path, settings: Settings) -> None:
    """Write the run's ``opencode.json``, keeping it out of the returned diff.

    The user confirmed this run, so the agent may edit files and run commands —
    inside the snapshot copy, never the user's actual folder.

    If *we* seeded the config it's plumbing, and writing it into the user's
    project would be a surprise, so it's excluded from the diff. A project that
    already ships its own ``opencode.json`` keeps it, and stays diffable.
    """
    if write_config(workdir, build_config(settings)):
        exclude_from_diff(workdir, ["opencode.json"])


def _start_opencode(workdir: Path, settings: Settings) -> tuple[subprocess.Popen | None, str]:
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


async def _stream_into_progress(
    *,
    service: WorkflowService,
    run_id: str,
    endpoint: _OpencodeEndpoint,
    instruction: str,
    summary_parts: list[str],
    settings: Settings,
) -> None:
    """Relay opencode's events into the run's persisted progress list."""
    agent = MicroappAgent(settings)
    buffer: list[dict] = []
    last_flush = time.monotonic()

    async for chunk in agent.stream_instruction(endpoint, instruction):
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
