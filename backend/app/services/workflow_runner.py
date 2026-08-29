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
from app.services.mcp_service import MCPService
from app.services.microapp_agent import MicroappAgent
from app.services.opencode_config import DEFAULT_PERMISSION, build_config, write_config
from app.services.opencode_process import default_spawn, pick_free_port, terminate, wait_ready
from app.services.workflow_service import WorkflowService, absorb_into_baseline, exclude_from_diff

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

        try:
            async with asyncio.timeout(MAX_RUN_SECONDS):
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

    Server credentials stay in the MCP table and are read only when the run
    starts. For an explicit per-tool whitelist, each server prefix is denied
    first and only the selected ``server_tool`` names are re-enabled.
    """
    selected: dict[str, list[str]] | None
    if allowed_tool_keys is None:
        selected = None
    else:
        selected = {}
        for key in allowed_tool_keys:
            server_id, separator, tool_name = key.partition(":")
            if separator and server_id and tool_name:
                selected.setdefault(server_id, []).append(tool_name)

    servers = await MCPService(db).list_visible_servers(user_id)
    mcp: dict[str, dict] = {}
    tool_rules: dict[str, bool] = {}
    for server in servers:
        if selected is not None and server.id not in selected:
            continue
        config_name = _mcp_config_name(server.name, server.id)
        if server.transport == "stdio" and server.command:
            config: dict = {
                "type": "local",
                "command": [server.command, *(server.args or [])],
                "enabled": True,
            }
            if server.env:
                config["environment"] = dict(server.env)
        elif server.transport in ("http", "sse") and server.url:
            config = {"type": "remote", "url": server.url, "enabled": True}
            if server.auth_header:
                config["headers"] = {"Authorization": server.auth_header}
        else:
            continue
        mcp[config_name] = config

        if selected is not None:
            tool_rules[f"{config_name}_*"] = False
            for tool_name in selected[server.id]:
                tool_rules[f"{config_name}_{tool_name}"] = True
    return mcp, tool_rules


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
