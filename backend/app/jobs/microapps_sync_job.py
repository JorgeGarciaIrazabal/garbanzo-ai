"""Periodic micro-apps repo sync for deployments.

First run clones MICROAPPS_GIT_URL into MICROAPPS_REPO_PATH; subsequent runs
fetch the remote, fast-forward the main checkout, and rebase clean user
worktrees so published changes land in running workspaces (Vite HMR picks the
file changes up live). Registered only when MICROAPPS_GIT_URL is set — dev
points MICROAPPS_REPO_PATH at a repo the developer manages themselves.
"""

import asyncio
import logging

from app.services.microapp_workspace import manager

logger = logging.getLogger(__name__)


async def run_microapps_sync_job() -> None:
    if not manager.enabled:
        return
    try:
        await asyncio.to_thread(manager.sync_repo_sync)
        logger.info("Micro-apps repo sync completed")
    except Exception:
        logger.exception("Micro-apps repo sync failed")
