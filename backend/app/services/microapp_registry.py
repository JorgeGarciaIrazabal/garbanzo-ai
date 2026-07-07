"""Read the micro-apps registry and house files directly from a worktree.

Everything here is local filesystem access against the per-user git worktree —
no network fetch is needed because the worktree already contains registry.json
and the git-tracked houses/*.house.json files.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

from app.schemas.microapp import HouseFile, MicroAppInfo

logger = logging.getLogger(__name__)

HOUSES_DIRNAME = "houses"
HOUSE_EXT = ".house.json"


def read_registry(worktree: Path) -> list[MicroAppInfo]:
    """Parse ``registry.json`` at the worktree root into MicroAppInfo entries.

    Returns an empty list if the file is missing or malformed (logged), so a
    partially-broken repo never takes the workspace down.
    """
    registry_path = worktree / "registry.json"
    if not registry_path.is_file():
        logger.warning("registry.json not found in worktree %s", worktree)
        return []
    try:
        data = json.loads(registry_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("Failed to read registry.json: %s", exc)
        return []

    apps = data.get("apps", []) if isinstance(data, dict) else []
    result: list[MicroAppInfo] = []
    for entry in apps:
        if not isinstance(entry, dict):
            continue
        try:
            result.append(MicroAppInfo(**entry))
        except Exception as exc:  # noqa: BLE001 — skip a single bad entry, keep the rest
            logger.warning("Skipping malformed registry entry %r: %s", entry, exc)
    return result


def list_houses(worktree: Path) -> list[HouseFile]:
    """List ``houses/*.house.json`` files in the worktree, newest first."""
    houses_dir = worktree / HOUSES_DIRNAME
    if not houses_dir.is_dir():
        return []
    files: list[HouseFile] = []
    for path in sorted(houses_dir.glob(f"*{HOUSE_EXT}")):
        try:
            stat = path.stat()
        except OSError:
            continue
        files.append(
            HouseFile(
                path=f"{HOUSES_DIRNAME}/{path.name}",
                name=path.name,
                modified_at=stat.st_mtime,
                size=stat.st_size,
            )
        )
    files.sort(key=lambda h: h.modified_at, reverse=True)
    return files
