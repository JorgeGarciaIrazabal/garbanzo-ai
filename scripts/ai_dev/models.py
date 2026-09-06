"""Account model discovery, explicit routing, and evidence-based qualification."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Protocol

from .app_server import AppServerClient, paginated
from .common import local_dir, read_json, write_json

CATALOG_MAX_AGE = timedelta(days=7)
REQUIRED_SCENARIOS = frozenset({"tool_call", "patch", "test", "interrupt", "failure_report"})
HARNESS_VERSION = 1
ROUTES = {
    "architecture": ("gpt-6-astra", "medium"),
    "design": ("gpt-6-astra", "medium"),
    "complex": ("gpt-5.6-sol", "medium"),
    "review": ("gpt-5.6-sol", "medium"),
    "routine": ("gpt-5.6-terra", "medium"),
    "exploration": ("gpt-5.6-luna", "medium"),
}
REQUESTED_OLLAMA_FAMILIES = ("glm-5.3", "kimi-k3", "deepseek-v4-pro", "deepseek-v4-flash")


class QualificationHarness(Protocol):
    def run(self, model: str, scenario: str) -> tuple[bool, str]: ...


class CodexQualificationHarness:
    """Real isolated Codex smoke scenarios with machine-checkable outcomes."""

    def __init__(self, evidence_root: Path, *, provider: str = "codex", timeout: int = 90) -> None:
        self.evidence_root = evidence_root
        self.provider = provider
        self.timeout = timeout

    def run(self, model: str, scenario: str) -> tuple[bool, str]:
        directory = self.evidence_root / model / scenario
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.TemporaryDirectory(prefix="qualify-") as temporary:
            workspace = Path(temporary)
            (workspace / "seed.txt").write_text("before\n")
            (workspace / "justfile").write_text(
                "verify:\n    @test -f patched.txt\n\nfail:\n    @false\n"
            )
            prompts = {
                "tool_call": "Use the shell tool to run `pwd`, then say done.",
                "patch": "Use apply_patch to create patched.txt containing exactly qualified, then say done.",
                "test": "Create patched.txt, run `just verify`, and report whether it passed.",
                "failure_report": "Run `just fail` and clearly report that the command failed.",
                "interrupt": "Use the shell tool to run `sleep 30`, then say done.",
            }
            events = directory / "events.jsonl"
            command = [
                "codex",
                "exec",
                "--skip-git-repo-check",
                "--json",
                "--sandbox",
                "workspace-write",
            ]
            if self.provider == "ollama":
                command += ["--oss", "--local-provider", "ollama"]
            command += ["--model", model, "-"]
            started = time.monotonic()
            with events.open("w", encoding="utf-8") as output:
                process = subprocess.Popen(
                    command,
                    cwd=workspace,
                    stdin=subprocess.PIPE,
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    text=True,
                    start_new_session=True,
                )
                if scenario == "interrupt":
                    assert process.stdin is not None
                    process.stdin.write(prompts[scenario])
                    process.stdin.close()
                    self._wait_for_running_command(events, "sleep 30", process)
                    self._terminate(process)
                else:
                    try:
                        process.communicate(prompts[scenario], timeout=self.timeout)
                    except subprocess.TimeoutExpired:
                        self._terminate(process)
            text = events.read_text(encoding="utf-8", errors="replace")
            elapsed = time.monotonic() - started
            passed = self._validate(scenario, process.returncode, text, workspace, elapsed)
            summary = directory / "result.json"
            summary.write_text(
                json.dumps(
                    {
                        "passed": passed,
                        "returnCode": process.returncode,
                        "elapsedSeconds": round(elapsed, 3),
                    },
                    indent=2,
                )
                + "\n"
            )
            summary.chmod(0o600)
            return passed, str(summary)

    def _wait_for_running_command(self, path: Path, command: str, process) -> bool:
        deadline = time.monotonic() + min(self.timeout, 30)
        while time.monotonic() < deadline and process.poll() is None:
            for event in self._events(path.read_text(errors="replace")):
                item = event.get("item", {})
                if (
                    event.get("type") == "item.started"
                    and item.get("type") == "command_execution"
                    and command in item.get("command", "")
                ):
                    return True
            time.sleep(0.1)
        return False

    @staticmethod
    def _terminate(process) -> None:
        if process.poll() is not None:
            return
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)

    @staticmethod
    def _events(text: str) -> list[dict[str, Any]]:
        result = []
        for line in text.splitlines():
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                result.append(value)
        return result

    @staticmethod
    def _validate(scenario: str, code: int, events: str, workspace: Path, elapsed: float) -> bool:
        rows = CodexQualificationHarness._events(events)
        commands = [
            row.get("item", {})
            for row in rows
            if row.get("item", {}).get("type") == "command_execution"
        ]
        terminal = [item for item in commands if item.get("status") in {"completed", "failed"}]
        if scenario == "interrupt":
            started = any(
                "sleep 30" in item.get("command", "") and item.get("status") == "in_progress"
                for item in commands
            )
            return started and code != 0 and elapsed < 40
        if code != 0:
            return False
        if scenario == "patch":
            return (
                (workspace / "patched.txt").read_text().strip() == "qualified"
                if (workspace / "patched.txt").exists()
                else False
            )
        if scenario == "test":
            return (workspace / "patched.txt").exists() and any(
                "just verify" in item.get("command", "") and item.get("exit_code") == 0
                for item in terminal
            )
        if scenario == "failure_report":
            failed = any(
                "just fail" in item.get("command", "")
                and item.get("status") == "failed"
                and item.get("exit_code") not in (None, 0)
                for item in terminal
            )
            messages = " ".join(
                str(row.get("item", {}).get("text", ""))
                for row in rows
                if row.get("item", {}).get("type") == "agent_message"
            ).lower()
            return failed and any(
                word in messages for word in ("failed", "failure", "exit code", "did not pass")
            )
        return any(item.get("exit_code") == 0 for item in terminal)


@dataclass(frozen=True)
class Qualification:
    model: str
    tested_at: str
    checks: dict[str, bool]
    evidence: dict[str, str]
    provider: str = "codex"
    harness_version: int = HARNESS_VERSION
    catalog_refreshed_at: str | None = None

    @property
    def qualified(self) -> bool:
        return self.checks.keys() >= REQUIRED_SCENARIOS and all(
            self.checks[name] and bool(self.evidence.get(name)) for name in REQUIRED_SCENARIOS
        )


def discover(client: AppServerClient) -> list[dict[str, Any]]:
    models: list[dict[str, Any]] = []
    for page in paginated(client, "model/list", {"includeHidden": False}):
        for item in page["data"]:
            if isinstance(item, dict) and isinstance(item.get("id"), str):
                models.append(item)
    return models


def resolve_route(kind: str, catalog: list[dict[str, Any]]) -> dict[str, str]:
    requested_model, requested_effort = ROUTES[kind]
    available = {str(item["id"]): item for item in catalog if "id" in item}
    if requested_model not in available:
        raise ValueError(
            f"required model {requested_model!r} is unavailable; refusing silent downgrade"
        )
    item = available[requested_model]
    efforts = [
        option.get("reasoningEffort") for option in item.get("supportedReasoningEfforts", [])
    ]
    if efforts and requested_effort not in efforts:
        raise ValueError(
            f"required reasoning effort {requested_effort!r} is unavailable for {requested_model!r}; "
            "refusing silent downgrade"
        )
    return {"model": requested_model, "reasoningEffort": requested_effort}


def qualify(
    model: str,
    harness: QualificationHarness,
    *,
    provider: str = "codex",
    catalog_refreshed_at: str | None = None,
) -> Qualification:
    checks: dict[str, bool] = {}
    evidence: dict[str, str] = {}
    for scenario in sorted(REQUIRED_SCENARIOS):
        passed, detail = harness.run(model, scenario)
        checks[scenario] = bool(passed)
        evidence[scenario] = detail.strip()
    return Qualification(
        model,
        datetime.now(UTC).isoformat(),
        checks,
        evidence,
        provider,
        HARNESS_VERSION,
        catalog_refreshed_at,
    )


def save_catalog(
    path: Path, models: list[dict[str, Any]], qualifications: list[Qualification]
) -> None:
    promoted = [f"{item.provider}:{item.model}" for item in qualifications if item.qualified]
    payload = {
        "schemaVersion": 1,
        "refreshedAt": datetime.now(UTC).isoformat(),
        "models": models,
        "qualifications": [asdict(item) | {"qualified": item.qualified} for item in qualifications],
        "promoted": promoted,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")
    path.chmod(0o600)


def catalog_is_stale(path: Path, *, now: datetime | None = None) -> bool:
    if not path.exists():
        return True
    try:
        refreshed = datetime.fromisoformat(json.loads(path.read_text())["refreshedAt"])
    except (KeyError, ValueError, TypeError, json.JSONDecodeError):
        return True
    return (now or datetime.now(UTC)) - refreshed.astimezone(UTC) >= CATALOG_MAX_AGE


def current_catalog(client: AppServerClient | None = None) -> list[dict[str, Any]]:
    if client is not None:
        return discover(client)
    with AppServerClient() as owned_client:
        return discover(owned_client)


def discover_ollama(*, api_key: str | None = None, timeout: float = 20) -> dict[str, Any]:
    request = urllib.request.Request("https://ollama.com/api/tags")
    key = api_key or os.environ.get("OLLAMA_API_KEY")
    if key:
        request.add_header("Authorization", f"Bearer {key}")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.load(response)
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Ollama catalog collection failed: {exc}") from exc
    rows = payload.get("models") if isinstance(payload, dict) else None
    if not isinstance(rows, list):
        raise RuntimeError("Ollama catalog returned an invalid schema")
    models = [
        row
        for row in rows
        if isinstance(row, dict) and isinstance(row.get("model") or row.get("name"), str)
    ]
    names = {str(row.get("model") or row.get("name")) for row in models}
    available = {
        family: any(name == family or name.startswith(f"{family}:") for name in names)
        for family in REQUESTED_OLLAMA_FAMILIES
    }
    return {"models": models, "requestedFamilies": available}


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "models", help="Refresh the account-accessible Codex model catalog"
    )
    parser.set_defaults(func=handle, action="refresh")
    actions = parser.add_subparsers(dest="action")
    actions.add_parser("refresh")
    ollama = actions.add_parser(
        "ollama", help="Discover the account-accessible Ollama cloud catalog"
    )
    ollama.add_argument("--api-key")
    qualify_parser = actions.add_parser("qualify", help="Run real isolated qualification scenarios")
    qualify_parser.add_argument("--model", required=True)
    qualify_parser.add_argument("--provider", choices=("codex", "ollama"), required=True)


def handle(args) -> dict[str, Any]:
    path = local_dir(args.root) / "models.json"
    existing = read_json(path, {}) or {}
    if args.action == "qualify":
        catalog = (
            existing.get("models", [])
            if args.provider == "codex"
            else existing.get("ollama", {}).get("models", [])
        )
        names = {item.get("id") or item.get("model") or item.get("name") for item in catalog}
        if args.model not in names:
            raise ValueError(f"model {args.model!r} is not in the refreshed account catalog")
        refreshed = (
            existing.get("refreshedAt")
            if args.provider == "codex"
            else existing.get("ollamaRefreshedAt")
        )
        result = qualify(
            args.model,
            CodexQualificationHarness(
                local_dir(args.root) / "qualification", provider=args.provider
            ),
            provider=args.provider,
            catalog_refreshed_at=refreshed,
        )
        prior = [
            item
            for item in existing.get("qualifications", [])
            if (item.get("provider", "codex"), item.get("model")) != (args.provider, args.model)
        ]
        qualifications = prior + [asdict(result) | {"qualified": result.qualified}]
        existing["qualifications"] = qualifications
        existing["promoted"] = sorted(
            f"{item.get('provider', 'codex')}:{item['model']}"
            for item in qualifications
            if item.get("qualified")
        )
        write_json(path, existing)
        path.chmod(0o600)
        return qualifications[-1]
    if args.action == "ollama":
        result = discover_ollama(api_key=args.api_key)
        existing["ollama"] = result
        existing["ollamaRefreshedAt"] = datetime.now(UTC).isoformat()
        write_json(path, existing)
        path.chmod(0o600)
        return result
    models = current_catalog()
    payload = {
        "schemaVersion": 1,
        "refreshedAt": datetime.now(UTC).isoformat(),
        "models": models,
        # Discovery never implies qualification; retain only prior evidence-backed records.
        "qualifications": existing.get("qualifications", []),
        "promoted": existing.get("promoted", []),
    }
    if "ollama" in existing:
        payload["ollama"] = existing["ollama"]
        payload["ollamaRefreshedAt"] = existing.get("ollamaRefreshedAt")
    write_json(path, payload)
    path.chmod(0o600)
    return payload
