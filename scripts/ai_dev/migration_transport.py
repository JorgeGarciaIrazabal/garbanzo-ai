"""Docker-only transport definition, independent of application dependencies."""

from pathlib import Path


def compose_command(root: Path, project: str, *args: str) -> list[str]:
    return [
        "docker",
        "compose",
        "--project-name",
        project,
        "--file",
        str(root / "scripts/ai_dev/migration-smoke.compose.yml"),
        *args,
    ]
