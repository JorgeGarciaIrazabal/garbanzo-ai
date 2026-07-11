"""Per-user micro-apps workspace manager.

For each user the manager maintains:

1. A git **worktree** of the micro-apps monorepo (``.worktrees/<slug>`` on
   branch ``garbanzo/<slug>``).
2. A **dev server** subprocess (``node scripts/dev-server.js``, HMR) so the
   Flutter app can display the apps live.
3. An **opencode serve** subprocess so an LLM agent can edit files in the
   worktree.

The subprocess lifecycle safety (``os.setsid`` + ``PR_SET_PDEATHSIG`` preexec,
``atexit`` cleanup, ``pkill``-by-pattern belt) is ported verbatim from the
battle-tested ``garbanzo-books/ui/opencode_client.py`` — it guarantees the
children never outlive this process.

Testability: the subprocess spawner, the opencode readiness probe, the npm
installer, and the house validator are all injectable via the constructor so
tests exercise the real git logic against a temp repo without ever spawning
node/opencode.
"""

from __future__ import annotations

import atexit
import contextlib
import ctypes
import ctypes.util
import hashlib
import json
import logging
import os
import random
import re
import shutil
import signal
import socket
import subprocess
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import httpx

from app.core.config import Settings, get_settings
from app.schemas.microapp import ChangeFile, ChangesSummary, PublishResult

logger = logging.getLogger(__name__)

# Port band width for per-user dev servers (base .. base + this).
_DEV_PORT_SPAN = 400
# opencode readiness poll: 240 × 0.25s ≈ 60s (first launch may load a model).
_OPENCODE_READY_RETRIES = 240
_OPENCODE_READY_INTERVAL = 0.25


class FeatureDisabledError(RuntimeError):
    """Raised when the feature is used while MICROAPPS_REPO_PATH is unset."""


class WorkspaceError(RuntimeError):
    """A git / workspace operation failed with a user-facing message."""


def slugify_email(email: str) -> str:
    """Turn an email into a filesystem- and git-branch-safe slug."""
    slug = re.sub(r"[^a-z0-9]+", "-", email.strip().lower()).strip("-")
    return slug or "user"


def _child_preexec() -> None:
    """After fork / before exec in a child: own session + die-with-parent.

    - ``os.setsid()``: new session/group so we can kill the whole group.
    - ``PR_SET_PDEATHSIG=SIGKILL``: the kernel kills the child the instant this
      process dies for ANY reason — the real guarantee against orphans.
    """
    os.setsid()
    try:
        libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
        libc.prctl(1, signal.SIGKILL)  # PR_SET_PDEATHSIG = 1
    except Exception:  # noqa: BLE001 — non-Linux: fall back to explicit kills in stop()
        pass


def _default_spawn(cmd: list[str], cwd: str, env: dict[str, str]) -> subprocess.Popen:
    """Spawn a detached child that dies with us. Injectable for tests."""
    return subprocess.Popen(
        cmd,
        cwd=cwd,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=_child_preexec,
    )


@dataclass
class Workspace:
    """In-memory state for one user's workspace."""

    user_email: str
    slug: str
    path: Path
    branch: str
    dev_port: int
    state: str = "stopped"  # stopped | starting | ready | error
    setup_progress: str | None = None
    dev_proc: subprocess.Popen | None = None
    opencode_proc: subprocess.Popen | None = None
    opencode_port: int | None = None
    opencode_base: str | None = None
    opencode_ready: bool = False

    @property
    def dev_url(self) -> str | None:
        if self.dev_proc is None or self.dev_proc.poll() is not None:
            return None
        return f"http://127.0.0.1:{self.dev_port}"


# Type aliases for the injectable hooks.
SpawnFn = Callable[[list[str], str, dict[str, str]], subprocess.Popen]
HouseValidator = Callable[[Path, str], tuple[bool, str]]


class MicroappWorkspaceManager:
    """Module-level singleton (see ``manager`` below), like the scheduler."""

    def __init__(
        self,
        settings: Settings | None = None,
        *,
        spawn: SpawnFn | None = None,
        house_validator: HouseValidator | None = None,
        auto_install_deps: bool = True,
    ) -> None:
        self._settings = settings or get_settings()
        self._spawn = spawn or _default_spawn
        self._validate_house = house_validator or self._default_validate_house
        self._auto_install_deps = auto_install_deps
        self._workspaces: dict[str, Workspace] = {}
        # Per-slug locks so concurrent ensure() calls for the same user can't
        # race the ~60s startup sequence and double-spawn subprocesses.
        self._locks: dict[str, threading.Lock] = {}
        self._locks_guard = threading.Lock()

    def _slug_lock(self, slug: str) -> threading.Lock:
        with self._locks_guard:
            return self._locks.setdefault(slug, threading.Lock())

    # -- config helpers -----------------------------------------------------

    @property
    def enabled(self) -> bool:
        return bool(self._settings.microapps_repo_path)

    @property
    def repo_path(self) -> Path:
        if not self.enabled:
            raise FeatureDisabledError("Micro-apps workspace feature is disabled")
        return Path(self._settings.microapps_repo_path).expanduser().resolve()

    def _require_enabled(self) -> None:
        if not self.enabled:
            raise FeatureDisabledError("Micro-apps workspace feature is disabled")

    def dev_port_for(self, slug: str) -> int:
        """Deterministic, stable dev port for a slug within the port band."""
        digest = hashlib.sha1(slug.encode("utf-8")).digest()  # noqa: S324 — not security
        offset = int.from_bytes(digest[:4], "big") % _DEV_PORT_SPAN
        return self._settings.microapps_dev_port_base + offset

    def worktree_path(self, slug: str) -> Path:
        return self.repo_path / self._settings.microapps_worktrees_dir / slug

    # -- git plumbing -------------------------------------------------------

    def _git(self, cwd: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
        """Run ``git -C <cwd> <args>``. Blocking; call via ``asyncio.to_thread``."""
        result = subprocess.run(  # noqa: S603
            ["git", "-C", str(cwd), *args],
            capture_output=True,
            text=True,
            check=False,
        )
        if check and result.returncode != 0:
            raise WorkspaceError(
                f"git {' '.join(args)} failed ({result.returncode}): "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )
        return result

    # -- workspace state ----------------------------------------------------

    def _new_state(self, user_email: str, slug: str) -> Workspace:
        return Workspace(
            user_email=user_email,
            slug=slug,
            path=self.worktree_path(slug),
            branch=f"garbanzo/{slug}",
            dev_port=self.dev_port_for(slug),
        )

    def _get_or_create_state(self, user_email: str) -> Workspace:
        slug = slugify_email(user_email)
        ws = self._workspaces.get(slug)
        if ws is None:
            ws = self._new_state(user_email, slug)
            self._workspaces[slug] = ws
        return ws

    def _ensure_worktree(self, ws: Workspace) -> None:
        """Create the worktree if missing. Idempotent."""
        repo = self.repo_path
        listing = self._git(repo, "worktree", "list", "--porcelain").stdout
        target = ws.path.resolve()
        present = any(
            line.startswith("worktree ")
            and Path(line[len("worktree ") :]).resolve() == target
            for line in listing.splitlines()
        )
        if present and ws.path.is_dir():
            return
        ws.path.parent.mkdir(parents=True, exist_ok=True)
        # -B (re)creates the branch at HEAD; skipped above when already present.
        self._git(repo, "worktree", "add", str(ws.path), "-B", ws.branch)

    def _install_deps(self, ws: Workspace) -> None:
        """Run ``npm install`` per app that is missing node_modules. Slow, lazy."""
        if not self._auto_install_deps:
            return
        apps_dir = ws.path / "apps"
        if not apps_dir.is_dir():
            return
        for app_dir in sorted(p for p in apps_dir.iterdir() if p.is_dir()):
            if not (app_dir / "package.json").is_file():
                continue
            if (app_dir / "node_modules").is_dir():
                continue
            ws.setup_progress = f"Installing dependencies for {app_dir.name}…"
            logger.info("microapps: %s", ws.setup_progress)
            proc = subprocess.run(  # noqa: S603
                ["npm", "install", "--prefer-offline", "--no-audit", "--no-fund"],
                cwd=str(app_dir),
                capture_output=True,
                text=True,
                check=False,
            )
            if proc.returncode != 0:
                logger.warning(
                    "npm install failed for %s: %s", app_dir.name, proc.stderr[-500:]
                )

    def _seed_opencode_config(self, ws: Workspace) -> None:
        """Write a minimal opencode.json into the worktree if absent.

        The repo's own opencode.json is gitignored, so worktrees never inherit
        it — we point opencode at the local Ollama cloud endpoint.
        """
        cfg_path = ws.path / "opencode.json"
        if cfg_path.exists():
            return
        model = self._settings.microapps_opencode_model
        bare_model = model.split("/", 1)[1] if "/" in model else model
        config = {
            "$schema": "https://opencode.ai/config.json",
            "provider": {
                "ollama": {
                    "npm": "@ai-sdk/openai-compatible",
                    "name": "Ollama (local)",
                    "options": {
                        "baseURL": f"{self._settings.ollama_base_url.rstrip('/')}/v1"
                    },
                    "models": {bare_model: {"name": bare_model}},
                }
            },
            "model": model,
            # Disable opencode's internal planning/checklist tools: micro-app
            # edits are bounded and the house-design skill + validator/linter
            # supply the structure. Smaller/cloud models otherwise waste turns on
            # malformed todowrite calls, whose schema errors leak into the SSE
            # stream the Flutter agent rail renders.
            "tools": {"todowrite": False, "todoread": False},
            "instructions": ["CLAUDE.md", "AGENTS.md"],
            "permission": {"edit": "allow", "bash": "allow", "webfetch": "allow"},
        }
        cfg_path.write_text(json.dumps(config, indent=2), encoding="utf-8")

    # -- subprocesses -------------------------------------------------------

    def _start_dev_server(self, ws: Workspace) -> None:
        if ws.dev_proc is not None and ws.dev_proc.poll() is None:
            return
        env = {**os.environ, "PORT": str(ws.dev_port)}
        ws.dev_proc = self._spawn(
            ["node", "scripts/dev-server.js"], str(ws.path), env
        )
        logger.info(
            "microapps: dev server for %s on :%s (pid %s)",
            ws.slug, ws.dev_port, getattr(ws.dev_proc, "pid", "?"),
        )

    def _wait_opencode_ready(self, base: str, proc: subprocess.Popen) -> bool:
        """Poll opencode ``/config`` until ready. Injectable-friendly (sync)."""
        for _ in range(_OPENCODE_READY_RETRIES):
            if proc.poll() is not None:
                return False
            try:
                httpx.get(base + "/config", timeout=2.0)
                return True
            except Exception:  # noqa: BLE001 — not up yet
                time.sleep(_OPENCODE_READY_INTERVAL)
        return False

    @staticmethod
    def _pick_free_port() -> int:
        """Random port in the opencode band, bind-tested so a collision with
        another process (or another user's opencode) retries instead of
        handing out a port that fails at spawn time."""
        for _ in range(20):
            port = random.randint(40000, 60000)  # noqa: S311 — not security-sensitive
            with socket.socket() as s:
                try:
                    s.bind(("127.0.0.1", port))
                except OSError:
                    continue
            return port
        raise WorkspaceError("Could not find a free local port for opencode")

    def _start_opencode(self, ws: Workspace) -> None:
        if ws.opencode_ready and ws.opencode_proc and ws.opencode_proc.poll() is None:
            return
        self._seed_opencode_config(ws)
        port = self._pick_free_port()
        base = f"http://127.0.0.1:{port}"
        env = {**os.environ}
        proc = self._spawn(
            [
                self._settings.microapps_opencode_bin,
                "serve",
                "--hostname",
                "127.0.0.1",
                "--port",
                str(port),
            ],
            str(ws.path),
            env,
        )
        ws.opencode_proc = proc
        ws.opencode_port = port
        ws.opencode_base = base
        ws.setup_progress = "Starting agent…"
        ws.opencode_ready = self._wait_opencode_ready(base, proc)
        if not ws.opencode_ready:
            raise WorkspaceError(
                "opencode did not become ready — is the 'opencode' binary "
                "installed and Ollama running?"
            )
        logger.info("microapps: opencode for %s at %s (pid %s)", ws.slug, base, proc.pid)

    def _stop_procs(self, ws: Workspace) -> None:
        for proc, port, pattern in (
            (ws.dev_proc, ws.dev_port, "scripts/dev-server.js"),
            (ws.opencode_proc, ws.opencode_port, "opencode serve"),
        ):
            if proc is not None:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                except Exception:  # noqa: BLE001
                    with contextlib.suppress(Exception):
                        proc.kill()
            if port is not None:
                with contextlib.suppress(Exception):
                    subprocess.run(  # noqa: S603
                        ["pkill", "-9", "-f", f"{pattern}.*{port}"], check=False
                    )
        ws.dev_proc = None
        ws.opencode_proc = None
        ws.opencode_port = None
        ws.opencode_base = None
        ws.opencode_ready = False

    # -- public lifecycle API ----------------------------------------------

    def ensure_sync(self, user_email: str) -> Workspace:
        """Blocking ensure() core. Public async wrapper is ``ensure``.

        Serialized per user: the startup sequence blocks for up to ~60s, and
        without the lock two concurrent calls would double-spawn the
        dev-server/opencode subprocesses.
        """
        self._require_enabled()
        with self._slug_lock(slugify_email(user_email)):
            return self._ensure_sync_locked(user_email)

    def _ensure_sync_locked(self, user_email: str) -> Workspace:
        ws = self._get_or_create_state(user_email)
        ws.state = "starting"
        try:
            self._ensure_worktree(ws)
            ws.setup_progress = "Installing dependencies…"
            self._install_deps(ws)
            self._start_dev_server(ws)
            self._start_opencode(ws)
            ws.state = "ready"
            ws.setup_progress = None
        except Exception as exc:
            ws.state = "error"
            ws.setup_progress = str(exc)
            raise
        return ws

    async def ensure(self, user_email: str) -> Workspace:
        import asyncio

        return await asyncio.to_thread(self.ensure_sync, user_email)

    def status(self, user_email: str) -> Workspace:
        """Return current in-memory state. Read-only: unknown users get a
        transient ``stopped`` snapshot that is NOT cached in ``_workspaces``."""
        self._require_enabled()
        slug = slugify_email(user_email)
        ws = self._workspaces.get(slug)
        return ws if ws is not None else self._new_state(user_email, slug)

    def stop(self, user_email: str) -> None:
        """Kill both subprocesses but keep the worktree on disk."""
        slug = slugify_email(user_email)
        ws = self._workspaces.get(slug)
        if ws is None:
            return
        self._stop_procs(ws)
        ws.state = "stopped"
        ws.setup_progress = None

    def stop_all(self) -> None:
        for ws in self._workspaces.values():
            try:
                self._stop_procs(ws)
                ws.state = "stopped"
            except Exception:  # noqa: BLE001
                pass

    # -- repo provisioning + periodic sync (deployments) ---------------------

    def sync_repo_sync(self) -> None:
        """Clone the repo if missing, then pull remote changes into it.

        Blocking; run via ``asyncio.to_thread`` (see microapps_sync_job).
        Fetches once at the repo level (worktrees share refs), fast-forwards
        the primary checkout when it sits on main, and rebases every *clean*
        user worktree onto the updated remote. Dirty or conflicting worktrees
        are left alone — publish handles those interactively.
        """
        self._require_enabled()
        repo = self.repo_path
        remote = self._settings.microapps_publish_remote

        if not (repo / ".git").exists():
            url = self._settings.microapps_git_url
            if not url:
                raise WorkspaceError(
                    f"{repo} is not a git repository and MICROAPPS_GIT_URL is unset"
                )
            logger.info("microapps: cloning %s into %s", url, repo)
            repo.parent.mkdir(parents=True, exist_ok=True)
            result = subprocess.run(  # noqa: S603
                ["git", "clone", url, str(repo)],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                raise WorkspaceError(f"git clone failed: {result.stderr.strip()}")
            return  # fresh clone is already current

        self._git(repo, "fetch", remote)
        head = self._git(repo, "rev-parse", "--abbrev-ref", "HEAD", check=False)
        if head.stdout.strip() == "main":
            merge = self._git(repo, "merge", "--ff-only", f"{remote}/main", check=False)
            if merge.returncode != 0:
                logger.warning(
                    "microapps: main checkout not fast-forwardable: %s",
                    merge.stderr.strip(),
                )

        worktrees_dir = repo / self._settings.microapps_worktrees_dir
        if not worktrees_dir.is_dir():
            return
        for wt in sorted(p for p in worktrees_dir.iterdir() if p.is_dir()):
            if not (wt / ".git").exists():
                continue
            if self._git(wt, "status", "--porcelain", check=False).stdout.strip():
                logger.info("microapps: skipping sync of dirty worktree %s", wt.name)
                continue
            rebase = self._git(wt, "rebase", f"{remote}/main", check=False)
            if rebase.returncode != 0:
                self._git(wt, "rebase", "--abort", check=False)
                logger.warning(
                    "microapps: rebase of %s onto %s/main failed: %s",
                    wt.name, remote, rebase.stderr.strip(),
                )
                continue
            # Running workspaces may need new deps after the rebase; others
            # get theirs on the next ensure().
            ws = self._workspaces.get(wt.name)
            if ws is not None:
                self._install_deps(ws)

    # -- git: changes / publish / revert -----------------------------------

    def _base_ref(self, ws: Workspace) -> str:
        """The ref to diff/rebase against: origin/main if it exists, else main."""
        remote = self._settings.microapps_publish_remote
        candidate = f"{remote}/main"
        res = self._git(ws.path, "rev-parse", "--verify", "--quiet", candidate, check=False)
        if res.returncode == 0:
            return candidate
        return "main"

    def _parse_numstat(self, ws: Workspace, base: str) -> dict[str, tuple[int, int]]:
        out = self._git(ws.path, "diff", "--numstat", base, check=False).stdout
        stats: dict[str, tuple[int, int]] = {}
        for line in out.splitlines():
            parts = line.split("\t")
            if len(parts) != 3:
                continue
            plus_s, minus_s, path = parts
            plus = 0 if plus_s == "-" else int(plus_s or 0)
            minus = 0 if minus_s == "-" else int(minus_s or 0)
            stats[path] = (plus, minus)
        return stats

    def changes(self, user_email: str) -> ChangesSummary:
        """Structured summary of the working tree + branch vs the publish base."""
        self._require_enabled()
        ws = self._get_or_create_state(user_email)
        if not ws.path.is_dir():
            return ChangesSummary()
        base = self._base_ref(ws)
        numstat = self._parse_numstat(ws, base)

        files: list[ChangeFile] = []
        porcelain = self._git(ws.path, "status", "--porcelain").stdout
        for line in porcelain.splitlines():
            if not line:
                continue
            code = line[:2]
            rest = line[3:]
            if code == "??":
                status = "?"
                path = rest
            elif "U" in code:
                status = "U"
                path = rest
            else:
                status = code.strip()[0]
                path = rest.split(" -> ")[-1] if " -> " in rest else rest
            plus, minus = numstat.get(path, (0, 0))
            files.append(ChangeFile(path=path, status=status, plus=plus, minus=minus))

        # Committed-but-clean files (ahead of base) that porcelain won't list.
        seen = {f.path for f in files}
        for path, (plus, minus) in numstat.items():
            if path not in seen:
                files.append(ChangeFile(path=path, status="M", plus=plus, minus=minus))

        ahead, behind = 0, 0
        rl = self._git(
            ws.path, "rev-list", "--left-right", "--count", f"{base}...HEAD", check=False
        )
        if rl.returncode == 0:
            parts = rl.stdout.split()
            if len(parts) == 2:
                behind, ahead = int(parts[0]), int(parts[1])

        files.sort(key=lambda f: f.path)
        return ChangesSummary(files=files, ahead=ahead, behind=behind)

    def _default_validate_house(self, worktree: Path, rel_path: str) -> tuple[bool, str]:
        """Run the repo's house validator. Returns (ok, message)."""
        validator = worktree / ".claude" / "skills" / "house-design" / "validate.mjs"
        if not validator.is_file():
            return True, "validator not present; skipped"
        proc = subprocess.run(  # noqa: S603
            ["node", str(validator), rel_path],
            cwd=str(worktree),
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode == 0:
            return True, "valid"
        return False, (proc.stderr.strip() or proc.stdout.strip() or "validation failed")

    def _changed_house_files(self, ws: Workspace) -> list[str]:
        porcelain = self._git(ws.path, "status", "--porcelain").stdout
        houses: list[str] = []
        for line in porcelain.splitlines():
            if not line:
                continue
            rest = line[3:]
            path = rest.split(" -> ")[-1] if " -> " in rest else rest
            if path.startswith("houses/") and path.endswith(".house.json"):
                houses.append(path)
        return houses

    def publish(self, user_email: str, message: str | None = None) -> PublishResult:
        """Validate changed houses, commit, rebase onto origin/main, push HEAD:main."""
        self._require_enabled()
        ws = self._get_or_create_state(user_email)
        if not ws.path.is_dir():
            raise WorkspaceError("Workspace has no worktree yet")
        remote = self._settings.microapps_publish_remote

        # 1. Validate every changed house file before touching git.
        for rel in self._changed_house_files(ws):
            ok, detail = self._validate_house(ws.path, rel)
            if not ok:
                raise WorkspaceError(f"Invalid house '{rel}': {detail}")

        # 2. Stage + commit (if there is anything to commit).
        self._git(ws.path, "add", "-A")
        staged = self._git(ws.path, "diff", "--cached", "--name-only").stdout.strip()
        committed = False
        commit_sha: str | None = None
        if staged:
            msg = message or "Update micro-apps via Garbanzo agent"
            self._git(ws.path, "commit", "-m", msg)
            committed = True
            commit_sha = self._git(ws.path, "rev-parse", "--short", "HEAD").stdout.strip()

        # 3. Fetch + rebase onto origin/main; abort + report on conflict.
        self._git(ws.path, "fetch", remote, check=False)
        base = self._base_ref(ws)
        rebase = self._git(ws.path, "rebase", base, check=False)
        if rebase.returncode != 0:
            self._git(ws.path, "rebase", "--abort", check=False)
            raise WorkspaceError(
                f"Rebase onto {base} hit a conflict; nothing was pushed. "
                f"Resolve manually.\n{rebase.stderr.strip()}"
            )

        # 4. Push branch to main (single-remote personal repo, fast-forward),
        #    but only when this branch actually has commits origin/main lacks.
        pushed = False
        base = self._base_ref(ws)
        rl = self._git(
            ws.path, "rev-list", "--count", f"{base}..HEAD", check=False
        )
        ahead = int(rl.stdout.strip() or 0) if rl.returncode == 0 else (1 if committed else 0)
        if ahead > 0:
            push = self._git(ws.path, "push", remote, "HEAD:main", check=False)
            if push.returncode != 0:
                raise WorkspaceError(f"Push failed: {push.stderr.strip()}")
            pushed = True

        if not committed:
            summary = "No changes to publish."
        elif pushed:
            summary = f"Published {commit_sha} to main."
        else:
            summary = f"Committed {commit_sha} (not pushed)."
        return PublishResult(
            committed=committed, commit=commit_sha, pushed=pushed, message=summary
        )

    def revert(
        self, user_email: str, paths: list[str] | None = None, all_changes: bool = False
    ) -> ChangesSummary:
        """Discard changes. Scoped to ``paths`` or all when ``all_changes`` is set."""
        self._require_enabled()
        ws = self._get_or_create_state(user_email)
        if not ws.path.is_dir():
            raise WorkspaceError("Workspace has no worktree yet")

        if paths:
            safe = [self._safe_rel(ws, p) for p in paths]
            # Restore tracked modifications, then remove untracked files/dirs.
            self._git(ws.path, "checkout", "--", *safe, check=False)
            self._git(ws.path, "clean", "-fd", *safe, check=False)
        elif all_changes:
            self._git(ws.path, "checkout", "--", ".", check=False)
            self._git(ws.path, "clean", "-fd", check=False)
        else:
            raise WorkspaceError(
                "Refusing to revert everything without an explicit 'all' flag"
            )
        return self.changes(user_email)

    def _safe_rel(self, ws: Workspace, rel_path: str) -> str:
        """Reject paths that escape the worktree."""
        candidate = (ws.path / rel_path).resolve()
        try:
            candidate.relative_to(ws.path.resolve())
        except ValueError as exc:
            raise WorkspaceError(f"Path escapes workspace: {rel_path}") from exc
        return rel_path

    # -- house creation -----------------------------------------------------

    def create_house(
        self, user_email: str, name: str, template: str | None = None
    ) -> str:
        """Create ``houses/<slug>.house.json`` by copying a template. Returns rel path."""
        self._require_enabled()
        ws = self._get_or_create_state(user_email)
        houses_dir = ws.path / "houses"
        houses_dir.mkdir(parents=True, exist_ok=True)

        slug = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-") or "house"
        dest = houses_dir / f"{slug}.house.json"
        if dest.exists():
            raise WorkspaceError(f"House '{dest.name}' already exists")

        template_name = template or "tiny-cabin.house.json"
        src = houses_dir / template_name
        if src.is_file():
            shutil.copyfile(src, dest)
        else:
            # No template on disk — write a minimal valid-ish empty project.
            dest.write_text(
                json.dumps({"name": name, "floors": [], "version": 1}, indent=2),
                encoding="utf-8",
            )
        return f"houses/{dest.name}"


# Module-level singleton (created from live settings), mirroring app.scheduler.
manager = MicroappWorkspaceManager()
atexit.register(manager.stop_all)
