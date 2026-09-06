"""Deterministic grouping and release-aware recurrence rules for triage."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any

from . import beads
from .common import local_dir, read_json


def normalize_signature(row: dict[str, Any]) -> str:
    metadata = row.get("metadata") if isinstance(row.get("metadata"), dict) else {}
    raw = (
        metadata.get("error_signature")
        or metadata.get("exception_type")
        or row.get("description")
        or ""
    )
    text = str(raw).lower()
    text = re.sub(r"\b[0-9a-f]{8}-[0-9a-f-]{27,}\b", "<id>", text)
    text = re.sub(r"\b\d+\b", "<n>", text)
    text = re.sub(r"\s+", " ", text).strip()
    return hashlib.sha256(text.encode()).hexdigest()[:20]


def dimensions(row: dict[str, Any]) -> tuple[str, str, str, str]:
    metadata = row.get("metadata") if isinstance(row.get("metadata"), dict) else {}
    source = str(row.get("source") or metadata.get("source") or "unknown")
    component = str(metadata.get("component") or metadata.get("route") or "unknown")
    release = str(metadata.get("release") or metadata.get("app_version") or "unknown")
    return source, normalize_signature(row), component, release


def group_key(row: dict[str, Any]) -> str:
    return "|".join(dimensions(row))


def group_reports(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        groups.setdefault(group_key(row), []).append(row)
    return groups


def recurrence_action(
    report_release: str,
    fixed_release: str,
    reproduced_on_fixed: bool,
    *,
    report_predates_fix: bool | None = None,
) -> str:
    if report_release != fixed_release and report_predates_fix is True:
        return "retain_old_release_observation"
    if report_release != fixed_release:
        return "requires_release_comparison"
    if reproduced_on_fixed:
        return "reopen_task_and_report"
    return "await_reproduction"


def production_snapshot(root: str, *, runner=subprocess.run) -> dict[str, Any]:
    """Collect bounded production health evidence; failures are data, never empty success."""
    commands = {
        "services": [
            "just",
            "--justfile",
            f"{root}/justfile",
            "--working-directory",
            root,
            "ai-prod-services",
        ],
        "backend_logs": [
            "just",
            "--justfile",
            f"{root}/justfile",
            "--working-directory",
            root,
            "ai-prod-logs",
        ],
    }
    result: dict[str, Any] = {}
    for name, command in commands.items():
        completed = runner(command, text=True, capture_output=True, timeout=20, check=False)
        output = completed.stdout[-20_000:]
        if name == "backend_logs" and output:
            evidence = local_dir(Path(root)) / "incident-backend.log"
            evidence.write_text(output)
            evidence.chmod(0o600)
            output = f"private bounded evidence: {evidence} ({len(output.splitlines())} lines)"
        elif name == "services" and output:
            services = []
            for line in output.splitlines():
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                services.append(
                    {key: row.get(key) for key in ("Service", "State", "Health", "Status")}
                )
            output = services
        error = completed.stderr[-2_000:] if completed.returncode else ""
        if error:
            evidence = local_dir(Path(root)) / f"incident-{name}-error.log"
            evidence.write_text(error)
            evidence.chmod(0o600)
        result[name] = {
            "ok": completed.returncode == 0 and (name != "services" or bool(output)),
            "output": output,
            "error": f"private error evidence: {evidence}" if error else "",
        }
    result["collection_ok"] = all(item["ok"] for item in result.values())
    return result


def ingest_findings(root: Path, source: str, findings: list[dict[str, Any]]) -> dict[str, int]:
    """Map CI/audit findings into Beads using stable IDs and sanitized fields."""
    rows = beads.issues(root)
    created = 0
    closed = 0
    reopened = 0
    safe_source = source if re.fullmatch(r"[a-z0-9_-]{1,32}", source) else "external"
    prefix = f"finding:{safe_source}:"
    known = {row.get("external_ref"): row for row in rows if row.get("external_ref")}
    current_refs = set()
    for finding in findings:
        source_id = hashlib.sha256(str(finding["id"]).encode()).hexdigest()[:24]
        ref = f"finding:{safe_source}:{source_id}"
        current_refs.add(ref)
        existing = known.get(ref)
        if existing:
            if existing.get("status") == "closed":
                beads.call(root, "reopen", existing["id"], "--reason", "Finding observed again")
                reopened += 1
            continue
        raw_severity = str(finding.get("severity", "unknown"))
        severity = (
            raw_severity
            if raw_severity in {"critical", "high", "medium", "low", "unknown"}
            else "unknown"
        )
        raw_component = str(finding.get("component", "unknown"))
        component = (
            raw_component if re.fullmatch(r"[A-Za-z0-9_.:/-]{1,80}", raw_component) else "redacted"
        )
        priority = {"critical": "0", "high": "1", "medium": "2"}.get(severity, "3")
        beads.call(
            root,
            "create",
            "--title",
            f"{safe_source} finding {source_id}",
            "--external-ref",
            ref,
            "--description",
            f"severity={severity}; component={component}",
            "--acceptance",
            f"A subsequent {safe_source} scan no longer observes this stable finding.",
            "--priority",
            priority,
            "--labels",
            f"finding,{safe_source}",
        )
        known[ref] = {"external_ref": ref, "status": "open"}
        created += 1
    for ref, existing in known.items():
        if (
            ref.startswith(prefix)
            and ref not in current_refs
            and existing.get("status") != "closed"
        ):
            beads.call(
                root,
                "close",
                existing["id"],
                "--reason",
                f"Finding absent from the latest successful {safe_source} scan",
            )
            closed += 1
    return {
        "observations": len(findings),
        "tasksCreated": created,
        "tasksClosed": closed,
        "tasksReopened": reopened,
    }


def handle(args) -> dict[str, Any]:
    from . import reports

    if args.command == "incident":
        return production_snapshot(str(args.root))
    result = reports.sync(args.root, limit=args.limit)
    evidence = read_json(local_dir(args.root) / "reports/reports.json", [])
    groups = group_reports(evidence)
    result["groups"] = len(groups)
    result["duplicateObservations"] = sum(max(0, len(rows) - 1) for rows in groups.values())
    return result


def register(subparsers) -> None:
    parser = subparsers.add_parser("triage", help="Synchronize and classify intake findings")
    parser.add_argument("--limit", type=int, choices=range(1, 501), default=50)
    parser.set_defaults(func=handle)
    incident = subparsers.add_parser("incident", help="Collect bounded production health and logs")
    incident.set_defaults(func=handle)
