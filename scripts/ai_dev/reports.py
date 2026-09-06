"""Production report intake with private evidence and idempotent task mapping."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import subprocess
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from . import beads, triage
from .common import WorkflowError, local_dir, lock, read_json, run, write_json

REPORT_FIELDS = {
    "id",
    "type",
    "status",
    "title",
    "description",
    "user_id",
    "metadata",
    "conversation_id",
    "severity",
    "source",
    "created_at",
    "updated_at",
    "version",
}
PUBLIC_FIELDS = {
    "source_id",
    "type",
    "status",
    "summary",
    "severity",
    "source",
    "component",
    "release",
    "group_key",
}
TRANSITIONS = {
    ("open", "in_progress"),
    ("in_progress", "open"),
    ("in_progress", "closed"),
    ("closed", "in_progress"),
}


@dataclass(frozen=True, order=True)
class Cursor:
    updated_at: str
    report_id: str


class ReportError(RuntimeError):
    pass


def _run(command: list[str]) -> str:
    result = subprocess.run(command, text=True, capture_output=True, timeout=60, check=False)
    if result.returncode:
        raise ReportError(result.stderr.strip() or "report command failed")
    return result.stdout.strip()


def fetch_page(
    helper: Path,
    *,
    cursor: Cursor | None = None,
    limit: int = 50,
    status: str = "all",
    runner: Callable[[list[str]], str] = _run,
) -> list[dict[str, Any]]:
    command = [str(helper), "list", "--status", status, "--limit", str(limit), "--json"]
    if cursor:
        command += ["--after-updated", cursor.updated_at, "--after-id", cursor.report_id]
    try:
        value = json.loads(runner(command))
    except (json.JSONDecodeError, TypeError) as exc:
        raise ReportError("production report helper returned invalid JSON") from exc
    if not isinstance(value, list):
        raise ReportError("production report helper returned a non-list page")
    return [{key: row.get(key) for key in REPORT_FIELDS} for row in value if isinstance(row, dict)]


def next_cursor(rows: Iterable[dict[str, Any]], current: Cursor | None = None) -> Cursor | None:
    cursors = [
        Cursor(str(row["updated_at"]), str(row["id"]))
        for row in rows
        if row.get("updated_at") and row.get("id")
    ]
    return max(cursors, default=current)


def overlap_cursor(cursor: Cursor, seconds: int = 300) -> Cursor:
    """Re-read a small window so corrected/regressed timestamps are not skipped."""
    value = datetime.fromisoformat(cursor.updated_at.replace("Z", "+00:00")) - timedelta(
        seconds=seconds
    )
    return Cursor(value.isoformat(), "00000000-0000-0000-0000-000000000000")


def write_private_evidence(root: Path, rows: list[dict[str, Any]]) -> Path:
    directory = root / ".ai" / "local" / "reports"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    path = directory / "reports.json"
    existing: list[dict[str, Any]] = []
    if path.exists():
        value = json.loads(path.read_text(encoding="utf-8"))
        existing = value if isinstance(value, list) else []
    merged = {str(row.get("id")): row for row in existing + rows if row.get("id")}
    path.write_text(
        json.dumps(list(merged.values()), indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.chmod(path, 0o600)
    return path


def private_report_artifact(root: Path, row: dict[str, Any]) -> Path:
    """Materialize one raw report privately without exposing it in command output."""
    report_id = str(row.get("id", ""))
    if not report_id:
        raise WorkflowError("report evidence has no stable ID")
    name = hashlib.sha256(report_id.encode()).hexdigest()[:24] + ".json"
    path = local_dir(root) / "reports/details" / name
    write_json(path, row)
    path.chmod(0o600)
    return path


def sanitized_summary(
    row: dict[str, Any], group_key: str, component: str, release: str
) -> dict[str, Any]:
    components = {
        "chat",
        "rooms",
        "auth",
        "reports",
        "tools",
        "tts",
        "stt",
        "settings",
        "notifications",
        "memories",
        "knowledge",
        "topics",
        "micro-apps",
    }
    component = component if component in components else "unknown"
    release = release if re.fullmatch(r"v?\d+\.\d+\.\d+(?:\+\d+)?", release) else "unknown"
    report_type = row.get("type") if row.get("type") in {"bug", "feature"} else "unknown"
    return {
        "source_id": str(row.get("id", "")),
        "type": report_type,
        "status": row.get("status")
        if row.get("status") in {"open", "in_progress", "closed"}
        else "unknown",
        "summary": f"{report_type} report in {component}",
        "severity": row.get("severity")
        if row.get("severity") in {"critical", "high", "medium", "low", "error", "warning"}
        else "unknown",
        "source": row.get("source")
        if row.get("source") in {"frontend", "backend", "user", "manual"}
        else "unknown",
        "component": component,
        "release": release,
        "group_key": hashlib.sha256(group_key.encode()).hexdigest(),
    }


def external_ref(report_id: str) -> str:
    return f"garbanzo-report:{report_id}"


def ensure_beads_task(
    row: dict[str, Any], summary: dict[str, Any], *, runner: Callable[[list[str]], str] = _run
) -> str:
    ref = external_ref(str(row["id"]))
    found = runner(["bd", "list", "--all", "--limit", "0", "--json"])
    records = json.loads(found or "[]")
    matching = [record for record in records if record.get("external_ref") == ref]
    if matching:
        task_id = str(matching[0]["id"])
        body = json.dumps(summary, sort_keys=True)
        if matching[0].get("description") != body:
            runner(["bd", "update", task_id, "--description", body, "--json"])
        return task_id
    body = json.dumps(summary, sort_keys=True)
    command = [
        "bd",
        "create",
        "--json",
        "--external-ref",
        ref,
        "--title",
        f"Production report {row['id']}",
        "--description",
        body,
    ]
    try:
        created = json.loads(runner(command))
    except ReportError:
        records = json.loads(runner(["bd", "list", "--all", "--limit", "0", "--json"]) or "[]")
        matching = [record for record in records if record.get("external_ref") == ref]
        if matching:
            return str(matching[0]["id"])
        raise
    return str(created["id"])


def set_status(
    helper: Path, row: dict[str, Any], new_status: str, *, runner: Callable[[list[str]], str] = _run
) -> dict[str, Any]:
    old = str(row.get("status"))
    if (old, new_status) not in TRANSITIONS:
        raise ReportError(f"invalid status transition: {old} -> {new_status}")
    output = runner(
        [
            str(helper),
            "set-status",
            str(row["id"]),
            new_status,
            old,
            str(row["updated_at"]),
            str(row["version"]),
        ]
    )
    return json.loads(output)


def can_close(
    *,
    fix_revision: str,
    deployed_revision: str,
    is_ancestor: Callable[[str, str], bool],
    behavior_verified: bool,
) -> bool:
    return bool(
        fix_revision
        and deployed_revision
        and behavior_verified
        and is_ancestor(fix_revision, deployed_revision)
    )


def helper_path(root: Path) -> Path:
    preferred = root / ".agents/skills/user-reports/reports.sh"
    return preferred if preferred.exists() else root / ".claude/skills/user-reports/reports.sh"


def _verification_path(root: Path, report_id: str) -> Path:
    safe_name = hashlib.sha256(report_id.encode()).hexdigest()
    return local_dir(root) / "report-verifications" / f"{safe_name}.json"


def _manifest_digest(value: dict[str, Any]) -> str:
    payload = {key: item for key, item in value.items() if key != "manifest_digest"}
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def verify_report(
    root: Path,
    report_id: str,
    deployed_revision: str,
    commands: list[str],
    *,
    runner: Callable[[list[str]], str] | None = None,
) -> dict[str, Any]:
    if not commands:
        raise WorkflowError("report verification requires at least one behavior test command")
    invoke = runner or (lambda argv: run(root, argv, timeout=1800))
    deployed_revision = run(
        root, ["git", "rev-parse", "--verify", f"{deployed_revision}^{{commit}}"]
    ).strip()
    runtime_revision = invoke(["just", "ai-prod-revision"]).strip()
    if runtime_revision != deployed_revision:
        raise WorkflowError(
            f"production runs {runtime_revision or 'an unknown revision'}, not {deployed_revision}"
        )
    verification_dir = _verification_path(root, report_id).parent
    verification_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(verification_dir, 0o700)
    results = []
    for index, text in enumerate(commands):
        argv = shlex.split(text)
        if len(argv) != 6 or argv[:2] != ["just", "ai-prod-behavior"]:
            raise WorkflowError(
                "report verification requires: just ai-prod-behavior --spec PATH --report ID"
            )
        try:
            spec_value = argv[argv.index("--spec") + 1]
            command_report = argv[argv.index("--report") + 1]
        except (ValueError, IndexError) as exc:
            raise WorkflowError("deployed behavior command requires --spec and --report") from exc
        if command_report != report_id:
            raise WorkflowError("deployed behavior command report does not match")
        from .behavior import load_spec

        load_spec(root, Path(spec_value), report_id)
        raw_spec_path = Path(spec_value)
        spec_path = (
            (root / raw_spec_path).resolve()
            if not raw_spec_path.is_absolute()
            else raw_spec_path.resolve()
        )
        output = invoke(argv)
        log_path = (
            verification_dir / f"{hashlib.sha256(report_id.encode()).hexdigest()}-{index}.log"
        )
        log_path.write_text(output, encoding="utf-8")
        os.chmod(log_path, 0o600)
        results.append(
            {
                "command": argv,
                "log_file": log_path.name,
                "log_sha256": hashlib.sha256(output.encode()).hexdigest(),
                "passed": True,
                "spec_file": spec_path.relative_to(root.resolve()).as_posix(),
                "spec_sha256": hashlib.sha256(spec_path.read_bytes()).hexdigest(),
            }
        )
    manifest = {
        "schema_version": 1,
        "report_id": report_id,
        "deployed_revision": deployed_revision,
        "runtime_revision": runtime_revision,
        "behavior_verified": True,
        "checked_at": datetime.now().astimezone().isoformat(),
        "commands": results,
    }
    manifest["manifest_digest"] = _manifest_digest(manifest)
    path = _verification_path(root, report_id)
    write_json(path, manifest)
    os.chmod(path, 0o600)
    return {
        "status": "verified",
        "reportId": report_id,
        "revision": deployed_revision,
        "evidence": str(path),
    }


def verified_manifest(root: Path, report_id: str, deployed_revision: str) -> dict[str, Any]:
    path = _verification_path(root, report_id)
    evidence = read_json(path, {})
    commands = evidence.get("commands", [])
    log_dir = path.parent
    logs_valid = bool(commands)
    for item in commands:
        log_name = item.get("log_file", "")
        log_path = log_dir / log_name
        spec_path = root / str(item.get("spec_file", ""))
        logs_valid = logs_valid and bool(
            item.get("passed") is True
            and Path(log_name).name == log_name
            and log_path.is_file()
            and hashlib.sha256(log_path.read_bytes()).hexdigest() == item.get("log_sha256")
            and spec_path.resolve().is_relative_to((root / "scripts/ai_checks").resolve())
            and spec_path.is_file()
            and hashlib.sha256(spec_path.read_bytes()).hexdigest() == item.get("spec_sha256")
        )
    valid = (
        evidence.get("schema_version") == 1
        and evidence.get("report_id") == report_id
        and evidence.get("deployed_revision") == deployed_revision
        and evidence.get("runtime_revision") == deployed_revision
        and evidence.get("behavior_verified") is True
        and bool(evidence.get("checked_at"))
        and logs_valid
        and evidence.get("manifest_digest") == _manifest_digest(evidence)
    )
    return evidence if valid else {}


def _sync(root: Path, *, limit: int = 50) -> dict[str, Any]:
    cursor_path = local_dir(root) / "reports-cursor.json"
    saved = read_json(cursor_path, {})
    cursor = Cursor(saved["updated_at"], saved["report_id"]) if saved else None
    page_cursor = overlap_cursor(cursor) if cursor else None
    all_rows: list[dict[str, Any]] = []
    while True:
        rows = fetch_page(
            helper_path(root),
            cursor=page_cursor,
            limit=limit,
            runner=lambda command: run(root, command),
        )
        all_rows.extend(rows)
        if len(rows) < limit:
            break
        advanced = next_cursor(rows, page_cursor)
        if advanced == page_cursor:
            raise WorkflowError("production report cursor did not advance")
        page_cursor = advanced
    evidence_path = write_private_evidence(root, all_rows)
    final_cursor = next_cursor(all_rows, cursor)
    merged_rows = read_json(evidence_path, [])
    known = {item.get("external_ref"): item for item in beads.issues(root)}
    created = 0
    for row in merged_rows:
        ref = external_ref(str(row["id"]))
        source, _, component, release = triage.dimensions(row)
        summary = sanitized_summary(row, triage.group_key(row), component, release)
        body = json.dumps(summary, sort_keys=True)
        if ref in known:
            if known[ref].get("description") != body:
                known[ref] = beads.call(root, "update", known[ref]["id"], "--description", body)
            continue
        item = beads.call(
            root,
            "create",
            "--title",
            f"Production report {row['id']}",
            "--external-ref",
            ref,
            "--description",
            body,
            "--labels",
            f"report,{source}",
        )
        known[ref] = item
        created += 1
    if final_cursor:
        write_json(
            cursor_path,
            {"updated_at": final_cursor.updated_at, "report_id": final_cursor.report_id},
        )
    return {
        "status": "synchronized",
        "observations": len(all_rows),
        "tasksCreated": created,
        "cursor": final_cursor.__dict__ if final_cursor else None,
    }


def sync(root: Path, *, limit: int = 50) -> dict[str, Any]:
    with lock(root, "reports"):
        return _sync(root, limit=limit)


def handle(args) -> dict[str, Any]:
    if args.action == "sync":
        return sync(args.root, limit=args.limit)
    if args.action == "snapshot":
        return triage.production_snapshot(str(args.root))
    if args.action == "verify":
        return verify_report(args.root, args.id, args.deployed_revision, args.command)
    evidence = read_json(local_dir(args.root) / "reports/reports.json", [])
    if args.action == "list":
        selected = (
            evidence
            if args.status == "all"
            else [row for row in evidence if row.get("status") == args.status]
        )
        return {
            "reports": [
                sanitized_summary(
                    row, triage.group_key(row), triage.dimensions(row)[2], triage.dimensions(row)[3]
                )
                for row in selected
            ]
        }
    matching = [row for row in evidence if str(row.get("id")) == args.id]
    if not matching:
        raise WorkflowError(f"report {args.id} is not in local evidence; run just ai-reports sync")
    row = matching[0]
    if args.action == "show":
        return {
            "report": sanitized_summary(
                row,
                triage.group_key(row),
                triage.dimensions(row)[2],
                triage.dimensions(row)[3],
            ),
            "private_artifact": str(private_report_artifact(args.root, row)),
        }
    if args.status == "closed":
        evidence = verified_manifest(args.root, args.id, args.deployed_revision)
        runtime_revision = run(args.root, ["just", "ai-prod-revision"]).strip()
        verified = (
            evidence.get("report_id") == args.id
            and evidence.get("deployed_revision") == args.deployed_revision
            and evidence.get("behavior_verified") is True
            and runtime_revision == args.deployed_revision
            and bool(evidence.get("checked_at"))
            and can_close(
                fix_revision=args.fix_revision,
                deployed_revision=args.deployed_revision,
                is_ancestor=lambda fix, deployed: (
                    subprocess.run(
                        ["git", "merge-base", "--is-ancestor", fix, deployed],
                        cwd=args.root,
                        check=False,
                    ).returncode
                    == 0
                ),
                behavior_verified=True,
            )
        )
        if not verified:
            raise WorkflowError(
                "closing requires the deployed revision to contain the fix and behavior verification"
            )
    return set_status(
        helper_path(args.root), row, args.status, runner=lambda command: run(args.root, command)
    )


def register(subparsers) -> None:
    parser = subparsers.add_parser("reports", help="Synchronize and inspect production reports")
    parser.set_defaults(func=handle, action="sync", limit=50)
    actions = parser.add_subparsers(dest="action")
    sync_parser = actions.add_parser("sync")
    sync_parser.add_argument("--limit", type=int, choices=range(1, 501), default=50)
    actions.add_parser("snapshot")
    list_parser = actions.add_parser("list")
    list_parser.add_argument(
        "--status", choices=("open", "in_progress", "closed", "all"), default="open"
    )
    show = actions.add_parser("show")
    show.add_argument("id")
    verify = actions.add_parser("verify")
    verify.add_argument("id")
    verify.add_argument("--deployed-revision", required=True)
    verify.add_argument("--command", action="append", required=True)
    status = actions.add_parser("status")
    status.add_argument("id")
    status.add_argument("status", choices=("open", "in_progress", "closed"))
    status.add_argument("--fix-revision", default="")
    status.add_argument("--deployed-revision", default="")
