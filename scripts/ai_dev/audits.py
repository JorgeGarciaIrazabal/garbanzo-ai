"""Local dependency and secret audits with sanitized Beads intake."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from .common import WorkflowError, environment, local_dir, run, write_json
from .triage import ingest_findings


def _stable(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()[:24]


def secret_findings(payload: object, scan_root: Path) -> list[dict[str, str]]:
    if not isinstance(payload, list):
        raise WorkflowError("gitleaks returned an unexpected JSON schema")
    findings = []
    for item in payload:
        if not isinstance(item, dict):
            raise WorkflowError("gitleaks returned an incomplete finding")
        try:
            component = (
                Path(str(item.get("File", "")))
                .resolve()
                .relative_to(scan_root.resolve())
                .as_posix()
            )
        except ValueError:
            component = "unknown"
        findings.append(
            {
                "id": _stable(f"{item.get('RuleID')}:{component}:{item.get('StartLine')}"),
                "severity": "high",
                "component": component,
            }
        )
    return findings


def dependency_findings(payload: object) -> list[dict[str, str]]:
    if not isinstance(payload, dict) or not isinstance(payload.get("dependencies"), list):
        raise WorkflowError("pip-audit returned an unexpected JSON schema")
    findings = []
    for dependency in payload["dependencies"]:
        if (
            not isinstance(dependency, dict)
            or not isinstance(dependency.get("name"), str)
            or (
                not isinstance(dependency.get("vulns"), list)
                and not isinstance(dependency.get("skip_reason"), str)
            )
        ):
            raise WorkflowError("pip-audit returned an incomplete dependency record")
        package = str(dependency.get("name", "unknown"))
        if isinstance(dependency.get("skip_reason"), str):
            findings.append(
                {
                    "id": _stable(f"{package}:audit-skipped"),
                    "severity": "unknown",
                    "component": package,
                }
            )
            continue
        seen = set()
        for vulnerability in dependency["vulns"]:
            if not isinstance(vulnerability, dict) or not vulnerability.get("id"):
                raise WorkflowError("pip-audit returned an incomplete vulnerability record")
            vulnerability_id = str(vulnerability.get("id", "unknown"))
            identity = f"{package}:{vulnerability_id}"
            if identity in seen:
                continue
            seen.add(identity)
            findings.append(
                {
                    "id": _stable(identity),
                    "severity": "unknown",
                    "component": package,
                }
            )
    return findings


def dart_findings(payload: object) -> list[dict[str, str]]:
    if not isinstance(payload, dict) or not isinstance(payload.get("packages"), list):
        raise WorkflowError("dart pub outdated returned an unexpected JSON schema")
    findings = []
    for package in payload["packages"]:
        if (
            not isinstance(package, dict)
            or not isinstance(package.get("package"), str)
            or package.get("kind") not in {"direct", "dev", "transitive"}
        ):
            raise WorkflowError("dart pub outdated returned an incomplete package record")
        name = package["package"]
        reasons = []
        if package.get("isCurrentAffectedByAdvisory") is True:
            reasons.append(("advisory", "high"))
        if package.get("isCurrentRetracted") is True:
            reasons.append(("retracted", "high"))
        if package.get("isDiscontinued") is True:
            reasons.append(("discontinued", "medium"))
        current = package.get("current")
        resolvable = package.get("resolvable")
        if (
            package["kind"] in {"direct", "dev"}
            and isinstance(current, dict)
            and isinstance(resolvable, dict)
            and current.get("version")
            and resolvable.get("version")
            and current["version"] != resolvable["version"]
        ):
            reasons.append(("outdated", "low"))
        for reason, severity in reasons:
            findings.append(
                {
                    "id": _stable(f"{name}:{reason}"),
                    "severity": severity,
                    "component": name,
                }
            )
    return findings


def handle(args) -> dict:
    root = args.root
    evidence_dir = local_dir(root) / "audits"
    evidence_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    secret_path = evidence_dir / "gitleaks.json"
    listed = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=root,
        capture_output=True,
        check=True,
    ).stdout.split(b"\0")
    with tempfile.TemporaryDirectory(prefix="garbanzo-secret-scan-") as temporary:
        scan_root = Path(temporary)
        for encoded in listed:
            if not encoded:
                continue
            relative = Path(encoded.decode())
            source = root / relative
            if source.is_file() and not source.is_symlink():
                destination = scan_root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
        secret = subprocess.run(
            [
                "gitleaks",
                "dir",
                "--no-banner",
                "--redact",
                "--report-format",
                "json",
                "--report-path",
                str(secret_path),
                str(scan_root),
            ],
            cwd=root,
            env=environment(root),
            text=True,
            capture_output=True,
            timeout=300,
            check=False,
        )
        if secret.returncode not in {0, 1}:
            raise WorkflowError("gitleaks collection failed; inspect private audit evidence")
        secrets = json.loads(secret_path.read_text()) if secret_path.exists() else []
        secret_observations = secret_findings(secrets, scan_root)

    dependency_output = run(root, ["just", "ai-pip-audit"], timeout=600)
    dependency_path = evidence_dir / "python.json"
    dependency_path.write_text(dependency_output)
    dependency_path.chmod(0o600)
    payload = json.loads(dependency_output)
    dependency_observations = dependency_findings(payload)

    dart_output = run(root, ["just", "ai-dart-audit"], timeout=300)
    dart_path = evidence_dir / "dart-outdated.json"
    dart_path.write_text(dart_output)
    dart_path.chmod(0o600)
    dart_payload = json.loads(dart_output)
    dart_observations = dart_findings(dart_payload)
    write_json(
        evidence_dir / "summary.json",
        {
            "secretFindings": len(secret_observations),
            "pythonFindings": len(dependency_observations),
            "dartFindings": len(dart_observations),
        },
    )
    secrets_result = ingest_findings(root, "gitleaks", secret_observations)
    dependencies_result = ingest_findings(root, "pip-audit", dependency_observations)
    dart_result = ingest_findings(root, "dart-pub", dart_observations)
    return {
        "gitleaks": secrets_result,
        "python": dependencies_result,
        "dart": dart_result,
    }


def register(subparsers):
    subparsers.add_parser("audit", help="Run dependency and secret audits").set_defaults(
        func=handle
    )
