"""The ``micro_app`` native chat tool.

This is what makes micro-apps feel *integrated*: the ordinary chat model is
handed one extra tool, and when it decides the user wants to view or change any
of their micro-apps it calls it. The executor ensures the user's workspace,
relays the instruction to the headless opencode agent (which edits the app's
source — or, for a data-driven app like house-designer, its git-tracked data
file — through the repo skills + validators), and returns a result dict that
carries a *panel signal* (``app`` / ``file`` / ``dev_port``) that the Flutter
chat reads to reveal the live app panel on the right. Works the same for every
app in the registry — nothing here is house-designer-specific.

Kept out of ``chat_service`` so the tool descriptor + relay logic stay testable
in isolation and the chat service just wires two small hooks.
"""

from __future__ import annotations

import logging
from pathlib import Path

from app.core.config import get_settings
from app.core.security import create_microapps_panel_token
from app.schemas.microapp import MicroAppInfo
from app.services.agent_turn import ProgressEmit
from app.services.llm_provider import ChatChunk
from app.services.microapp_agent import agent
from app.services.microapp_registry import read_registry
from app.services.microapp_workspace import Workspace, manager

logger = logging.getLogger(__name__)


def _panel_signal(ws: Workspace) -> dict:
    """Fields the frontend needs to open the app panel for this workspace.

    In proxy mode (deployments) the panel loads through the backend's
    /micro-apps proxy, which needs a panel token; otherwise it connects to the
    dev port directly.
    """
    settings = get_settings()
    signal: dict = {"dev_port": ws.dev_port, "proxied": settings.microapps_proxy_mode}
    if settings.microapps_proxy_mode:
        signal["panel_token"] = create_microapps_panel_token(ws.user_email, ws.slug, settings)
    return signal


# Sentinel "server id" in the tool lookup so the chat executor can recognise a
# native (non-MCP) tool call and route it here.
NATIVE_SERVER_ID = "__microapp__"
MICRO_APP_TOOL = "micro_app"


def list_registry_apps() -> list[MicroAppInfo]:
    """Apps available to the tool. Read from the main repo's registry.json
    (identical across worktrees), so the descriptor can be built before any
    workspace exists."""
    if not manager.enabled:
        return []
    try:
        return read_registry(manager.repo_path)
    except Exception:  # noqa: BLE001
        logger.warning("Could not read micro-apps registry", exc_info=True)
        return []


def micro_app_descriptor(apps: list[MicroAppInfo]) -> dict | None:
    """The Ollama/OpenAI tool payload advertised to the chat model.

    Returns None when there are no apps (nothing to offer). The available app
    ids are enumerated in the description and constrained via an enum so the
    model picks a real one.
    """
    if not apps:
        return None

    lines = []
    for a in apps:
        bits = [f"'{a.id}'"]
        if a.description:
            bits.append(f"— {a.description}")
        if a.suggestions:
            bits.append(f"(e.g. {a.suggestions[0]})")
        lines.append("  - " + " ".join(bits))
    catalogue = "\n".join(lines)

    return {
        "type": "function",
        "function": {
            "name": MICRO_APP_TOOL,
            "description": (
                "Open or edit one of the user's micro-apps in a live panel next "
                "to the chat. Call this whenever the user wants to see or change "
                "any of these apps:\n"
                f"{catalogue}\n"
                "A specialized agent applies the instruction (editing the app's "
                "source, or its data file for a design app like house-designer) "
                "and the app opens/refreshes in the panel. Examples: 'show me my "
                "house', 'add a window to the living room', 'añade un baño', "
                "'make the fire planner map bigger', 'muéstrame la app de "
                "campamentos'. For general questions not about a micro-app, "
                "answer normally instead of calling this."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "app": {
                        "type": "string",
                        "enum": [a.id for a in apps],
                        "description": (
                            "Which micro-app to open or edit. Omit to continue "
                            "with the app the user is currently working on."
                        ),
                    },
                    "instruction": {
                        "type": "string",
                        "description": (
                            "What to view or change, in the user's own words "
                            "(English or Spanish). For a pure 'show me' request, "
                            "pass the request as-is."
                        ),
                    },
                    "edit": {
                        "type": "boolean",
                        "description": (
                            "true when the user wants to CHANGE the app "
                            "(e.g. 'add a window', 'make the map bigger'); false "
                            "when they only want to OPEN/VIEW it (e.g. 'open the "
                            "house designer', 'show me the fire planner'). "
                            "Opening is instant; editing runs the agent."
                        ),
                    },
                },
                "required": ["instruction"],
            },
        },
    }


# Words that signal a pure open/view request when the model omits the `edit`
# flag — a light fallback so opening stays fast even without the flag.
_VIEW_ONLY_HINTS = (
    "open",
    "show",
    "view",
    "display",
    "see ",
    "look at",
    "abre",
    "abrir",
    "muestra",
    "muéstrame",
    "muestrame",
    "ver ",
    "enseña",
)


def _coerce_edit(raw, instruction: str) -> bool:
    """Decide whether this call should run the editing agent.

    Honours an explicit ``edit`` flag from the model (bool or string); when the
    model omits it, infers view-only from the instruction so opening stays fast.
    """
    if isinstance(raw, bool):
        return raw
    if isinstance(raw, str):
        return raw.strip().lower() not in ("false", "0", "no", "")
    text = (instruction or "").strip().lower()
    if not text:
        return False  # nothing to do → treat as a plain open
    # Short instruction that starts with a view verb and no obvious change verb.
    if any(text.startswith(h) or f" {h}" in text for h in _VIEW_ONLY_HINTS):
        change_verbs = (
            "add",
            "change",
            "make",
            "remove",
            "delete",
            "move",
            "resize",
            "bigger",
            "smaller",
            "añade",
            "cambia",
            "quita",
            "elimina",
            "haz",
            "mueve",
            "agranda",
        )
        if not any(v in text for v in change_verbs):
            return False
    return True


def _resolve_app(
    apps: list[MicroAppInfo], app_arg: str | None, prior_app: str | None
) -> MicroAppInfo | None:
    """Pick the app: explicit arg → prior/current → the only/flagship app."""
    if app_arg:
        want = app_arg.strip().rstrip("/")
        for a in apps:
            if a.id == want or a.path.rstrip("/") == want:
                return a
    if prior_app:
        for a in apps:
            if a.id == prior_app:
                return a
    if len(apps) == 1:
        return apps[0]
    # Prefer a data-driven (editable) app as the sensible default.
    for a in apps:
        if a.dataDir:
            return a
    return apps[0] if apps else None


def _list_data_files(worktree: Path, app: MicroAppInfo) -> list[str]:
    """Repo-relative data files for a data-driven app, newest first."""
    if not app.dataDir:
        return []
    ddir = worktree / app.dataDir
    if not ddir.is_dir():
        return []
    ext = app.dataExt or ""
    files = [p for p in ddir.glob(f"*{ext}") if p.is_file()]
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return [f"{app.dataDir.rstrip('/')}/{p.name}" for p in files]


def _resolve_data_file(
    worktree: Path, app: MicroAppInfo, file_arg: str | None, prior_file: str | None
) -> str | None:
    files = _list_data_files(worktree, app)
    if not files:
        return None
    if file_arg:
        want = file_arg.strip()
        for f in files:
            if f == want or f.endswith(f"/{want}") or Path(f).name == want:
                return f
        stem = want.split(".", 1)[0]
        for f in files:
            if Path(f).name.split(".", 1)[0] == stem:
                return f
    if prior_file and prior_file in files:
        return prior_file
    return files[0]


async def _forward_progress(chunk, emit: ProgressEmit) -> None:
    """Relay one opencode-agent chunk into the outer chat turn as a live step.

    Maps the micro-app agent's ``ChatResponseChunk`` (from ``translate_event``)
    onto the ``ChatChunk`` shape the turn engine yields, so the existing chat UI
    renders inner tool calls / results / reasoning as a progress timeline. These
    are live-only — the turn's sink doesn't persist them, so history stays tidy
    (one micro_app call + its final summary) after a reload.
    """
    if chunk.type == "tool_call" and chunk.tool_calls:
        await emit(ChatChunk(content="", tool_calls=chunk.tool_calls))
    elif chunk.type == "tool_result" and chunk.tool_result:
        await emit(ChatChunk(content="", metadata={"tool_result": chunk.tool_result}))
    elif chunk.type == "thinking" and chunk.content:
        await emit(ChatChunk(content=chunk.content, is_thinking=True))


async def run_micro_app(
    *,
    user_email: str,
    args: dict,
    prior_app: str | None,
    prior_file: str | None,
    emit: ProgressEmit | None = None,
) -> dict:
    """Ensure the workspace, relay the instruction to opencode, return a result.

    The returned dict is both fed back to the chat model (as the tool result)
    and surfaced to the frontend (via the ``tool_result`` chunk metadata), so it
    doubles as the panel-open signal: ``app`` + optional ``file`` + ``dev_port``.

    When ``emit`` is provided, the agent's inner steps (file reads/edits,
    validator runs, reasoning) are forwarded live as they happen so the chat
    shows a progress timeline instead of going silent for the whole edit.
    """
    if not manager.enabled:
        return {
            "ok": False,
            "summary": "The micro-apps feature is not configured on this server.",
        }

    instruction = (args.get("instruction") or "").strip()
    apps = list_registry_apps()
    app = _resolve_app(apps, args.get("app"), prior_app)
    if app is None:
        return {"ok": False, "summary": "No micro-apps are available."}

    try:
        ws = await manager.ensure(user_email)
    except Exception as exc:  # noqa: BLE001
        logger.exception("microapp workspace ensure failed")
        return {"ok": False, "summary": f"Could not start the workspace: {exc}"}

    if not ws.opencode_ready:
        return {
            "ok": False,
            "summary": "The micro-app agent did not start. Try again shortly.",
            "app": app.id,
            "app_path": app.path,
            **_panel_signal(ws),
        }

    worktree = manager.worktree_path(ws.slug)
    data_file = _resolve_data_file(worktree, app, args.get("file"), prior_file)

    # Fast path: a pure open/view. Skip the agent round-trip entirely and just
    # return the panel signal, so "open the house designer" reveals the app
    # instantly instead of waiting ~20-40s for an agent turn that edits nothing.
    if not _coerce_edit(args.get("edit"), instruction):
        return {
            "ok": True,
            "summary": f"Opened {app.name}.",
            "app": app.id,
            "app_path": app.path,
            "file": data_file,
            "file_name": Path(data_file).name if data_file else None,
            **_panel_signal(ws),
        }

    # Data-driven apps (house-designer) edit a specific file; source-only apps
    # edit their own tree. Wrap the free-form instruction with just enough
    # guardrails — the repo skills supply the how.
    if app.dataDir and data_file:
        full_instruction = (
            f"Work on the '{app.name}' micro-app. The data file is at {data_file}. "
            f"User request (English or Spanish): {instruction}\n"
            "If the request changes the design, edit that file, then run the "
            "app's validator/linter and make sure they pass, preserving existing "
            "elements unless asked to remove them. If it is only to view/show, "
            "do not modify anything."
        )
    else:
        full_instruction = (
            f"Work on the '{app.name}' micro-app; its source is under "
            f"apps/{app.id}/. User request (English or Spanish): {instruction}\n"
            "If the request changes the app, edit its source; the dev server "
            "hot-reloads. Run its build to catch errors. If it is only to "
            "view/show, do not modify anything."
        )

    summary_parts: list[str] = []
    error: str | None = None
    try:
        async for chunk in agent.stream_instruction(ws, full_instruction):
            if chunk.type == "chunk" and chunk.content:
                # Agent narration accumulates into the final tool summary; it is
                # deliberately NOT forwarded as live chat content, which would
                # bleed the agent's voice into the assistant's own answer.
                summary_parts.append(chunk.content)
            elif chunk.type == "error" and chunk.error:
                error = chunk.error
            elif emit is not None:
                # Forward the agent's steps live so the chat shows a timeline
                # (reading a file → editing → running the validator).
                await _forward_progress(chunk, emit)
    except Exception as exc:  # noqa: BLE001
        logger.exception("microapp agent relay failed")
        error = str(exc)

    summary = "".join(summary_parts).strip()
    if error and not summary:
        summary = f"The agent reported an error: {error}"
    elif not summary:
        summary = "Done."

    return {
        "ok": error is None,
        "summary": summary,
        # Panel signal — the frontend opens/refreshes the app panel from these.
        "app": app.id,
        "app_path": app.path,
        "file": data_file,
        "file_name": Path(data_file).name if data_file else None,
        **_panel_signal(ws),
    }
