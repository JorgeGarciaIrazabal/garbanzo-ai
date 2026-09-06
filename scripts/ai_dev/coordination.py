"""Branchless worker coordination and stable preview checkpoints.

All durable controller data is private machine-local state under ``.ai/local``.
Workers receive committed Git archive snapshots and return patches; they never
write commits or merge directly into the coordinator's working tree.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import posixpath
import shutil
import signal
import stat
import subprocess
import tarfile
from collections.abc import Iterator, Sequence
from contextlib import contextmanager, suppress
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from typing import Any

from .common import environment


class CoordinationError(RuntimeError):
    """A handoff cannot safely be created or integrated."""


@dataclass(frozen=True)
class Assignment:
    task_id: str
    workspace: Path
    base_revision: str
    requirement_revision: str


def _run(root: Path, *args: str, input_text: str | None = None) -> str:
    result = subprocess.run(
        args,
        cwd=root,
        input=input_text,
        text=True,
        capture_output=True,
        env=environment(root),
        check=False,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise CoordinationError(f"command failed ({' '.join(args)}): {detail}")
    return result.stdout


def _local_dir(root: Path) -> Path:
    path = root / ".ai" / "local"
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path, 0o700)
    return path


def _safe_id(value: str) -> str:
    if not value or any(
        char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        for char in value
    ):
        raise CoordinationError(f"invalid identifier: {value!r}")
    return value


def _normalize_paths(paths: Sequence[str]) -> list[str]:
    normalized: list[str] = []
    for value in paths:
        path = PurePosixPath(value)
        if path.is_absolute() or not path.parts or ".." in path.parts or value.endswith("/"):
            raise CoordinationError(f"unsafe owned path: {value!r}")
        clean = path.as_posix()
        if clean == "." or clean.startswith(".git/") or clean.startswith(".ai/"):
            raise CoordinationError(f"unsafe owned path: {value!r}")
        normalized.append(clean)
    if len(set(normalized)) != len(normalized):
        raise CoordinationError("owned paths contain duplicates")
    return sorted(normalized)


def requirement_hash(
    requirements: str, dependencies: Sequence[str], acceptance: Sequence[str]
) -> str:
    payload = {
        "acceptance": list(acceptance),
        "dependencies": list(dependencies),
        "requirements": requirements,
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def _git_path_state(root: Path, revision: str, path: str) -> str | None:
    result = subprocess.run(
        ["git", "rev-parse", f"{revision}:{path}"],
        cwd=root,
        env=environment(root),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def create_assignment(
    root: Path,
    task_id: str,
    *,
    requirements: str,
    owned_files: Sequence[str],
    dependencies: Sequence[str] = (),
    acceptance: Sequence[str] = (),
    base_revision: str = "HEAD",
    review_required: bool = True,
) -> Assignment:
    """Create an isolated committed snapshot and its immutable assignment manifest."""
    task_id = _safe_id(task_id)
    owned = _normalize_paths(owned_files)
    revision = _run(root, "git", "rev-parse", "--verify", f"{base_revision}^{{commit}}").strip()
    revision_hash = requirement_hash(requirements, dependencies, acceptance)
    local = _local_dir(root)
    workers = local / "workers"
    workers.mkdir(mode=0o700, exist_ok=True)
    workspace = workers / task_id
    if workspace.exists():
        raise CoordinationError(f"assignment already exists: {task_id}")
    workspace.mkdir(mode=0o700)

    archive_path = workspace / ".snapshot.tar"
    try:
        with archive_path.open("wb") as archive:
            result = subprocess.run(
                ["git", "archive", "--format=tar", revision],
                cwd=root,
                env=environment(root),
                stdout=archive,
                stderr=subprocess.PIPE,
                check=False,
            )
        if result.returncode:
            raise CoordinationError(result.stderr.decode().strip())
        with tarfile.open(archive_path) as archive:
            _extract_archive_safely(archive, workspace)
    except Exception:
        shutil.rmtree(workspace, ignore_errors=True)
        raise
    finally:
        archive_path.unlink(missing_ok=True)

    manifest = {
        "acceptance": list(acceptance),
        "base_files": {path: _git_path_state(root, revision, path) for path in owned},
        "base_revision": revision,
        "created_at": datetime.now(UTC).isoformat(),
        "dependencies": list(dependencies),
        "owned_files": owned,
        "requirement_revision": revision_hash,
        "requirements": requirements,
        "review_required": review_required,
        "status": "active",
        "task_id": task_id,
    }
    _write_json(workspace / ".assignment.json", manifest)
    return Assignment(task_id, workspace, revision, revision_hash)


def _extract_archive_safely(archive: tarfile.TarFile, destination: Path) -> None:
    for member in archive.getmembers():
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise CoordinationError(f"unsafe archive member: {member.name}")
        if member.issym() or member.islnk():
            link = PurePosixPath(member.linkname)
            base = path.parent if member.issym() else PurePosixPath()
            resolved = posixpath.normpath((base / link).as_posix())
            if link.is_absolute() or resolved == ".." or resolved.startswith("../"):
                raise CoordinationError(f"unsafe archive link: {member.name}")
    archive.extractall(destination, filter="data")


def prepare_handoff(root: Path, task_id: str) -> Path:
    """Validate worker edits and write the patch artifact consumed by integration."""
    workspace, manifest = _load_assignment(root, task_id)
    owned = set(manifest["owned_files"])
    changed = _workspace_changes(root, workspace, manifest["base_revision"])
    extras = changed - owned
    if extras:
        raise CoordinationError(f"worker changed unowned files: {', '.join(sorted(extras))}")
    for relative in changed:
        candidate = workspace / relative
        if candidate.is_symlink():
            raise CoordinationError(f"worker output contains symlink: {relative}")

    patch = workspace / ".handoff.patch"
    # A temporary index compares the archive snapshot with the worker tree while
    # leaving both the worker and coordinator Git metadata untouched.
    index = workspace / ".handoff.index"
    env = os.environ.copy()
    env["GIT_INDEX_FILE"] = str(index)
    env["GIT_DIR"] = str(root / ".git")
    env["GIT_WORK_TREE"] = str(workspace)
    _git_with_env(workspace, env, "git", "read-tree", manifest["base_revision"])
    _git_with_env(workspace, env, "git", "add", "-A", "--", *manifest["owned_files"])
    diff = _git_with_env(workspace, env, "git", "diff", "--cached", "--binary", "--full-index")
    if not diff:
        raise CoordinationError("worker produced no owned-file changes")
    patch.write_text(diff, encoding="utf-8")
    index.unlink(missing_ok=True)
    os.chmod(patch, 0o600)
    manifest["handoff_files"] = sorted(changed)
    manifest["handoff_workspace"] = {
        relative: _workspace_digest(workspace / relative) for relative in sorted(changed)
    }
    manifest["handoff_sha256"] = hashlib.sha256(diff.encode()).hexdigest()
    manifest.pop("verification", None)
    manifest.pop("review", None)
    manifest["status"] = "ready"
    _write_json(workspace / ".assignment.json", manifest)
    return patch


def _git_with_env(root: Path, env: dict[str, str], *args: str) -> str:
    result = subprocess.run(args, cwd=root, env=env, text=True, capture_output=True)
    if result.returncode:
        raise CoordinationError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def _workspace_changes(root: Path, workspace: Path, revision: str) -> set[str]:
    tracked = set(
        _run(root, "git", "ls-tree", "-r", "--full-tree", "--name-only", revision).splitlines()
    )
    present: set[str] = set()
    ignored = {".assignment.json", ".handoff.patch", ".handoff.index"}
    ignored_directories = {".dart_tool", ".pytest_cache", ".venv", "__pycache__", "build"}
    for candidate in workspace.rglob("*"):
        relative = candidate.relative_to(workspace).as_posix()
        if (
            relative in ignored
            or relative.startswith(".git/")
            or any(part in ignored_directories for part in PurePosixPath(relative).parts)
            or candidate.is_dir()
        ):
            continue
        present.add(relative)
    changed = tracked ^ present
    for relative in tracked & present:
        candidate = workspace / relative
        content = (
            os.readlink(candidate).encode() if candidate.is_symlink() else candidate.read_bytes()
        )
        blob = hashlib.sha1(f"blob {len(content)}\0".encode() + content).hexdigest()
        if blob != _git_path_state(root, revision, relative):
            changed.add(relative)
    return changed


def record_verification(
    root: Path, task_id: str, *, command: Sequence[str], passed: bool, summary: str
) -> None:
    """Attach focused verification evidence to a prepared handoff."""
    workspace, manifest = _load_assignment(root, task_id)
    manifest.setdefault("verification", []).append(
        {
            "command": list(command),
            "handoff_sha256": manifest.get("handoff_sha256"),
            "passed": passed,
            "summary": summary,
            "timestamp": datetime.now(UTC).isoformat(),
        }
    )
    _write_json(workspace / ".assignment.json", manifest)


def record_review(
    root: Path, task_id: str, *, reviewer: str, reviewer_model: str, approved: bool, summary: str
) -> None:
    """Attach substantive independent review evidence to a handoff."""
    workspace, manifest = _load_assignment(root, task_id)
    if (
        not reviewer.strip()
        or reviewer == manifest.get("worker_session")
        or reviewer == manifest.get("codex_thread_id")
    ):
        raise CoordinationError("review must be independent from the implementation worker")
    if reviewer_model not in {"gpt-5.6-sol", "gpt-6-astra"}:
        raise CoordinationError("substantive review requires gpt-5.6-sol")
    manifest["review"] = {
        "approved": approved,
        "handoff_sha256": manifest.get("handoff_sha256"),
        "reviewer": reviewer,
        "reviewer_model": reviewer_model,
        "summary": summary,
        "timestamp": datetime.now(UTC).isoformat(),
    }
    _write_json(workspace / ".assignment.json", manifest)


def integrate_handoff(
    root: Path,
    task_id: str,
    *,
    requirement_revision: str,
    completed_dependencies: Sequence[str] = (),
) -> list[str]:
    """Apply a validated worker patch while holding the sole writer lock."""
    workspace, manifest = _load_assignment(root, task_id)
    if manifest.get("status") != "ready":
        raise CoordinationError("handoff is not ready")
    if requirement_revision != manifest["requirement_revision"]:
        raise CoordinationError("requirements changed since assignment")
    missing_dependencies = set(manifest["dependencies"]) - set(completed_dependencies)
    if missing_dependencies:
        raise CoordinationError(
            f"dependencies incomplete: {', '.join(sorted(missing_dependencies))}"
        )
    verification = manifest.get("verification", [])
    if not verification or not all(
        item.get("passed") and item.get("handoff_sha256") == manifest["handoff_sha256"]
        for item in verification
    ):
        raise CoordinationError("passing verification evidence is required")
    if not any(item.get("command", [])[:2] == ["just", "check"] for item in verification):
        raise CoordinationError("just check verification is required before commit")
    review = manifest.get("review", {})
    if manifest.get("review_required") and not (
        review.get("approved") and review.get("handoff_sha256") == manifest["handoff_sha256"]
    ):
        raise CoordinationError("approved independent review is required")
    patch = workspace / ".handoff.patch"
    if hashlib.sha256(patch.read_bytes()).hexdigest() != manifest["handoff_sha256"]:
        raise CoordinationError("handoff patch changed after validation")
    current_changes = _workspace_changes(root, workspace, manifest["base_revision"])
    if current_changes != set(manifest["handoff_files"]):
        raise CoordinationError("worker files changed after handoff preparation")
    for relative, expected in manifest["handoff_workspace"].items():
        if _workspace_digest(workspace / relative) != expected:
            raise CoordinationError(f"worker file changed after handoff preparation: {relative}")

    with writer_lock(root):
        if _run(root, "git", "branch", "--show-current").strip() != "main":
            raise CoordinationError("integration is restricted to main")
        for relative, expected in manifest["base_files"].items():
            if _git_path_state(root, "HEAD", relative) != expected:
                raise CoordinationError(f"base content changed: {relative}")
            status = _run(root, "git", "status", "--porcelain=v1", "--", relative)
            if status:
                raise CoordinationError(f"owned file has local edits: {relative}")
        check = subprocess.run(
            ["git", "apply", "--check", "--whitespace=error-all", str(patch)],
            cwd=root,
            env=environment(root),
            text=True,
            capture_output=True,
        )
        if check.returncode:
            raise CoordinationError(f"patch rejected: {check.stderr.strip()}")
        _run(root, "git", "apply", "--whitespace=error-all", str(patch))
        manifest["status"] = "integration_pending_commit"
        _write_json(workspace / ".assignment.json", manifest)
        message = f"{task_id}: integrate verified worker handoff"
        _run(root, "git", "commit", "--only", "-m", message, "--", *manifest["handoff_files"])
        manifest["commit_revision"] = _run(root, "git", "rev-parse", "HEAD").strip()
        manifest["status"] = "integrated"
        manifest["integrated_at"] = datetime.now(UTC).isoformat()
        _write_json(workspace / ".assignment.json", manifest)
    return manifest["handoff_files"]


@contextmanager
def writer_lock(root: Path) -> Iterator[None]:
    lock_path = _local_dir(root) / "writer.lock"
    with lock_path.open("a", encoding="utf-8") as handle:
        os.chmod(lock_path, 0o600)
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def create_preview(root: Path, name: str, *, source_revision: str = "HEAD") -> Path:
    """Create a stable archive preview tied to an exact committed revision."""
    name = _safe_id(name)
    revision = _run(root, "git", "rev-parse", "--verify", f"{source_revision}^{{commit}}").strip()
    target = _local_dir(root) / "previews" / name
    if target.exists():
        raise CoordinationError(f"preview already exists: {name}")
    target.mkdir(parents=True, mode=0o700)
    archive = target / "source.tar"
    with archive.open("wb") as handle:
        result = subprocess.run(
            ["git", "archive", revision],
            cwd=root,
            env=environment(root),
            stdout=handle,
            stderr=subprocess.PIPE,
        )
    if result.returncode:
        shutil.rmtree(target)
        raise CoordinationError(result.stderr.decode().strip())
    source = target / "source"
    source.mkdir(mode=0o700)
    with tarfile.open(archive) as bundle:
        _extract_archive_safely(bundle, source)
    port_offset = int(hashlib.sha256(name.encode()).hexdigest()[:4], 16) % 1000
    _write_json(
        target / "preview.json",
        {
            "created_at": datetime.now(UTC).isoformat(),
            "feedback": [],
            "name": name,
            "namespace": f"garbanzo-preview-{name}",
            "ports": {"backend": 18000 + port_offset, "frontend": 19000 + port_offset},
            "source_revision": revision,
            "verification": "created_unverified",
        },
    )
    return target


def add_preview_feedback(root: Path, name: str, feedback: str) -> dict[str, Any]:
    metadata_path = _local_dir(root) / "previews" / _safe_id(name) / "preview.json"
    metadata = _read_json(metadata_path)
    entry = {
        "created_at": datetime.now(UTC).isoformat(),
        "source_revision": metadata["source_revision"],
        "text": feedback,
    }
    metadata["feedback"].append(entry)
    _write_json(metadata_path, metadata)
    return entry


def verify_preview(
    root: Path, name: str, *, command: Sequence[str], passed: bool, summary: str
) -> dict[str, Any]:
    metadata_path = _local_dir(root) / "previews" / _safe_id(name) / "preview.json"
    metadata = _read_json(metadata_path)
    evidence = {
        "command": list(command),
        "passed": passed,
        "summary": summary,
        "timestamp": datetime.now(UTC).isoformat(),
    }
    metadata["launch_verification"] = evidence
    metadata["verification"] = "ready_for_testing" if passed else "launch_failed"
    _write_json(metadata_path, metadata)
    return metadata


def record_session(
    root: Path,
    session_id: str,
    *,
    pid: int | None,
    command: Sequence[str],
    status: str = "running",
    cwd: Path | None = None,
) -> None:
    session_id = _safe_id(session_id)
    path = _local_dir(root) / "sessions" / f"{session_id}.json"
    _write_json(
        path,
        {
            "command": list(command),
            "pid": pid,
            "pid_start": _pid_start(pid),
            "cwd": str(cwd or root),
            "session_id": session_id,
            "status": status,
            "updated_at": datetime.now(UTC).isoformat(),
        },
    )


def session_status(root: Path, session_id: str) -> dict[str, Any]:
    path = _local_dir(root) / "sessions" / f"{_safe_id(session_id)}.json"
    state = _read_json(path)
    pid = state.get("pid")
    alive = False
    if pid and state.get("pid_start") == _pid_start(pid):
        try:
            os.kill(pid, 0)
            alive = True
        except ProcessLookupError:
            pass
    state["alive"] = alive
    if state["status"] == "running" and not alive:
        state["status"] = "stopped"
        _write_json(path, state)
    return state


def stop_session(root: Path, session_id: str) -> dict[str, Any]:
    state = session_status(root, session_id)
    if state["alive"]:
        with suppress(ProcessLookupError):
            os.killpg(state["pid"], signal.SIGTERM)
    state["status"] = "stopped"
    state["updated_at"] = datetime.now(UTC).isoformat()
    _write_json(_local_dir(root) / "sessions" / f"{_safe_id(session_id)}.json", state)
    return state


def resume_session(root: Path, session_id: str) -> subprocess.Popen[bytes]:
    state = session_status(root, session_id)
    if state["alive"]:
        raise CoordinationError("session is already running")
    process = subprocess.Popen(
        state["command"],
        cwd=state.get("cwd", root),
        env=environment(root),
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    record_session(
        root,
        session_id,
        pid=process.pid,
        command=state["command"],
        cwd=Path(state.get("cwd", root)),
    )
    return process


def _pid_start(pid: int | None) -> str | None:
    if not pid:
        return None
    try:
        return Path(f"/proc/{pid}/stat").read_text().split()[21]
    except (OSError, IndexError):
        return None


def _load_assignment(root: Path, task_id: str) -> tuple[Path, dict[str, Any]]:
    workspace = _local_dir(root) / "workers" / _safe_id(task_id)
    return workspace, _read_json(workspace / ".assignment.json")


def _workspace_digest(path: Path) -> str | None:
    if not path.exists() and not path.is_symlink():
        return None
    content = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
    return hashlib.sha256(content).hexdigest()


def assignment_state(root: Path, task_id: str) -> dict[str, Any]:
    """Return a copy of persisted assignment state for CLI and executors."""
    _, manifest = _load_assignment(root, task_id)
    return manifest


def update_assignment(root: Path, task_id: str, **values: Any) -> dict[str, Any]:
    """Persist coordinator-owned execution metadata on an assignment."""
    workspace, manifest = _load_assignment(root, task_id)
    manifest.update(values)
    manifest["updated_at"] = datetime.now(UTC).isoformat()
    _write_json(workspace / ".assignment.json", manifest)
    return manifest


def _read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CoordinationError(f"cannot read state {path}: {error}") from error


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, stat.S_IRUSR | stat.S_IWUSR)
    temporary.replace(path)
