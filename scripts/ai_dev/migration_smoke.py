"""Run every SQL migration twice against a disposable pgvector PostgreSQL."""

from __future__ import annotations

import argparse
import asyncio
import importlib
import os
import socket
import subprocess
from pathlib import Path
from typing import Any

import asyncpg
from migration_transport import compose_command
from sqlalchemy.ext.asyncio import create_async_engine


def _available_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def _compose(root: Path, project: str, env: dict[str, str], *args: str) -> str:
    result = subprocess.run(
        compose_command(root, project, *args),
        cwd=root,
        env=env,
        text=True,
        capture_output=True,
        timeout=120,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


async def run_database_smoke(
    database_url: str, migrations_dir: Path, expected: list[str]
) -> dict[str, Any]:
    from app.db import migrations
    from app.db.base import Base

    importlib.import_module("app.models")

    engine = create_async_engine(database_url)
    try:
        async with engine.begin() as connection:
            await connection.exec_driver_sql("CREATE EXTENSION IF NOT EXISTS vector")
            await connection.run_sync(Base.metadata.create_all)
        original = migrations.MIGRATIONS_DIR
        migrations.MIGRATIONS_DIR = migrations_dir
        try:
            await migrations.run_migrations(database_url)
            dsn = database_url.replace("postgresql+asyncpg://", "postgresql://", 1)
            connection = await asyncpg.connect(dsn)
            try:
                first = await connection.fetch(
                    "SELECT filename, applied_at FROM schema_migrations ORDER BY filename"
                )
                vector = await connection.fetchval(
                    "SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector')"
                )
            finally:
                await connection.close()
            await migrations.run_migrations(database_url)
            connection = await asyncpg.connect(dsn)
            try:
                second = await connection.fetch(
                    "SELECT filename, applied_at FROM schema_migrations ORDER BY filename"
                )
            finally:
                await connection.close()
        finally:
            migrations.MIGRATIONS_DIR = original
    finally:
        await engine.dispose()

    applied = [row["filename"] for row in first]
    if applied != expected:
        raise RuntimeError(
            f"migration ledger mismatch: expected {len(expected)}, applied {len(applied)}"
        )
    if list(first) != list(second):
        raise RuntimeError("second migration pass changed the migration ledger")
    if not vector:
        raise RuntimeError("pgvector extension was not installed")
    return {"migrations": len(applied), "idempotent": True, "pgvector": True}


def run(root: Path) -> dict[str, Any]:
    port = _available_port()
    project = f"garbanzo-migration-smoke-{os.getpid()}"
    env = os.environ.copy()
    env["AI_MIGRATION_SMOKE_PORT"] = str(port)
    database_url = (
        f"postgresql+asyncpg://garbanzo:smoke-only@127.0.0.1:{port}/garbanzo_migration_smoke"
    )
    try:
        _compose(root, project, env, "up", "--detach", "--wait", "postgres")
        migrations_dir = root / "backend/migrations"
        expected = sorted(path.name for path in migrations_dir.glob("*.sql"))
        return asyncio.run(run_database_smoke(database_url, migrations_dir, expected))
    finally:
        _compose(root, project, env, "down", "--volumes", "--remove-orphans")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    result = run(args.root.resolve())
    print(
        f"migration smoke passed: {result['migrations']} migrations, "
        f"idempotent={result['idempotent']}, pgvector={result['pgvector']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
