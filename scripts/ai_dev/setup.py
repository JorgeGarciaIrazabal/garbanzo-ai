"""Reproducible setup and visible capability checks; no hidden fallbacks."""

import json
import os
import shutil
import subprocess
import tempfile
import tomllib
from pathlib import Path
from types import SimpleNamespace

from . import beads, capacity, models, reports
from .common import WorkflowError, environment, local_dir, read_json, run, write_json
from .knowledge import DOCUMENTS


def setup(args):
    root = args.root
    local_dir(root)
    if args.install:
        tools = root / ".ai/tools"
        tools.mkdir(exist_ok=True)
        for name in ("package.json", "package-lock.json"):
            shutil.copyfile(root / ".ai" / name, tools / name)
        run(root, ["npm", "ci", "--prefix", str(tools)], timeout=600)
        # Native SQLite must match the pinned Node, not a possibly older host Node.
        run(root, ["npm", "rebuild", "--prefix", str(tools), "better-sqlite3"], timeout=300)
        pin = read_json(root / ".ai/toolchain.json")["ollama-usage"]["revision"]
        run(root, ["just", "ai-install-usage", pin], timeout=180)
        gitleaks = read_json(root / ".ai/toolchain.json")["gitleaks"]
        run(
            root,
            [
                "just",
                "ai-install-gitleaks",
                gitleaks["version"],
                gitleaks["linux_x64_sha256"],
            ],
            timeout=180,
        )
    if not (root / ".beads/embeddeddolt").exists():
        # bd init auto-commits even with --skip-hooks. Run in a non-git directory
        # with BEADS_DIR, then relocate, avoiding commits or documentation mutations.
        env = environment(root)
        env["BEADS_DIR"] = str(root / ".beads")
        env["BD_NON_INTERACTIVE"] = "1"
        with tempfile.TemporaryDirectory(prefix="garbanzo-beads-init-") as temporary:
            result = subprocess.run(
                [
                    "bd",
                    "init",
                    "--prefix",
                    "garbanzo",
                    "--skip-agents",
                    "--skip-hooks",
                    "--non-interactive",
                ],
                cwd=temporary,
                env=env,
                capture_output=True,
                text=True,
                timeout=120,
            )
        if result.returncode:
            raise WorkflowError("Beads initialization failed; inspect just ai-doctor")
    run(root, ["bd", "config", "set", "sync.auto-push", "false"])
    run(root, ["bd", "config", "set", "export.auto", "false"])
    if args.migrate:
        beads.migrate(root)
    models.handle(SimpleNamespace(root=root, action="refresh"))
    if args.nightly:
        install_nightly(root)
    return doctor(args)


def install_nightly(root: Path):
    destination = Path.home() / ".config/systemd/user"
    destination.mkdir(parents=True, exist_ok=True)
    for name in ("garbanzo-ai-nightly.service", "garbanzo-ai-nightly.timer"):
        source = root / "scripts/ai_dev/systemd" / name
        text = source.read_text().replace("%h/code/garbanzo-ai", str(root).replace("%", "%%"))
        (destination / name).write_text(text)
    run(root, ["systemctl", "--user", "daemon-reload"])
    run(root, ["systemctl", "--user", "enable", "--now", "garbanzo-ai-nightly.timer"])


def doctor(args):
    root = args.root
    checks = []
    env = environment(root)
    for name, argv, required in [
        ("just", ["just", "--version"], True),
        ("codex", ["codex", "--version"], True),
        ("bd", ["bd", "version"], True),
        ("qmd", ["qmd", "--version"], True),
        ("ast-grep", ["ast-grep", "--version"], True),
        ("node", ["node", "--version"], True),
        ("dart", ["dart", "--version"], True),
        ("ollama", ["ollama", "--version"], False),
        ("ollama-usage", ["ollama-usage", "--version"], False),
        ("gitleaks", ["gitleaks", "version"], False),
    ]:
        present = shutil.which(argv[0], path=env["PATH"])
        try:
            version = run(root, argv, timeout=10).strip() if present else "missing"
            ok = bool(present)
        except WorkflowError:
            version, ok = "unavailable", False
        checks.append({"name": name, "ok": ok, "required": required, "version": version})
    for path in DOCUMENTS + [
        ".codex/config.toml",
        ".serena/project.yml",
        "pyrightconfig.json",
        ".beads/metadata.json",
    ]:
        checks.append({"name": path, "ok": (root / path).is_file(), "required": True})
    for path in (root / ".agents/skills").glob("*/SKILL.md"):
        checks.append(
            {
                "name": str(path.relative_to(root)),
                "ok": path.read_text().startswith("---\nname:"),
                "required": True,
            }
        )
    configuration = tomllib.loads((root / ".codex/config.toml").read_text())
    checks.append(
        {
            "name": "codex-model-policy",
            "ok": configuration.get("model") == "gpt-6-astra",
            "required": True,
        }
    )
    checks.append(
        {
            "name": "canonical-agent-doc",
            "ok": not (root / "AGENTS.md").is_symlink() and (root / "CLAUDE.md").is_symlink(),
            "required": True,
        }
    )
    checks.append(
        {
            "name": "canonical-skills",
            "ok": not (root / ".agents/skills").is_symlink(),
            "required": True,
        }
    )
    checks.append(
        {
            "name": "python-environment",
            "ok": (root / "backend/.venv/bin/python").exists(),
            "required": True,
        }
    )
    checks.append(
        {
            "name": "dart-generated-models",
            "ok": (root / "lib/features/chat/models/conversation.freezed.dart").exists(),
            "required": True,
        }
    )
    manifest = read_json(local_dir(root) / "knowledge-manifest.json", {})
    checks.append(
        {"name": "knowledge-index", "ok": bool(manifest.get("sources")), "required": True}
    )
    checks.append(
        {
            "name": "production-report-adapter",
            "ok": (root / ".agents/skills/user-reports/reports.sh").is_file(),
            "required": True,
        }
    )
    try:
        task_graph_ok = bool(beads.issues(root))
    except (RuntimeError, ValueError, OSError):
        task_graph_ok = False
    checks.append({"name": "beads-task-graph", "ok": task_graph_ok, "required": True})
    return {"ok": all(item["ok"] for item in checks if item["required"]), "checks": checks}


def guided(args):
    # Session startup takes one bounded production sample; failures stay visible.
    findings = {}
    try:
        findings["reports"] = reports.sync(args.root)
    except (RuntimeError, ValueError, OSError) as exc:
        findings["collection_failure"] = str(exc)
    try:
        findings["capacity"] = capacity.handle(SimpleNamespace(unattended=False))
    except (RuntimeError, ValueError, OSError) as exc:
        findings["capacity_failure"] = str(exc)
    write_json(local_dir(args.root) / "startup.json", findings)
    if args.inspect:
        return findings
    print(json.dumps(findings, indent=2, default=str), flush=True)
    argv = [
        "codex",
        "-C",
        str(args.root),
        "-m",
        "gpt-6-astra",
        "-c",
        'model_reasoning_effort="medium"',
    ]
    if args.prompt:
        argv.append(" ".join(args.prompt))
    returncode = subprocess.call(argv, cwd=args.root, env=environment(args.root))
    if returncode:
        raise WorkflowError(
            f"Codex exited with {returncode}; persisted startup evidence is available"
        )
    return {"status": "session_ended"}


def serena(args):
    pin = json.loads((args.root / ".ai/toolchain.json").read_text())["serena"]
    os.execvpe("just", ["just", "ai-serena-runtime", pin], environment(args.root))


def register(subparsers):
    parser = subparsers.add_parser("setup")
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--migrate", action="store_true")
    parser.add_argument(
        "--nightly", action="store_true", help="Install and enable the bounded user timer"
    )
    parser.set_defaults(func=setup)
    subparsers.add_parser("doctor").set_defaults(func=doctor)
    parser = subparsers.add_parser("guided")
    parser.add_argument(
        "--inspect",
        action="store_true",
        help="Collect startup context without launching a second Codex UI",
    )
    parser.add_argument("prompt", nargs="*")
    parser.set_defaults(func=guided)
    subparsers.add_parser("serena").set_defaults(func=serena)
