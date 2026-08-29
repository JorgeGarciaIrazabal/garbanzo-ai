"""Tests for /api/v1/workflows (idea 18).

Covers the client's whole round trip — create → upload → start → poll →
changes → applied — plus ownership scoping and the guards that stop a client
reading a diff out of a run that is still going.
"""

import base64
import uuid
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.message import Message
from app.models.user import User
from app.services import workflow_runner

_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)

OWNER = "test@example.com"  # seeded by conftest
OTHER = "other@example.com"


class _UserSwitch:
    def __init__(self, email: str = OWNER):
        self.email = email

    async def __call__(self):
        return {"email": self.email, "token_payload": {}}


def _install_overrides(db_session, switch: _UserSwitch):
    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = switch


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_settings, None)
    app.dependency_overrides.pop(get_current_user, None)


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


def _b64(text: str) -> str:
    return base64.b64encode(text.encode()).decode()


def _write(path: str, text: str) -> None:
    """Module-level file IO so async tests don't trip ruff's ASYNC240."""
    Path(path).write_text(text)


def _exists(path: str) -> bool:
    return Path(path).exists()


@pytest.fixture()
def no_launch(monkeypatch):
    """Stop /start from actually spawning opencode; record the run ids."""
    launched: list[str] = []
    monkeypatch.setattr(workflow_runner, "launch", lambda run_id: launched.append(run_id))
    return launched


async def _create(client: AsyncClient, **kwargs) -> dict:
    resp = await client.post(
        "/api/v1/workflows",
        json={"instruction": "refactor the parser", **kwargs},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_create_returns_a_draft_run(db_session):
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            run = await _create(c, folder_label="my-project")
        assert run["status"] == "draft"
        assert run["instruction"] == "refactor the parser"
        assert run["scope"]["folder_label"] == "my-project"
        # The server-side snapshot path is internal and must never leak.
        assert "workdir" not in run
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_full_round_trip(db_session, no_launch, monkeypatch):
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            run = await _create(c)

            upload = await c.post(
                f"/api/v1/workflows/{run['id']}/files",
                json={"files": [{"path": "doc.md", "data": _b64("v1")}]},
            )
            assert upload.status_code == 200, upload.text
            assert upload.json() == {"file_count": 1, "total_bytes": 2}

            started = await c.post(f"/api/v1/workflows/{run['id']}/start")
            assert started.status_code == 200, started.text
            assert started.json()["status"] == "queued"
            assert no_launch == [run["id"]]

            # Simulate the run finishing with an edit in the snapshot.
            from app.models.workflow_run import WorkflowRun

            row = await db_session.get(WorkflowRun, run["id"])
            workdir = row.workdir
            _write(f"{workdir}/doc.md", "v2")
            row.status = "done"
            row.summary = "Updated the doc."
            await db_session.commit()

            changes = await c.get(f"/api/v1/workflows/{run['id']}/changes")
            assert changes.status_code == 200, changes.text
            body = changes.json()
            assert [ch["path"] for ch in body["changes"]] == ["doc.md"]
            assert base64.b64decode(body["changes"][0]["data"]) == b"v2"
            assert body["changes"][0]["base_sha256"]

            applied = await c.post(f"/api/v1/workflows/{run['id']}/applied")
            assert applied.status_code == 204
            assert not _exists(workdir)
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_research_run_starts_empty_and_downloads_summary(db_session, no_launch):
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            run = await _create(c, mode="research")
            assert run["scope"]["mode"] == "research"

            upload = await c.post(
                f"/api/v1/workflows/{run['id']}/files",
                json={"files": [{"path": "no.txt", "data": _b64("no")}]},
            )
            assert upload.status_code == 400

            started = await c.post(f"/api/v1/workflows/{run['id']}/start")
            assert started.status_code == 200
            assert no_launch == [run["id"]]

            from app.models.workflow_run import WorkflowRun

            row = await db_session.get(WorkflowRun, run["id"])
            row.status = "done"
            row.summary = "# Findings\n\nThe answer."
            await db_session.commit()

            output = await c.get(f"/api/v1/workflows/{run['id']}/output")
            assert output.status_code == 200
            assert output.text == "# Findings\n\nThe answer."
            assert output.headers["content-type"].startswith("text/markdown")
            assert output.headers["content-disposition"].endswith('.md"')

            changes = await c.get(f"/api/v1/workflows/{run['id']}/changes")
            assert changes.status_code == 409
            applied = await c.post(f"/api/v1/workflows/{run['id']}/applied")
            assert applied.status_code == 409
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_changes_conflict_while_running(db_session, no_launch):
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            run = await _create(c)
            await c.post(f"/api/v1/workflows/{run['id']}/start")
            resp = await c.get(f"/api/v1/workflows/{run['id']}/changes")
        assert resp.status_code == 409
        assert "still running" in resp.json()["detail"]
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_start_twice_conflicts(db_session, no_launch):
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            run = await _create(c)
            assert (await c.post(f"/api/v1/workflows/{run['id']}/start")).status_code == 200
            second = await c.post(f"/api/v1/workflows/{run['id']}/start")
        assert second.status_code == 409
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_upload_rejects_escaping_path(db_session):
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            run = await _create(c)
            resp = await c.post(
                f"/api/v1/workflows/{run['id']}/files",
                json={"files": [{"path": "../../evil.sh", "data": _b64("rm -rf /")}]},
            )
        assert resp.status_code == 400
        assert "escapes" in resp.json()["detail"]
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_runs_are_scoped_to_their_owner(db_session):
    db_session.add(User(email=OTHER, hashed_password=hash_password("x")))
    await db_session.commit()
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            run = await _create(c)
            switch.email = OTHER
            assert (await c.get(f"/api/v1/workflows/{run['id']}")).status_code == 404
            resp = await c.post(
                f"/api/v1/workflows/{run['id']}/files",
                json={"files": [{"path": "a.txt", "data": _b64("x")}]},
            )
            assert resp.status_code == 404
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_get_pages_progress_with_since(db_session):
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            run = await _create(c)

            from app.services.workflow_service import WorkflowService

            service = WorkflowService(db_session)
            row = await service.get(run["id"], OWNER)
            await service.start_snapshot(row)
            await service.append_progress(
                run["id"],
                [
                    {"type": "chunk", "content": "one"},
                    {"type": "tool_call", "content": ""},
                    {"type": "chunk", "content": "two"},
                ],
            )

            first = (await c.get(f"/api/v1/workflows/{run['id']}")).json()
            assert first["progress_total"] == 3
            assert len(first["progress"]) == 3

            tail = (
                await c.get(
                    f"/api/v1/workflows/{run['id']}",
                    params={"since": first["progress_total"]},
                )
            ).json()
            assert tail["progress"] == []
            assert tail["progress_offset"] == 3
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_polling_marks_the_run_as_watched(db_session):
    """The poll doubles as the "user is in the app" signal that suppresses
    the completion push."""
    from app.services import workflow_watchers

    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            run = await _create(c)
            assert not workflow_watchers.is_watched(run["id"])
            await c.get(f"/api/v1/workflows/{run['id']}")
            assert workflow_watchers.is_watched(run["id"])
    finally:
        workflow_watchers.forget(run["id"])
        _clear_overrides()


@pytest.mark.asyncio
async def test_list_for_conversation(db_session, test_conversation):
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            await _create(c, conversation_id=test_conversation.id)
            resp = await c.get(
                "/api/v1/workflows",
                params={"conversation_id": test_conversation.id},
            )
        assert resp.status_code == 200, resp.text
        runs = resp.json()
        assert len(runs) == 1
        assert runs[0]["conversation_id"] == test_conversation.id
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_create_captures_conversation_mcp_allowance(db_session, test_conversation):
    test_conversation.enabled_tools = ["server-1:web_search", "__garbo__:memories"]
    await db_session.commit()
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            run = await _create(
                c,
                mode="research",
                conversation_id=test_conversation.id,
            )
        assert run["scope"]["mcp_tools"] == ["server-1:web_search"]
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_create_imports_launching_message_attachment(db_session, test_conversation):
    payload = "Contrato para España".encode()
    db_session.add_all(
        [
            Message(
                id=str(uuid.uuid4()),
                conversation_id=test_conversation.id,
                role="user",
                content="analiza esto",
                seq=100,
                meta={
                    "attachments": [
                        {
                            "name": "contrato Hébridas.pdf",
                            "type": "document",
                            "mime_type": "application/pdf",
                            "encoding": "base64",
                            "data": base64.b64encode(payload).decode("ascii"),
                        }
                    ]
                },
            ),
            Message(
                id=str(uuid.uuid4()),
                conversation_id=test_conversation.id,
                role="tool_call",
                content="[]",
                seq=200,
                meta={"tool_calls": [{"id": "delegate-unicode"}]},
            ),
        ]
    )
    await db_session.commit()
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as c:
            created = await _create(
                c,
                conversation_id=test_conversation.id,
                tool_call_id="delegate-unicode",
                mode="research",
            )

        from app.models.workflow_run import WorkflowRun

        row = await db_session.get(WorkflowRun, created["id"])
        rel_path = row.scope["attachment_paths"][0]
        assert rel_path.endswith("contrato Hébridas.pdf")
        assert (Path(row.workdir) / rel_path).read_bytes() == payload
    finally:
        _clear_overrides()
