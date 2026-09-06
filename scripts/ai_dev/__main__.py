"""Human and structured command interface (invoked by just)."""

import argparse
import importlib
import json
import os
import sys
from pathlib import Path

from .common import WorkflowError, environment, foreground_command, lock


def main():
    parser = argparse.ArgumentParser(description="Codex-first Garbanzo development")
    parser.add_argument("--json", action="store_true")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in (
        "beads",
        "knowledge",
        "setup",
        "coordination",
        "execution",
        "reports",
        "triage",
        "models",
        "capacity",
        "nightly",
        "releases",
        "audits",
    ):
        try:
            module = importlib.import_module(f"scripts.ai_dev.{name}")
        except ModuleNotFoundError as exc:
            if exc.name != f"scripts.ai_dev.{name}":
                raise
            continue
        if hasattr(module, "register"):
            module.register(subparsers)
    # Accept --json at any nesting level without duplicating every parser flag.
    raw = sys.argv[1:]
    structured = "--json" in raw
    args = parser.parse_args([value for value in raw if value != "--json"])
    args.json = structured
    args.root = Path(__file__).resolve().parents[2]
    os.environ.update(environment(args.root))
    try:
        if foreground_command(args.command) and not os.environ.get("AI_NIGHTLY_CHILD"):
            with lock(args.root, "foreground"):
                result = args.func(args)
        else:
            result = args.func(args)
    except (WorkflowError, ValueError, OSError, RuntimeError) as exc:
        if structured:
            print(json.dumps({"ok": False, "error": str(exc)}))
        else:
            print(f"error: {exc}", file=sys.stderr)
        return 1
    if result is not None:
        print(
            json.dumps(result, indent=2, default=str)
            if structured or not isinstance(result, str)
            else result
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
