"""Read-only, report-specific behavior checks against the deployed backend."""

from __future__ import annotations

import argparse
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from .common import WorkflowError

DEFAULT_BASE_URL = "http://127.0.0.1:8001"
FORBIDDEN_PATHS = frozenset({"/health", "/api/v1/health"})


def load_spec(root: Path, path: Path, report_id: str) -> dict[str, Any]:
    resolved = (root / path).resolve() if not path.is_absolute() else path.resolve()
    checks_root = (root / "scripts/ai_checks").resolve()
    if not resolved.is_relative_to(checks_root) or resolved.suffix != ".json":
        raise WorkflowError("behavior specs must be tracked JSON under scripts/ai_checks")
    try:
        relative = resolved.relative_to(root)
    except ValueError as exc:
        raise WorkflowError("behavior spec is outside the repository") from exc
    if not (root / ".git").exists():
        raise WorkflowError("behavior verification requires a Git repository")
    from .common import run

    tracked = run(root, ["git", "ls-files", "--error-unmatch", relative.as_posix()]).strip()
    if tracked != relative.as_posix():
        raise WorkflowError("behavior spec must be committed and tracked")
    value = json.loads(resolved.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("report_id") != report_id:
        raise WorkflowError("behavior spec report_id does not match the requested report")
    if value.get("method", "GET") != "GET":
        raise WorkflowError("deployed behavior checks are read-only GET requests")
    request_path = str(value.get("path", ""))
    parsed = urllib.parse.urlsplit(request_path)
    if not request_path.startswith("/") or parsed.scheme or parsed.netloc:
        raise WorkflowError("behavior spec path must be an absolute URL path")
    if parsed.path.rstrip("/") in FORBIDDEN_PATHS:
        raise WorkflowError("health endpoints do not verify reported behavior")
    expected = value.get("expect")
    if not isinstance(expected, dict) or not expected:
        raise WorkflowError("behavior spec requires explicit response assertions")
    assertion_keys = set(expected) - {"status"}
    if not assertion_keys:
        raise WorkflowError("HTTP status alone does not verify reported behavior")
    json_equals = expected.get("json_equals", {})
    if (
        isinstance(json_equals, dict)
        and set(json_equals) <= {"version", "status"}
        and not expected.get("text_contains")
    ):
        raise WorkflowError("version-only checks do not verify reported behavior")
    return value


def _lookup(value: Any, dotted: str) -> Any:
    current = value
    for part in dotted.split("."):
        if isinstance(current, dict) and part in current:
            current = current[part]
        elif isinstance(current, list) and part.isdigit() and int(part) < len(current):
            current = current[int(part)]
        else:
            raise WorkflowError(f"response is missing asserted field {dotted!r}")
    return current


def execute(
    root: Path, spec_path: Path, report_id: str, *, opener=urllib.request.urlopen
) -> dict[str, Any]:
    spec = load_spec(root, spec_path, report_id)
    base_url = os.getenv("AI_DEPLOYED_BASE_URL", DEFAULT_BASE_URL).rstrip("/")
    if not re.fullmatch(r"http://127\.0\.0\.1:\d+", base_url):
        raise WorkflowError("AI_DEPLOYED_BASE_URL must use loopback HTTP")
    headers = {"Accept": "application/json"}
    authorization = os.getenv("AI_DEPLOYED_AUTHORIZATION")
    if authorization:
        headers["Authorization"] = authorization
    request = urllib.request.Request(base_url + spec["path"], headers=headers, method="GET")
    try:
        with opener(request, timeout=20) as response:
            status = response.status
            body = response.read(1_000_001)
    except (urllib.error.URLError, TimeoutError) as exc:
        raise WorkflowError(f"deployed behavior request failed: {type(exc).__name__}") from exc
    if len(body) > 1_000_000:
        raise WorkflowError("deployed behavior response exceeded 1 MB")
    expected = spec["expect"]
    if status != int(expected.get("status", 200)):
        raise WorkflowError(f"expected HTTP {expected.get('status', 200)}, received {status}")
    text = body.decode("utf-8", errors="replace")
    for fragment in expected.get("text_contains", []):
        if str(fragment) not in text:
            raise WorkflowError("deployed response did not contain an expected fragment")
    if expected.get("json_equals"):
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as exc:
            raise WorkflowError("deployed response was not valid JSON") from exc
        for field, wanted in expected["json_equals"].items():
            if _lookup(payload, field) != wanted:
                raise WorkflowError(f"deployed response field {field!r} did not match")
    return {"reportId": report_id, "path": spec["path"], "status": status, "passed": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", type=Path, required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    print(json.dumps(execute(root, args.spec, args.report), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
