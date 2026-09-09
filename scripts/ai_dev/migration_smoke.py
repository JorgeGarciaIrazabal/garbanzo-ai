"""Run every SQL migration twice against a disposable pgvector PostgreSQL."""

from __future__ import annotations

import argparse
import asyncio
import importlib
import os
import socket
import subprocess
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import asyncpg
from migration_transport import compose_command
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine


async def _topic_switch_concurrency_smoke(engine: Any) -> dict[str, bool]:
    """Exercise PostgreSQL row serialization and a detached turn's captured epoch."""
    from app.models.conversation import Conversation
    from app.models.message import Message
    from app.topics.models import Topic, TopicSwitchOperation
    from app.topics.topic_switch_service import TopicSwitchService

    conversation_id = "00000000-0000-0000-0000-000000000004"
    second_topic_id = "00000000-0000-0000-0000-000000000003"
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    async with sessions() as seed_session:
        seed_session.add_all(
            [
                Topic(
                    id=second_topic_id,
                    user_id="topic-smoke@example.com",
                    label="Travel planning",
                    normalized_label="travel planning",
                    origin="history",
                ),
                Conversation(
                    id=conversation_id,
                    user_id="topic-smoke@example.com",
                    title="Primary",
                    model="smoke-model",
                    is_primary=True,
                ),
            ]
        )
        await seed_session.commit()

    async def switch(topic_id: str, idempotency_key: str):
        async with sessions() as session:
            return await TopicSwitchService(session).switch(
                conversation_id=conversation_id,
                user=SimpleNamespace(email="topic-smoke@example.com"),
                topic_id=topic_id,
                label=None,
                idempotency_key=idempotency_key,
                archive=False,
                retain_pinned=True,
            )

    async with sessions() as turn_session:
        turn_conversation = await turn_session.get(Conversation, conversation_id)
        if turn_conversation is None:
            raise RuntimeError("concurrency smoke conversation was not created")
        captured_epoch = turn_conversation.session_epoch
        responses = await asyncio.gather(
            switch("00000000-0000-0000-0000-000000000001", "smoke-switch-one"),
            switch(second_topic_id, "smoke-switch-two"),
        )
        turn_session.add(
            Message(
                id="00000000-0000-0000-0000-000000000005",
                conversation_id=conversation_id,
                role="assistant",
                content="Detached turn completed after both topic switches.",
                session_epoch=captured_epoch,
            )
        )
        await turn_session.commit()

    async with sessions() as check_session:
        final = await check_session.get(Conversation, conversation_id)
        persisted_epoch = await check_session.scalar(
            select(Message.session_epoch).where(
                Message.id == "00000000-0000-0000-0000-000000000005"
            )
        )
        operation_count = await check_session.scalar(
            select(func.count(TopicSwitchOperation.id)).where(
                TopicSwitchOperation.conversation_id == conversation_id
            )
        )
    response_epochs = sorted(response.session_epoch for response in responses)
    serialized = bool(
        final is not None
        and final.session_epoch == 2
        and final.context_version == 2
        and response_epochs == [1, 2]
        and operation_count == 2
    )
    isolated = captured_epoch == 0 and persisted_epoch == 0
    if not serialized:
        raise RuntimeError("concurrent topic switches did not serialize into two boundaries")
    if not isolated:
        raise RuntimeError("detached turn crossed its captured topic session epoch")
    return {"serialized_switches": True, "stream_epoch_isolated": True}


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
                await connection.execute(
                    "INSERT INTO users (email, hashed_password) VALUES ($1, $2)",
                    "topic-smoke@example.com",
                    "unused-smoke-hash",
                )
                await connection.execute(
                    """INSERT INTO topics
                    (id, user_id, label, normalized_label, origin, base_score,
                     mention_count, status, metadata)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)""",
                    "00000000-0000-0000-0000-000000000001",
                    "topic-smoke@example.com",
                    "Launch planning",
                    "launch planning",
                    "history",
                    0.5,
                    1,
                    "active",
                    "{}",
                )
                embedding = "[" + ",".join(["0.036084"] * 768) + "]"
                await connection.execute(
                    """INSERT INTO topic_assertions
                    (id, topic_id, kind, content, normalized_key, embedding,
                     status, authority, confidence)
                    VALUES ($1, $2, $3, $4, $5, $6::vector, $7, $8, $9)""",
                    "00000000-0000-0000-0000-000000000002",
                    "00000000-0000-0000-0000-000000000001",
                    "preference",
                    "Use the orchid route for launch.",
                    "orchid-route",
                    embedding,
                    "active",
                    "explicit_user_statement",
                    0.9,
                )
                hybrid_row = await connection.fetchrow(
                    """SELECT id,
                    ((1.0 - (embedding <=> $1::vector)) * 0.70
                     + COALESCE(ts_rank_cd(
                         to_tsvector('english', content),
                         websearch_to_tsquery('english', $2), 32
                       ), 0.0) * 0.30) AS fused_score
                    FROM topic_assertions
                    WHERE embedding IS NOT NULL
                    ORDER BY fused_score DESC
                    LIMIT 1""",
                    embedding,
                    "orchid launch",
                )
            finally:
                await connection.close()
            concurrency = await _topic_switch_concurrency_smoke(engine)
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
    if hybrid_row is None or hybrid_row["fused_score"] <= 0:
        raise RuntimeError("PostgreSQL vector/FTS hybrid scoring did not execute")
    return {
        "migrations": len(applied),
        "idempotent": True,
        "pgvector": True,
        "hybrid_query": True,
        **concurrency,
    }


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
        f"idempotent={result['idempotent']}, pgvector={result['pgvector']}, "
        f"hybrid_query={result['hybrid_query']}, "
        f"serialized_switches={result['serialized_switches']}, "
        f"stream_epoch_isolated={result['stream_epoch_isolated']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
