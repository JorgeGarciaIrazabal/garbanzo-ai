"""Startup SQL migration runner.

Applies backend/migrations/*.sql in filename order, recording each file in a
schema_migrations table so it runs exactly once per database. Files must stay
idempotent (ADD COLUMN IF NOT EXISTS, ...) as a safety net.

Uses a direct asyncpg connection: the files are multi-statement and contain
DO $$ blocks, which the prepared-statement protocol (SQLAlchemy's asyncpg
dialect) rejects; asyncpg's simple-query protocol handles them natively.
"""

import logging
from pathlib import Path

import asyncpg

logger = logging.getLogger(__name__)

# app/db/migrations.py -> backend/migrations (host) or /app/migrations (container)
MIGRATIONS_DIR = Path(__file__).resolve().parents[2] / "migrations"


async def run_migrations(database_url: str) -> None:
    if not MIGRATIONS_DIR.is_dir():
        logger.warning("Migrations directory %s not found; skipping", MIGRATIONS_DIR)
        return

    dsn = database_url.replace("postgresql+asyncpg://", "postgresql://", 1)
    conn = await asyncpg.connect(dsn)
    try:
        await conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations ("
            " filename TEXT PRIMARY KEY,"
            " applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())"
        )
        applied = {
            row["filename"]
            for row in await conn.fetch("SELECT filename FROM schema_migrations")
        }
        for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
            if path.name in applied:
                continue
            logger.info("Applying migration %s", path.name)
            # File + its record commit atomically: a failed file is retried
            # on next startup instead of being recorded as applied.
            async with conn.transaction():
                await conn.execute(path.read_text(encoding="utf-8"))
                await conn.execute(
                    "INSERT INTO schema_migrations (filename) VALUES ($1)",
                    path.name,
                )
    finally:
        await conn.close()
