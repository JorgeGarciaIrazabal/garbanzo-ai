"""Deterministic admission and bounded execution for the overnight lane."""

from __future__ import annotations

import contextlib
import fcntl
import json
import os
import subprocess
import threading
import time as wall_time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from . import beads, execution, models
from .app_server import AppServerClient
from .capacity import Allowance, codex_allowances, evaluate
from .common import environment, local_dir, read_json, write_json
from .processes import stop_tree

NIGHT_ZONE = ZoneInfo("America/New_York")
START = time(0, 0)
END = time(6, 0)
MAX_TASKS = 2
MAX_RUNTIME = timedelta(minutes=60)
DISALLOWED_LABELS = frozenset(
    {
        "architecture",
        "authentication",
        "auth",
        "migration",
        "deployment",
        "deploy",
        "automation-policy",
    }
)
DISALLOWED_PATH_PARTS = frozenset(
    {"migrations", "deploy", ".github", ".codex", ".agents", ".claude", ".ai", "ai_dev"}
)
ALLOWED_TOP_LEVEL_PATHS = frozenset({"backend", "lib", "test", "docs"})
DISALLOWED_NAME_FRAGMENTS = (
    "auth",
    "migration",
    "deploy",
    "architecture",
    "automation",
    "policy",
    "secret",
    "credential",
)


@dataclass(frozen=True)
class NightTask:
    id: str
    labels: frozenset[str]
    owned_paths: tuple[str, ...] = ()
    clear: bool = True
    low_risk: bool = True


@dataclass(frozen=True)
class NightResult:
    task_id: str
    success: bool
    attempts: int
    detail: str


def within_window(value: datetime) -> bool:
    local = value.astimezone(NIGHT_ZONE)
    return START <= local.time() < END


def select_tasks(tasks: Sequence[NightTask]) -> list[NightTask]:
    def safe(task: NightTask) -> bool:
        path_parts = {part for path in task.owned_paths for part in Path(path).parts}
        normalized_parts = {part.lower() for part in path_parts}
        top_levels = {Path(path).parts[0] for path in task.owned_paths if Path(path).parts}
        sensitive_name = any(
            fragment in part for part in normalized_parts for fragment in DISALLOWED_NAME_FRAGMENTS
        )
        return (
            task.clear
            and task.low_risk
            and bool(task.owned_paths)
            and top_levels <= ALLOWED_TOP_LEVEL_PATHS
            and not sensitive_name
            and not (task.labels & DISALLOWED_LABELS)
            and not (normalized_parts & DISALLOWED_PATH_PARTS)
        )

    return [task for task in tasks if safe(task)][:MAX_TASKS]


class NightlyRunner:
    def __init__(
        self,
        capacity_reader: Callable[[], list[Allowance]],
        *,
        foreground_active: Callable[[], bool],
        state_path: Path | None = None,
        poll_seconds: float = 5.0,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self.capacity_reader = capacity_reader
        self.foreground_active = foreground_active
        self.state_path = state_path
        self.poll_seconds = poll_seconds
        self.clock = clock or (lambda: datetime.now(UTC))

    def run(
        self,
        tasks: Sequence[NightTask],
        worker: Callable[[NightTask, threading.Event], tuple[bool, str]],
        *,
        now: datetime,
        triage: Callable[[], None] | None = None,
        timeout_seconds: float = MAX_RUNTIME.total_seconds(),
    ) -> list[NightResult]:
        if not within_window(now) or self.foreground_active():
            return []
        if not evaluate(
            self.capacity_reader(), unattended=True, now=self.clock()
        ).allowed_unattended:
            return []
        if not self._claim_batch(now):
            return []
        started = datetime.now(NIGHT_ZONE)
        if triage is not None:
            triage()
        results: list[NightResult] = []
        for task in select_tasks(tasks):
            remaining = timeout_seconds - (datetime.now(NIGHT_ZONE) - started).total_seconds()
            if remaining <= 0 or self.foreground_active():
                break
            if not evaluate(
                self.capacity_reader(), unattended=True, now=self.clock()
            ).allowed_unattended:
                break
            results.append(self._run_task(task, worker, remaining))
        return results

    def _run_task(
        self,
        task: NightTask,
        worker: Callable[[NightTask, threading.Event], tuple[bool, str]],
        remaining: float,
    ) -> NightResult:
        cancel = threading.Event()
        outcome: list[tuple[bool, str]] = []

        def execute() -> None:
            for _attempt in range(2):
                if (
                    self.foreground_active()
                    or not evaluate(
                        self.capacity_reader(), unattended=True, now=self.clock()
                    ).allowed_unattended
                ):
                    cancel.set()
                    outcome.append((False, "cancelled by foreground or capacity guard"))
                    return
                success, detail = worker(task, cancel)
                outcome.append((success, detail))
                if success:
                    return

        thread = threading.Thread(target=execute, daemon=True)
        thread.start()
        deadline = datetime.now(NIGHT_ZONE) + timedelta(seconds=max(0.0, remaining))
        while thread.is_alive():
            seconds_left = (deadline - datetime.now(NIGHT_ZONE)).total_seconds()
            if seconds_left <= 0:
                cancel.set()
                thread.join(10)
                if thread.is_alive():
                    raise RuntimeError("worker did not acknowledge deadline cancellation")
                return NightResult(task.id, False, len(outcome), "60 minute batch limit reached")
            thread.join(min(self.poll_seconds, seconds_left))
            if thread.is_alive() and (
                self.foreground_active()
                or not evaluate(
                    self.capacity_reader(), unattended=True, now=self.clock()
                ).allowed_unattended
            ):
                cancel.set()
                thread.join(10)
                if thread.is_alive():
                    raise RuntimeError("worker did not acknowledge cancellation; batch stopped")
                return NightResult(
                    task.id, False, len(outcome), "cancelled by foreground or capacity guard"
                )
        success, detail = outcome[-1] if outcome else (False, "worker produced no result")
        return NightResult(task.id, success, len(outcome), detail)

    def _claim_batch(self, now: datetime) -> bool:
        if self.state_path is None:
            return True
        night = now.astimezone(NIGHT_ZONE).date().isoformat()
        self.state_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        lock_path = self.state_path.with_suffix(".lock")
        with lock_path.open("a", encoding="utf-8") as lock_stream:
            fcntl.flock(lock_stream, fcntl.LOCK_EX)
            try:
                prior = json.loads(self.state_path.read_text()) if self.state_path.exists() else {}
            except (json.JSONDecodeError, OSError):
                return False
            if prior.get("night") == night:
                return False
            temporary = self.state_path.with_suffix(f".{os.getpid()}.tmp")
            temporary.write_text(json.dumps({"night": night}) + "\n")
            temporary.chmod(0o600)
            os.replace(temporary, self.state_path)
            return True


def foreground_active(root: Path) -> bool:
    with (local_dir(root) / "foreground.lock").open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)
    return False


def guarded_process(
    root: Path, command: list[str], deadline: float, log: Path, capacity_reader
) -> bool:
    """The parent stays alive to cancel all descendants, including separate sessions."""
    if foreground_active(root) or not within_window(datetime.now(UTC)):
        return False
    if not evaluate(capacity_reader(), unattended=True).allowed_unattended:
        return False
    child_environment = environment(root)
    child_environment["AI_NIGHTLY_CHILD"] = "1"
    with log.open("w") as stream:
        log.chmod(0o600)
        process = subprocess.Popen(
            command,
            cwd=root,
            env=child_environment,
            stdout=stream,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            while process.poll() is None:
                if (
                    wall_time.monotonic() >= deadline
                    or foreground_active(root)
                    or not within_window(datetime.now(UTC))
                    or not evaluate(capacity_reader(), unattended=True).allowed_unattended
                ):
                    stop_tree(process)
                    return False
                with contextlib.suppress(subprocess.TimeoutExpired):
                    process.wait(timeout=min(2, max(0.01, deadline - wall_time.monotonic())))
        except BaseException:
            stop_tree(process)
            raise
    return process.returncode == 0


def handle(args) -> dict[str, object]:
    now = datetime.now(UTC)
    if not within_window(now):
        return {"status": "outside_window", "results": []}
    if foreground_active(args.root):
        return {"status": "foreground_active", "results": []}
    catalog = read_json(local_dir(args.root) / "models.json", {})
    if models.catalog_is_stale(local_dir(args.root) / "models.json"):
        return {
            "status": "paused",
            "reason": "model catalog requires weekly refresh",
            "results": [],
        }
    # Native Codex workers use only their own allowance; a missing Ollama cookie
    # must pause Ollama, not block an independently qualified Codex provider.
    required = {"codex:gpt-5.6-terra", "codex:gpt-5.6-sol"}
    if not required.issubset(set(catalog.get("promoted", []))):
        return {
            "status": "paused",
            "reason": "worker and reviewer models require qualification",
            "results": [],
        }

    def capacity_reader():
        try:
            with AppServerClient() as client:
                return codex_allowances(client)
        except (OSError, RuntimeError):
            return []

    allowance = evaluate(capacity_reader(), unattended=True)
    if not allowance.allowed_unattended:
        return {"status": "paused", "capacity": allowance.structured(), "results": []}
    runner = NightlyRunner(
        capacity_reader,
        foreground_active=lambda: foreground_active(args.root),
        state_path=local_dir(args.root) / "nightly-state.json",
    )
    if not runner._claim_batch(now):
        return {"status": "already_ran", "results": []}
    deadline = wall_time.monotonic() + min(
        3600,
        (
            datetime.combine(now.astimezone(NIGHT_ZONE).date(), END, NIGHT_ZONE) - now
        ).total_seconds(),
    )
    directory = local_dir(args.root) / "nightly" / now.astimezone(NIGHT_ZONE).date().isoformat()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not guarded_process(
        args.root,
        ["just", "ai-triage", "--json"],
        deadline,
        directory / "triage.log",
        capacity_reader,
    ):
        return {"status": "collection_failed_or_cancelled", "results": []}
    candidates = []
    for row in beads.call(args.root, "ready"):
        metadata = row.get("metadata") or {}
        labels = frozenset(row.get("labels", []))
        paths = metadata.get("owned_files", [])
        if (
            "nightly-safe" in labels
            and paths
            and metadata.get("verification_commands")
            and (row.get("acceptance_criteria") or row.get("acceptance"))
        ):
            candidates.append(NightTask(row["id"], labels, tuple(paths)))
    results = []
    for task in select_tasks(candidates):
        for attempt in range(2):
            ok = guarded_process(
                args.root,
                ["just", "ai-nightly-worker", task.id, "--json"],
                deadline,
                directory / f"{task.id}-{attempt}.log",
                capacity_reader,
            )
            if (
                ok
                or wall_time.monotonic() >= deadline
                or foreground_active(args.root)
                or not evaluate(capacity_reader(), unattended=True).allowed_unattended
            ):
                break
        results.append({"task_id": task.id, "success": ok, "attempts": attempt + 1})
        if not ok:
            break
    result = {"status": "completed", "results": results}
    write_json(directory / "result.json", result)
    return result


def register(subparsers) -> None:
    subparsers.add_parser("nightly", help="Run one bounded overnight batch").set_defaults(
        func=handle
    )
    parser = subparsers.add_parser(
        "nightly-worker", help="Internal bounded worker (launched by overnight guard)"
    )
    parser.add_argument("task_id")
    parser.set_defaults(func=worker_handle)


def worker_handle(args):
    if not within_window(datetime.now(UTC)):
        raise RuntimeError("nightly worker outside allowed window")
    row = execution._task(args.root, args.task_id)
    metadata = row.get("metadata") or {}
    task = NightTask(
        args.task_id, frozenset(row.get("labels", [])), tuple(metadata.get("owned_files", []))
    )
    if not select_tasks([task]) or "nightly-safe" not in task.labels or not task.owned_paths:
        raise RuntimeError("task is not admitted for overnight work")
    if not (local_dir(args.root) / "workers" / args.task_id).exists():
        execution.assign(args.root, args.task_id, task.owned_paths, kind="routine")
    execution.execute(args.root, args.task_id, timeout=1800)
    result = execution.verify(args.root, args.task_id, metadata["verification_commands"])
    if not result["passed"]:
        raise RuntimeError("focused verification failed; one repair may be attempted")
    review = execution.review_independently(args.root, args.task_id)
    if not review["approved"]:
        raise RuntimeError("independent review rejected the handoff")
    integrated = execution.commit_integration(args.root, args.task_id)
    return {
        "task_id": args.task_id,
        "status": "committed",
        "revision": integrated["revision"],
    }
