"""Private state, bounded subprocesses, and project tool resolution."""

import contextlib
import fcntl
import json
import os
import subprocess
import tempfile
from pathlib import Path


class WorkflowError(RuntimeError):
    """An actionable workflow failure, safe to display to the user."""


def local_dir(root: Path) -> Path:
    path = root / ".ai/local"
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    return path


def environment(root: Path) -> dict[str, str]:
    env = os.environ.copy()
    env["PATH"] = (
        str(root / ".ai/tools/bin")
        + os.pathsep
        + str(root / ".ai/tools/node_modules/.bin")
        + os.pathsep
        + env.get("PATH", "")
    )
    env["QMD_FORCE_CPU"] = "1"
    env["QMD_EMBED_PARALLELISM"] = "1"
    return env


def foreground_command(command: str) -> bool:
    """Return whether a command must preempt unattended provider work."""
    return command in {"guided", "run", "batch", "reports", "triage", "incident"}


def run(root: Path, argv: list[str], timeout: float = 60, *, input: str | None = None) -> str:
    try:
        result = subprocess.run(
            argv,
            cwd=root,
            env=environment(root),
            input=input,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as exc:
        raise WorkflowError(f"{argv[0]} is missing; run just ai-setup --install") from exc
    except subprocess.TimeoutExpired as exc:
        raise WorkflowError(f"{argv[0]} timed out after {timeout}s") from exc
    if result.returncode:
        # Subprocess stderr may contain private report payloads or credentials.
        path = local_dir(root) / "last-command-error.txt"
        path.write_text(result.stderr + result.stdout)
        path.chmod(0o600)
        raise WorkflowError(f"{argv[0]} failed (exit {result.returncode}); private details: {path}")
    return result.stdout


def read_json(path: Path, default=None):
    return json.loads(path.read_text()) if path.exists() else default


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".write-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write("\n")
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def write_text(path: Path, value: str, *, mode: int | None = None) -> None:
    """Atomically replace a text artifact without exposing a truncated view."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".write-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(value)
        if mode is not None:
            os.chmod(name, mode)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


@contextlib.contextmanager
def lock(root: Path, name: str = "writer"):
    with (local_dir(root) / f"{name}.lock").open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise WorkflowError(f"{name} is busy; retry after the active operation") from exc
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)
