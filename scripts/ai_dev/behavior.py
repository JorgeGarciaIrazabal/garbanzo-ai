"""Read-only, report-specific behavior checks against the deployed backend."""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from typing import Any

from .common import WorkflowError

DEFAULT_BASE_URL = "http://127.0.0.1:8001"
FORBIDDEN_PATHS = frozenset({"/health", "/api/v1/health"})
XML_NAMESPACES = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}


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
    if set(expected) - {"status", "text_contains", "json_equals", "headers", "zip_xml"}:
        raise WorkflowError("unknown behavior response assertion")
    json_equals = expected.get("json_equals", {})
    if not isinstance(json_equals, dict):
        raise WorkflowError("json_equals must be an object")
    texts = expected.get("text_contains", [])
    if not isinstance(texts, list) or any(not isinstance(s, str) or not s for s in texts):
        raise WorkflowError("text_contains requires nonempty strings")
    documents = expected.get("zip_xml", {})
    if not isinstance(documents, dict):
        raise WorkflowError("zip_xml must be an object")
    for name, assertions in documents.items():
        if not name.endswith(".xml") or not isinstance(assertions, dict):
            raise WorkflowError("zip_xml entries require XML assertions")
        if set(assertions) - {"paths", "text_contains"}:
            raise WorkflowError("unknown ZIP XML assertion")
        paths, fragments = assertions.get("paths", []), assertions.get("text_contains", [])
        if not isinstance(paths, list) or not isinstance(fragments, list) or not paths + fragments:
            raise WorkflowError("ZIP XML requires nonempty assertions")
        if any(not isinstance(s, str) or not s for s in paths + fragments):
            raise WorkflowError("ZIP XML assertions require nonempty strings")
    if not texts and not documents and set(json_equals) <= {"version", "status"}:
        raise WorkflowError("status/header/version-only checks do not verify reported behavior")
    headers = expected.get("headers", {})
    if not isinstance(headers, dict) or any(
        not isinstance(v, str) or not v for v in headers.values()
    ):
        raise WorkflowError("header assertions require nonempty string values")
    parameters = value.get("path_parameters", {})
    if not isinstance(parameters, dict):
        raise WorkflowError("path_parameters must be an object")
    for name, variable in parameters.items():
        if (
            not re.fullmatch(r"[a-z_]+", name)
            or not isinstance(variable, str)
            or not re.fullmatch(r"AI_DEPLOYED_[A-Z_]+_ID", variable)
        ):
            raise WorkflowError("path parameters must reference explicit deployed ID variables")
        if "{" + name + "}" not in request_path:
            raise WorkflowError("unused behavior path parameter")
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
    request_path = spec["path"]
    for name, variable in spec.get("path_parameters", {}).items():
        identifier = os.getenv(variable, "")
        if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", identifier):
            raise WorkflowError(f"{variable} must contain a UUID")
        request_path = request_path.replace("{" + name + "}", identifier)
    if "{" in request_path or "}" in request_path:
        raise WorkflowError("unresolved behavior path parameter")
    request = urllib.request.Request(base_url + request_path, headers=headers, method="GET")
    try:
        with opener(request, timeout=20) as response:
            status = response.status
            body = response.read(1_000_001)
            response_headers = getattr(response, "headers", {})
    except (urllib.error.URLError, TimeoutError) as exc:
        raise WorkflowError(f"deployed behavior request failed: {type(exc).__name__}") from exc
    if len(body) > 1_000_000:
        raise WorkflowError("deployed behavior response exceeded 1 MB")
    expected = spec["expect"]
    if status != int(expected.get("status", 200)):
        raise WorkflowError(f"expected HTTP {expected.get('status', 200)}, received {status}")
    for name, wanted in expected.get("headers", {}).items():
        if wanted not in response_headers.get(name, ""):
            raise WorkflowError("deployed response header did not contain an expected fragment")
    if expected.get("zip_xml"):
        try:
            with zipfile.ZipFile(io.BytesIO(body)) as archive:
                if (
                    len(archive.infolist()) > 200
                    or sum(i.file_size for i in archive.infolist()) > 10_000_000
                ):
                    raise WorkflowError("deployed ZIP exceeded verification bounds")
                for name, assertions in expected["zip_xml"].items():
                    document = ET.fromstring(archive.read(name))
                    for path in assertions.get("paths", []):
                        if document.find(path, XML_NAMESPACES) is None:
                            raise WorkflowError("deployed ZIP XML is missing an expected element")
                    document_text = "".join(document.itertext())
                    for fragment in assertions.get("text_contains", []):
                        if fragment not in document_text:
                            raise WorkflowError("deployed ZIP XML is missing expected text")
        except WorkflowError:
            raise
        except (zipfile.BadZipFile, KeyError, ET.ParseError, SyntaxError, RuntimeError) as exc:
            raise WorkflowError("deployed response failed ZIP XML validation") from exc
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
