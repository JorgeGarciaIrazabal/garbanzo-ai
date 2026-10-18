"""Run every SQL migration twice against a disposable pgvector PostgreSQL."""

from __future__ import annotations

import argparse
import asyncio
import importlib
import json
import os
import socket
import subprocess
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import asyncpg
from migration_transport import compose_command
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine


async def _visual_submission_concurrency_smoke(engine: Any) -> dict[str, bool]:
    """Different request IDs must not claim one presentation action twice."""
    from app.models.conversation import Conversation
    from app.models.message import Message
    from app.models.ui_submission import UISubmissionRecord
    from app.schemas.visual_ui import Presentation, UISubmission
    from app.services.visual_ui import UIActionService

    sessions = async_sessionmaker(engine, expire_on_commit=False)
    message_id = "visual-ui-concurrency-smoke"
    async with sessions() as session:
        session.add(
            Message(
                id=message_id,
                conversation_id="00000000-0000-0000-0000-000000000004",
                role="tool_result",
                content="Presentation summary",
            )
        )
        await session.commit()

    async def claim(request_id):
        async with sessions() as session:
            session.add(
                UISubmissionRecord(
                    id=request_id,
                    message_id=message_id,
                    action_id="submit",
                    status="pending",
                    values={"choice": "a"},
                )
            )
            try:
                await session.commit()
                return True
            except IntegrityError:
                await session.rollback()
                return False

    winners = await asyncio.gather(claim("ui-request-one"), claim("ui-request-two"))
    if sum(winners) != 1:
        raise RuntimeError("Concurrent UI submissions did not have exactly one winner")
    async with sessions() as session:
        source = await session.get(Message, message_id)
        await session.delete(source)
        await session.commit()
        count = await session.scalar(select(func.count(UISubmissionRecord.id)))
        if count != 0:
            raise RuntimeError("Deleting a presentation did not cascade to UI submissions")
    # Exercise the service's claim/duplicate path with independent PostgreSQL
    # sessions, including the atomically saved follow-up user message.
    conversation_id = "00000000-0000-0000-0000-000000000004"
    presentation = Presentation.model_validate(
        {
            "summary": "Choose",
            "surface_id": "choices",
            "components": [
                {
                    "id": "root",
                    "component": "Choices",
                    "action": "choose",
                    "options": [{"label": "A", "value": "A"}],
                }
            ],
            "actions": [{"id": "choose", "kind": "follow_up", "prompt": "Explain selection"}],
        }
    )
    async with sessions() as session:
        conversation = await session.get(Conversation, conversation_id)
        session.add(
            Message(
                id="visual-followup-source",
                conversation_id=conversation_id,
                role="tool_result",
                content=presentation.summary,
                session_epoch=conversation.session_epoch,
                meta={
                    "tool_call_id": "visual-concurrent-call",
                    "tool_name": "render_ui",
                    "result": presentation.result(),
                },
            )
        )
        await session.commit()
    started = []

    class RecordingService(UIActionService):
        def start_follow_up(self, conversation_id, user_id, message_id):
            started.append(message_id)

    async def submit(request_id):
        async with sessions() as session:
            return await RecordingService(session).submit(
                conversation_id,
                "topic-smoke@example.com",
                UISubmission(
                    tool_call_id="visual-concurrent-call",
                    surface_id="choices",
                    action_id="choose",
                    submission_id=request_id,
                    values={"choice": "A"},
                ),
            )

    await asyncio.gather(submit("followup-request-one"), submit("followup-request-two"))
    async with sessions() as session:
        user_count = await session.scalar(
            select(func.count(Message.id)).where(
                Message.conversation_id == conversation_id,
                Message.role == "user",
                Message.meta["ui_submission_id"].as_string().is_not(None),
            )
        )
    if user_count != 1 or len(started) != 1:
        raise RuntimeError("Concurrent UI follow-ups created or started more than one turn")
    return {"unique_ui_submissions": True, "unique_ui_followup": True}


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


async def _virtual_folder_concurrency_smoke(engine: Any) -> dict[str, bool]:
    """Verify file revisions and folder quotas under real PostgreSQL row locks."""
    from app.services import virtual_folder_service as folder_module
    from app.services.virtual_folder_service import FolderError, VirtualFolderService
    from app.topics.models import TopicIngestionEvent

    owner = "topic-smoke@example.com"
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    async with sessions() as session:
        service = VirtualFolderService(session)
        folder = await service.create_folder(owner, "Revision smoke")
        file = await service.create_text(folder.id, owner, "notes.txt", "base")
        folder_id, file_id = folder.id, file.id

    async def metadata_edit(**changes):
        async with sessions() as session:
            await VirtualFolderService(session).update_folder(folder_id, owner, **changes)

    await asyncio.wait_for(
        asyncio.gather(
            metadata_edit(name="Renamed smoke folder"),
            metadata_edit(description="Purpose preserved during a concurrent rename"),
        ),
        timeout=20,
    )
    async with sessions() as session:
        folder = await VirtualFolderService(session).owned_folder(folder_id, owner)
        if folder.name != "Renamed smoke folder" or folder.description != (
            "Purpose preserved during a concurrent rename"
        ):
            raise RuntimeError("Concurrent partial folder metadata edits lost a field")

    arrived = 0
    ready = asyncio.Event()

    async def edit(content: str):
        nonlocal arrived
        async with sessions() as session:
            # Real chat ingestion takes FK KEY SHARE locks before tool execution.
            session.add(
                TopicIngestionEvent(
                    user_id=owner,
                    operation="create",
                    source_type="message",
                    source_id=f"folder-edit-{content}",
                    source_version="smoke",
                    payload={},
                )
            )
            await session.flush()
            arrived += 1
            if arrived == 2:
                ready.set()
            await ready.wait()
            try:
                await VirtualFolderService(session).update_text(
                    folder_id, file_id, owner, content, 1
                )
                return "saved"
            except FolderError as exc:
                return exc.status_code

    edits = await asyncio.wait_for(asyncio.gather(edit("one"), edit("two")), timeout=20)
    if sorted(str(result) for result in edits) != ["409", "saved"]:
        raise RuntimeError(f"Virtual file revision serialization failed: {edits}")

    async def replace(content: bytes):
        async with sessions() as session:
            try:
                await VirtualFolderService(session).replace_file(
                    folder_id, file_id, owner, content, 2
                )
                return "saved"
            except FolderError as exc:
                return exc.status_code

    replacements = await asyncio.wait_for(
        asyncio.gather(replace(b"first replacement"), replace(b"second replacement")), timeout=20
    )
    if sorted(str(result) for result in replacements) != ["409", "saved"]:
        raise RuntimeError(f"Virtual file replacement serialization failed: {replacements}")

    async def keep_both():
        async with sessions() as session:
            copy = await VirtualFolderService(session).create_file(
                folder_id, owner, "notes.txt", b"copy", keep_both=True
            )
            return copy.path

    copies = await asyncio.wait_for(asyncio.gather(keep_both(), keep_both()), timeout=20)
    if sorted(copies) != ["notes (2).txt", "notes (3).txt"]:
        raise RuntimeError(f"Concurrent copies did not receive unique names: {copies}")

    async with sessions() as session:
        folder = await VirtualFolderService(session).create_folder(owner, "Quota smoke")
        quota_folder_id = folder.id

    async def upload(path: str):
        async with sessions() as session:
            try:
                await VirtualFolderService(session).create_file(
                    quota_folder_id, owner, path, b"1234"
                )
                return "saved"
            except FolderError as exc:
                return exc.status_code

    old_limit = folder_module.MAX_FOLDER_BYTES
    try:
        folder_module.MAX_FOLDER_BYTES = 6
        uploads = await asyncio.gather(upload("one.txt"), upload("two.txt"))
    finally:
        folder_module.MAX_FOLDER_BYTES = old_limit
    if sorted(str(result) for result in uploads) != ["413", "saved"]:
        raise RuntimeError(f"Virtual folder quota serialization failed: {uploads}")
    return {
        "serialized_file_revisions": True,
        "serialized_folder_quotas": True,
        "serialized_folder_metadata": True,
        "serialized_file_replacements": True,
        "unique_concurrent_copies": True,
    }


async def _style_default_upgrade_smoke(connection: Any, migrations_dir: Path) -> dict[str, bool]:
    """Retirement preserves pointers even when old flags disagree with them."""
    # Reconstruct the pre-052 storage in this disposable DB after fresh startup
    # has already proved ORM-first migration replay works without the column.
    await connection.execute(
        "ALTER TABLE styles ADD COLUMN is_default BOOLEAN NOT NULL DEFAULT FALSE; "
        "CREATE UNIQUE INDEX ix_styles_one_default_per_user ON styles(user_id) WHERE is_default"
    )
    for owner in (
        "style-cleared@example.com",
        "style-owned@example.com",
        "style-builtin@example.com",
    ):
        await connection.execute(
            "INSERT INTO users(email, hashed_password) VALUES ($1, $2)", owner, "unused-smoke-hash"
        )
    await connection.execute(
        """INSERT INTO styles(id, user_id, name, model_id, is_builtin, is_default) VALUES
        ('style-cleared-legacy', 'style-cleared@example.com', 'Cleared', 'model', FALSE, TRUE),
        ('style-owned-legacy', 'style-owned@example.com', 'Superseded', 'model', FALSE, TRUE),
        ('style-owned-current', 'style-owned@example.com', 'Selected', 'model', FALSE, FALSE),
        ('style-shared-current', NULL, 'Shared', 'model', TRUE, FALSE)"""
    )
    await connection.execute(
        "UPDATE users SET default_style_id = 'style-owned-current' WHERE email = 'style-owned@example.com'; "
        "UPDATE users SET default_style_id = 'style-shared-current' WHERE email = 'style-builtin@example.com'"
    )
    before_pointers = await connection.fetch(
        "SELECT email, default_style_id FROM users WHERE email LIKE 'style-%' ORDER BY email"
    )
    before_styles = await connection.fetch(
        "SELECT id, user_id, name, model_id, created_at, updated_at FROM styles "
        "WHERE id LIKE 'style-%' ORDER BY id"
    )
    retirement = (migrations_dir / "052_retire_style_default_flag.sql").read_text(encoding="utf-8")
    for _ in range(2):
        await connection.execute(retirement)
        if (
            await connection.fetch(
                "SELECT email, default_style_id FROM users WHERE email LIKE 'style-%' ORDER BY email"
            )
            != before_pointers
        ):
            raise RuntimeError("Style retirement changed selected or cleared defaults")
        if (
            await connection.fetch(
                "SELECT id, user_id, name, model_id, created_at, updated_at FROM styles "
                "WHERE id LIKE 'style-%' ORDER BY id"
            )
            != before_styles
        ):
            raise RuntimeError("Style retirement changed style content or timestamps")
        legacy_column = await connection.fetchval(
            """SELECT EXISTS(SELECT 1 FROM information_schema.columns
            WHERE table_schema = current_schema() AND table_name = 'styles'
              AND column_name = 'is_default')"""
        )
        legacy_index = await connection.fetchval(
            "SELECT to_regclass('ix_styles_one_default_per_user')"
        )
        if legacy_column or legacy_index is not None:
            raise RuntimeError("Legacy style default storage was not retired")
    # The retained user pointer still clears when its selected style is deleted.
    await connection.execute("DELETE FROM styles WHERE id = 'style-owned-current'")
    if (
        await connection.fetchval(
            "SELECT default_style_id FROM users WHERE email = 'style-owned@example.com'"
        )
        is not None
    ):
        raise RuntimeError("Style default pointer lost ON DELETE SET NULL")
    return {"style_default_upgrade": True}


async def _style_model_refresh_smoke(connection: Any, migrations_dir: Path) -> dict[str, bool]:
    """Exercise style model upgrades and JSON snapshots against real PostgreSQL."""
    migration = (migrations_dir / "053_style_model_refresh.sql").read_text(encoding="utf-8")
    snapshot_model = "deepseek-v4.1-flash:1017-cloud"
    originals = {
        "refresh-builtin": "deepseek-v4.1-flash:cloud",
        "refresh-owned": "deepseek-v4-pro:cloud",
        "refresh-local": "deepseek-r1:8b",
        "refresh-base": "deepseek:latest",
        "refresh-current": snapshot_model,
        "refresh-other": "glm-5.3:cloud",
        "refresh-custom": "my-org/deepseek-r1:custom",
    }
    transaction = connection.transaction()
    await transaction.start()
    try:
        owner = "style-owned@example.com"
        for style_id, model in originals.items():
            await connection.execute(
                """INSERT INTO styles(id, user_id, name, model_id, thinking_level, is_builtin)
                VALUES ($1, $2, $1, $3, 'high', $4)""",
                style_id,
                None if style_id == "refresh-builtin" else owner,
                model,
                style_id == "refresh-builtin",
            )
        await connection.execute(
            "UPDATE users SET default_style_id = 'refresh-owned' WHERE email = $1", owner
        )
        await connection.execute(
            """INSERT INTO conversations
            (id, user_id, title, model, is_deleted, is_pinned, use_memory,
             use_knowledge_base, is_primary, topic_is_pinned, context_version)
            VALUES ('refresh-history', $1, 'Existing chat', 'deepseek-v4-pro:cloud',
                    FALSE, FALSE, TRUE, TRUE, FALSE, FALSE, 0)""",
            owner,
        )
        payloads = {
            "refresh-share": {
                "name": "Shared",
                "model_id": "deepseek-v4-flash:cloud",
                "thinking_level": "high",
                "prompt": {"content": "Keep my voice"},
            },
            "refresh-other-share": {"name": "Other", "model_id": "glm-5.3:cloud"},
            "refresh-prompt": {
                "model_id": "deepseek-v4-flash:cloud",
                "content": "Keep this prompt",
            },
        }
        for item_id, payload in payloads.items():
            await connection.execute(
                """INSERT INTO shared_items(id, sender_email, recipient_email, kind, payload)
                VALUES ($1, $2, 'style-builtin@example.com', $3, $4::jsonb)""",
                item_id,
                owner,
                "prompt" if item_id == "refresh-prompt" else "style",
                json.dumps(payload),
            )
        await connection.execute(
            "UPDATE available_models SET is_enabled = FALSE WHERE model_id = $1", snapshot_model
        )
        before = await connection.fetch(
            "SELECT * FROM styles WHERE id LIKE 'refresh-%' ORDER BY id"
        )
        expected = [dict(row) for row in before]
        for row in expected:
            if row["model_id"].startswith(("deepseek-", "deepseek:")):
                row["model_id"] = snapshot_model
        payloads["refresh-share"]["model_id"] = snapshot_model
        for _ in range(2):
            await connection.execute(migration)
            after = await connection.fetch(
                "SELECT * FROM styles WHERE id LIKE 'refresh-%' ORDER BY id"
            )
            if [dict(row) for row in after] != expected:
                raise RuntimeError("Style model refresh changed unrelated style fields or models")
            for item_id, payload in payloads.items():
                actual = await connection.fetchval(
                    "SELECT payload FROM shared_items WHERE id = $1", item_id
                )
                if json.loads(actual) != payload:
                    raise RuntimeError("Style model refresh damaged a shared snapshot")
            if (
                await connection.fetchval(
                    "SELECT default_style_id FROM users WHERE email = $1", owner
                )
                != "refresh-owned"
            ):
                raise RuntimeError("Style model refresh changed the default pointer")
            if (
                await connection.fetchval(
                    "SELECT model FROM conversations WHERE id = 'refresh-history'"
                )
                != "deepseek-v4-pro:cloud"
            ):
                raise RuntimeError("Style model refresh changed an existing conversation")
            if (
                await connection.fetchval(
                    "SELECT is_enabled FROM available_models WHERE model_id = $1", snapshot_model
                )
                is not False
            ):
                raise RuntimeError("Style model refresh overrode an admin model disable")
    finally:
        await transaction.rollback()
    return {"style_model_refresh": True}


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
            # Exercise migration 050's CREATE path in this disposable database.
            await connection.exec_driver_sql(
                "DROP TABLE conversation_folders, virtual_files, virtual_folders"
            )
            await connection.exec_driver_sql("DROP TABLE ui_submissions")
        original = migrations.MIGRATIONS_DIR
        migrations.MIGRATIONS_DIR = migrations_dir
        dsn = database_url.replace("postgresql+asyncpg://", "postgresql://", 1)
        try:
            # Seed a pre-metadata folder so 051 verifies an upgrade with real data.
            connection = await asyncpg.connect(dsn)
            try:
                await connection.execute(
                    (migrations_dir / "050_virtual_folders.sql").read_text(encoding="utf-8")
                )
                await connection.execute(
                    "INSERT INTO users (email, hashed_password) VALUES ($1, $2)",
                    "folder-metadata-smoke@example.com",
                    "unused-smoke-hash",
                )
                await connection.execute(
                    "INSERT INTO virtual_folders (id, user_id, name) VALUES ($1, $2, $3)",
                    "metadata-upgrade-smoke",
                    "folder-metadata-smoke@example.com",
                    "Legacy folder",
                )
            finally:
                await connection.close()
            await migrations.run_migrations(database_url)
            connection = await asyncpg.connect(dsn)
            try:
                style_upgrade = await _style_default_upgrade_smoke(connection, migrations_dir)
                style_models = await _style_model_refresh_smoke(connection, migrations_dir)
                description = await connection.fetchval(
                    "SELECT description FROM virtual_folders WHERE id = 'metadata-upgrade-smoke'"
                )
                if description != "":
                    raise RuntimeError("Legacy folder description was not initialized to empty")
                await connection.execute(
                    "UPDATE virtual_folders SET description = $1 WHERE id = $2",
                    "Existing purpose and context",
                    "metadata-upgrade-smoke",
                )
                await connection.execute(
                    (migrations_dir / "051_virtual_folder_metadata.sql").read_text(encoding="utf-8")
                )
                description = await connection.fetchval(
                    "SELECT description FROM virtual_folders WHERE id = 'metadata-upgrade-smoke'"
                )
                if description != "Existing purpose and context":
                    raise RuntimeError("Metadata migration rerun changed an existing description")
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
            ui_concurrency = await _visual_submission_concurrency_smoke(engine)
            folder_concurrency = await _virtual_folder_concurrency_smoke(engine)
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
        "folder_metadata_upgrade": True,
        **style_upgrade,
        **style_models,
        **concurrency,
        **folder_concurrency,
        **ui_concurrency,
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
        f"stream_epoch_isolated={result['stream_epoch_isolated']}, "
        f"serialized_file_revisions={result['serialized_file_revisions']}, "
        f"serialized_folder_quotas={result['serialized_folder_quotas']}, "
        f"serialized_folder_metadata={result['serialized_folder_metadata']}, "
        f"serialized_file_replacements={result['serialized_file_replacements']}, "
        f"unique_concurrent_copies={result['unique_concurrent_copies']}, "
        f"folder_metadata_upgrade={result['folder_metadata_upgrade']}, "
        f"style_default_upgrade={result['style_default_upgrade']}, "
        f"style_model_refresh={result['style_model_refresh']}, "
        f"unique_ui_submissions={result['unique_ui_submissions']}, "
        f"unique_ui_followup={result['unique_ui_followup']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
