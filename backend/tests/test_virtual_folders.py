"""Persistence, ownership, original downloads and revision-safe AI folder editing."""

import hashlib
import io
import json
import zipfile
from unittest.mock import AsyncMock

import pytest
import pytest_asyncio
from openpyxl import Workbook
from sqlalchemy import select, update
from sqlalchemy.exc import SQLAlchemyError

from app.db import session as db_session_module
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.models.virtual_folder import ConversationFolder
from app.services import virtual_folder_service, virtual_folder_tools
from app.services.chat_service import ChatService
from app.services.llm_provider import ChatChunk
from app.services.native_tools import execute_native_tool
from app.services.virtual_folder_service import FolderError, VirtualFolderService
from tests.test_chat_tool_loop import _make_service, _ScriptedProvider
from tests.test_workflow_endpoints import _clear_overrides, _client, _install_overrides, _UserSwitch

OWNER = "test@example.com"


@pytest_asyncio.fixture
async def folders_client(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            yield client, switch
    finally:
        _clear_overrides()


async def _folder(client):
    response = await client.post("/api/v1/folders", json={"name": "My research 🌱"})
    assert response.status_code == 201, response.text
    return response.json()["id"]


async def _tool(db, **args):
    return await execute_native_tool(name="virtual_folders", args=args, db=db, user_id=OWNER)


@pytest.mark.asyncio
async def test_original_upload_download_zip_and_persistence(folders_client, db_session):
    client, _ = folders_client
    folder_id = await _folder(client)
    raw = "España 🌱\n".encode() + b"\x00\xff"
    response = await client.post(
        f"/api/v1/folders/{folder_id}/files",
        files={"file": ("datos.bin", raw)},
        data={"path": "nested/datos España.bin"},
    )
    assert response.status_code == 201, response.text
    file = response.json()
    assert "data" not in file and file["revision"] == 1
    # A fresh session, as used by another device/chat turn, sees the same bytes.
    async with db_session_module.async_session_maker() as session:
        service = VirtualFolderService(session)
        stored = await service.get_file(folder_id, file["id"], OWNER, data=True)
        assert stored.data == raw
    downloaded = await client.get(f"/api/v1/folders/{folder_id}/files/{file['id']}/content")
    assert downloaded.content == raw
    assert "UTF-8''datos%20Espa%C3%B1a.bin" in downloaded.headers["content-disposition"]
    zipped = await client.get(f"/api/v1/folders/{folder_id}/download")
    assert zipped.status_code == 200
    with zipfile.ZipFile(io.BytesIO(zipped.content)) as archive:
        assert archive.namelist() == ["nested/datos España.bin"]
        assert archive.read(archive.namelist()[0]) == raw
    read = await client.get(f"/api/v1/folders/{folder_id}/files/{file['id']}/text")
    assert read.status_code == 400


@pytest.mark.asyncio
async def test_text_edit_conflicts_and_binary_is_read_only(folders_client):
    client, _ = folders_client
    folder_id = await _folder(client)
    response = await client.post(
        f"/api/v1/folders/{folder_id}/text", json={"path": "notes.md", "content": "original 🌱"}
    )
    assert response.status_code == 201, response.text
    file = response.json()
    url = f"/api/v1/folders/{folder_id}/files/{file['id']}/text"
    page = (await client.get(url, params={"limit": 4})).json()
    assert page["editable"] and page["text"] == "orig" and page["next_offset"] == 4
    saved = await client.put(url, json={"content": "changed", "revision": 1})
    assert saved.status_code == 200 and saved.json()["revision"] == 2
    conflict = await client.put(url, json={"content": "stale", "revision": 1})
    assert conflict.status_code == 409
    assert (await client.get(url)).json()["text"] == "changed"
    duplicate = await client.post(
        f"/api/v1/folders/{folder_id}/files", files={"file": ("notes.md", b"overwrite")}
    )
    assert duplicate.status_code == 409
    binary = await client.post(
        f"/api/v1/folders/{folder_id}/files", files={"file": ("pretends.txt", b"\x00\xff")}
    )
    binary_url = f"/api/v1/folders/{folder_id}/files/{binary.json()['id']}/text"
    assert (
        await client.put(binary_url, json={"content": "replace", "revision": 1})
    ).status_code == 400
    assert (
        await client.post(
            f"/api/v1/folders/{folder_id}/text", json={"path": "fake.pdf", "content": "fake PDF"}
        )
    ).status_code == 400
    delete_url = f"/api/v1/folders/{folder_id}/files/{file['id']}"
    assert (await client.delete(delete_url, params={"revision": 1})).status_code == 409
    assert (await client.delete(delete_url, params={"revision": 2})).status_code == 204


@pytest.mark.asyncio
async def test_duplicate_upload_choices_preserve_originals_and_guard_replacements(folders_client):
    client, _ = folders_client
    folder_id = await _folder(client)
    url = f"/api/v1/folders/{folder_id}/files"
    original = (
        await client.post(
            url,
            files={"file": ("report.pdf", b"old PDF bytes")},
            data={"path": "nested/report.pdf"},
        )
    ).json()
    duplicate = await client.post(
        url,
        files={"file": ("report.pdf", b"new PDF bytes")},
        data={"path": original["path"]},
    )
    assert duplicate.status_code == 409
    for number in [2, 3]:
        copy = await client.post(
            url,
            files={"file": ("report.pdf", b"copy bytes")},
            data={"path": original["path"], "keep_both": "true"},
        )
        assert copy.status_code == 201, copy.text
        assert copy.json()["path"] == f"nested/report ({number}).pdf"
        assert copy.json()["id"] != original["id"] and copy.json()["revision"] == 1
    content_url = f"{url}/{original['id']}/content"
    assert (await client.get(content_url)).content == b"old PDF bytes"
    replacement = b"\x00\xffnew PDF original bytes"
    replaced = await client.put(
        content_url, files={"file": ("report.pdf", replacement)}, data={"revision": 1}
    )
    assert replaced.status_code == 200, replaced.text
    metadata = replaced.json()
    assert metadata["id"] == original["id"] and metadata["path"] == original["path"]
    assert metadata["revision"] == 2 and metadata["media_type"] == "application/pdf"
    assert metadata["size_bytes"] == len(replacement)
    assert metadata["sha256"] == hashlib.sha256(replacement).hexdigest()
    stale = await client.put(
        content_url, files={"file": ("report.pdf", b"stale")}, data={"revision": 1}
    )
    assert stale.status_code == 409
    assert (await client.get(content_url)).content == replacement
    zipped = await client.get(f"/api/v1/folders/{folder_id}/download")
    with zipfile.ZipFile(io.BytesIO(zipped.content)) as archive:
        assert archive.read("nested/report.pdf") == replacement
        assert archive.read("nested/report (2).pdf") == b"copy bytes"


@pytest.mark.asyncio
async def test_raw_replacement_uses_quota_delta_without_adding_file(db_session, monkeypatch):
    service = VirtualFolderService(db_session)
    folder = await service.create_folder(OWNER, "Full folder")
    monkeypatch.setattr(virtual_folder_service, "MAX_FILES", 1)
    monkeypatch.setattr(virtual_folder_service, "MAX_FOLDER_BYTES", 6)
    monkeypatch.setattr(virtual_folder_service, "MAX_USER_BYTES", 6)
    file = await service.create_file(folder.id, OWNER, "data.bin", b"123456")
    replaced = await service.replace_file(folder.id, file.id, OWNER, b"1234", 1)
    assert replaced.revision == 2 and replaced.size_bytes == 4
    with pytest.raises(FolderError, match="100 MiB"):
        await service.replace_file(folder.id, file.id, OWNER, b"1234567", 2)
    with pytest.raises(FolderError, match="500-file"):
        await service.create_file(folder.id, OWNER, file.path, b"x", keep_both=True)
    assert len(await service.list_files(folder.id, OWNER)) == 1
    assert (await service.get_file(folder.id, file.id, OWNER, data=True)).data == b"1234"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "path", ["../outside", "/absolute", "a/../b", "a\\b", "a//b", ".", "a\nb", "C:evil", "a/./b"]
)
async def test_unsafe_paths_rejected(folders_client, path):
    client, _ = folders_client
    folder_id = await _folder(client)
    response = await client.post(
        f"/api/v1/folders/{folder_id}/text", json={"path": path, "content": "text"}
    )
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_owner_scoping_for_every_operation_and_chat_link(
    folders_client, test_conversation, db_session
):
    client, switch = folders_client
    folder_id = await _folder(client)
    file = (
        await client.post(
            f"/api/v1/folders/{folder_id}/text", json={"path": "private.txt", "content": "secret"}
        )
    ).json()
    db_session.add(User(email="stranger@example.com", hashed_password="unused"))
    await db_session.commit()
    switch.email = "stranger@example.com"
    assert (await client.get("/api/v1/folders")).json() == []
    operations = [
        ("get", f"/{folder_id}/files", {}),
        ("get", f"/{folder_id}/download", {}),
        ("get", f"/{folder_id}/files/{file['id']}/content", {}),
        (
            "put",
            f"/{folder_id}/files/{file['id']}/content",
            {"files": {"file": ("private.txt", b"stolen")}, "data": {"revision": 1}},
        ),
        ("get", f"/{folder_id}/files/{file['id']}/text", {}),
        ("delete", f"/{folder_id}", {}),
        ("patch", f"/{folder_id}", {"json": {"name": "stolen"}}),
        ("patch", f"/{folder_id}", {"json": {"description": "stolen context"}}),
        ("post", f"/{folder_id}/text", {"json": {"path": "new.txt", "content": "bad"}}),
        (
            "put",
            f"/{folder_id}/files/{file['id']}/text",
            {"json": {"content": "bad", "revision": 1}},
        ),
        ("delete", f"/{folder_id}/files/{file['id']}?revision=1", {}),
        ("get", f"/conversations/{test_conversation.id}", {}),
        ("put", f"/conversations/{test_conversation.id}/{folder_id}", {}),
        ("delete", f"/conversations/{test_conversation.id}/{folder_id}", {}),
    ]
    for method, path, kwargs in operations:
        response = await client.request(method, "/api/v1/folders" + path, **kwargs)
        assert response.status_code == 404, (method, path, response.text)
    switch.email = OWNER
    db_session.add(Conversation(id="strangers-chat", user_id="stranger@example.com", model="model"))
    await db_session.commit()
    assert (
        await client.put(f"/api/v1/folders/conversations/strangers-chat/{folder_id}")
    ).status_code == 404
    assert (await client.get(f"/api/v1/folders/{folder_id}/files/{file['id']}/text")).json()[
        "text"
    ] == "secret"


@pytest.mark.asyncio
async def test_folder_metadata_partial_edits_clear_and_persist(folders_client, db_session):
    client, _ = folders_client
    description = "Orchid research 🌱\nReferences for next year's field trials."
    created = await client.post(
        "/api/v1/folders", json={"name": "Research", "description": description}
    )
    assert created.status_code == 201, created.text
    folder_id = created.json()["id"]
    url = f"/api/v1/folders/{folder_id}"
    renamed = await client.patch(url, json={"name": "Orchids"})
    assert renamed.status_code == 200 and renamed.json()["description"] == description
    updated = await client.patch(url, json={"description": "Field trials and source papers"})
    assert updated.status_code == 200 and updated.json()["name"] == "Orchids"
    async with db_session_module.async_session_maker() as session:
        folder = await VirtualFolderService(session).owned_folder(folder_id, OWNER)
        assert folder.name == "Orchids" and folder.description == "Field trials and source papers"
    cleared = await client.patch(url, json={"description": ""})
    assert cleared.status_code == 200 and cleared.json()["description"] == ""
    assert (await client.get("/api/v1/folders")).json()[0]["description"] == ""


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "changes",
    [
        {},
        {"description": None},
        {"name": None},
        {"name": "   "},
        {"description": "x" * 2001},
        {"description": "bad\x00context"},
        {"context": "unknown field"},
    ],
)
async def test_invalid_metadata_patch_leaves_folder_intact(folders_client, changes):
    client, _ = folders_client
    folder_id = await _folder(client)
    response = await client.patch(f"/api/v1/folders/{folder_id}", json=changes)
    assert response.status_code == 422, response.text
    folder = (await client.get("/api/v1/folders")).json()[0]
    assert folder["name"] == "My research 🌱" and folder["description"] == ""


@pytest.mark.asyncio
async def test_ai_metadata_discovery_update_and_current_manifest(db_session, test_conversation):
    created = await _tool(
        db_session, action="create", name="Trip", description="Receipts and plans for Madrid"
    )
    assert created["ok"], created
    folder_id = created["folder"]["id"]
    assert (await _tool(db_session, action="list"))["folders"][0]["description"] == (
        "Receipts and plans for Madrid"
    )
    service = VirtualFolderService(db_session)
    await service.attach(test_conversation.id, folder_id, OWNER)
    updated = await _tool(
        db_session,
        action="update_folder",
        folder_id=folder_id,
        description="Madrid and Barcelona trip planning",
    )
    assert updated["ok"] and updated["folder"]["name"] == "Trip", updated
    manifest = await service.context_manifest(test_conversation.id, OWNER)
    assert "Madrid and Barcelona trip planning" in manifest
    assert "Receipts and plans for Madrid" not in manifest
    assert "not instructions" in manifest
    renamed = await _tool(db_session, action="update_folder", folder_id=folder_id, name="Spain")
    assert renamed["ok"] and renamed["folder"]["description"] == updated["folder"]["description"]
    for changes in [{}, {"description": None}, {"description": "x" * 2001}]:
        rejected = await _tool(db_session, action="update_folder", folder_id=folder_id, **changes)
        assert not rejected["ok"]
    cleared = await _tool(db_session, action="update_folder", folder_id=folder_id, description="")
    assert cleared["ok"] and cleared["folder"]["description"] == ""
    db_session.add(User(email="stranger@example.com", hashed_password="unused"))
    await db_session.commit()
    rejected = await execute_native_tool(
        name="virtual_folders",
        args={"action": "update_folder", "folder_id": folder_id, "description": "stolen"},
        db=db_session,
        user_id="stranger@example.com",
    )
    assert not rejected["ok"] and "not found" in rejected["error"].lower()


@pytest.mark.asyncio
async def test_chat_links_reusable_detach_and_delete_cascade(db_session, test_conversation):
    service = VirtualFolderService(db_session)
    folder = await service.create_folder(OWNER, "Shared across my chats")
    file = await service.create_text(folder.id, OWNER, "notes.md", "persistent")
    other = Conversation(id="another-chat", user_id=OWNER, model="model")
    db_session.add(other)
    await db_session.commit()
    await service.attach(test_conversation.id, folder.id, OWNER)
    await service.attach(test_conversation.id, folder.id, OWNER)  # idempotent
    await service.attach(other.id, folder.id, OWNER)
    assert len(await service.attached_folders(test_conversation.id, OWNER)) == 1
    await service.detach(test_conversation.id, folder.id, OWNER)
    assert not await service.attached_folders(test_conversation.id, OWNER)
    assert len(await service.attached_folders(other.id, OWNER)) == 1
    assert (await service.get_file(folder.id, file.id, OWNER, data=True)).data == b"persistent"
    await db_session.delete(other)
    await db_session.commit()
    assert len(await service.list_files(folder.id, OWNER)) == 1
    await service.delete_folder(folder.id, OWNER)
    assert not list(await db_session.scalars(select(ConversationFolder)))


@pytest.mark.asyncio
async def test_quotas_and_file_directory_collisions(db_session, monkeypatch):
    service = VirtualFolderService(db_session)
    folder = await service.create_folder(OWNER, "bounded")
    monkeypatch.setattr(virtual_folder_service, "MAX_FILE_BYTES", 5)
    monkeypatch.setattr(virtual_folder_service, "MAX_FOLDER_BYTES", 8)
    monkeypatch.setattr(virtual_folder_service, "MAX_USER_BYTES", 9)
    file = await service.create_text(folder.id, OWNER, "first.txt", "12345")
    with pytest.raises(FolderError, match="10 MiB"):
        await service.create_file(folder.id, OWNER, "large", b"123456")
    with pytest.raises(FolderError, match="100 MiB"):
        await service.create_file(folder.id, OWNER, "second", b"1234")
    with pytest.raises(FolderError, match="conflicts"):
        await service.create_file(folder.id, OWNER, "first.txt/nested", b"x")
    await service.update_text(folder.id, file.id, OWNER, "12", 1)
    other = await service.create_folder(OWNER, "other")
    await service.create_file(other.id, OWNER, "second", b"12345")
    with pytest.raises(FolderError, match="500 MiB"):
        await service.create_file(folder.id, OWNER, "third", b"123")
    monkeypatch.setattr(virtual_folder_service, "MAX_FILES", 1)
    with pytest.raises(FolderError, match="500-file"):
        await service.create_file(folder.id, OWNER, "fourth", b"")


@pytest.mark.asyncio
async def test_ai_create_edit_paged_read_download_and_current_chat_only(
    db_session, test_conversation, monkeypatch
):
    created = await _tool(db_session, action="create", name="AI notes")
    assert created["ok"], created
    folder_id = created["folder"]["id"]
    result = await _tool(
        db_session,
        action="write_file",
        folder_id=folder_id,
        path="notes.md",
        content="España 🌱\n" * 600,
    )
    assert result["ok"], result
    file_id = result["file"]["id"]
    rejected = await _tool(
        db_session, action="write_file", folder_id=folder_id, file_id=file_id, content="stale"
    )
    assert not rejected["ok"]
    settings = virtual_folder_tools.get_settings().model_copy(
        update={"tool_result_max_chars": 2000}
    )
    monkeypatch.setattr(virtual_folder_tools, "get_settings", lambda: settings)
    text = []
    offset = 0
    while True:
        page = await _tool(
            db_session, action="read_file", folder_id=folder_id, file_id=file_id, offset=offset
        )
        assert page["ok"] and len(json.dumps(page)) <= 2000, page
        assert page["file"]["revision"] == 1
        text.append(page["text"])
        if page["next_offset"] is None:
            break
        offset = page["next_offset"]
    assert "".join(text) == "España 🌱\n" * 600
    download = await _tool(db_session, action="download", folder_id=folder_id, file_id=file_id)
    assert download["download"]["file_id"] == file_id
    service = ChatService(db_session)
    attached = await service._execute_garbo_tool(
        "virtual_folders",
        {"action": "attach", "folder_id": folder_id, "_conversation_id": "forged-chat"},
        test_conversation,
    )
    assert attached["ok"], attached
    assert (
        len(await VirtualFolderService(db_session).attached_folders(test_conversation.id, OWNER))
        == 1
    )
    assert not (await _tool(db_session, action="attach", folder_id=folder_id))["ok"]


@pytest.mark.asyncio
async def test_attached_manifest_and_tools_honor_disabled_tools(
    db_session, test_conversation, monkeypatch
):
    service = VirtualFolderService(db_session)
    folder = await service.create_folder(
        OWNER, "My saved folder", description="Published orchid field trials"
    )
    await service.create_text(folder.id, OWNER, "notes.txt", "Do not inject this content")
    await service.attach(test_conversation.id, folder.id, OWNER)
    provider = _ScriptedProvider(
        [[ChatChunk(content="Ready"), ChatChunk(content="", is_finished=True)]]
    )
    chat = await _make_service(db_session, provider)
    chat._mcp.list_all_tools = AsyncMock(return_value=[])
    monkeypatch.setattr(chat, "_spawn_title_generation", lambda *args: None)
    chunks = [
        chunk async for chunk in chat.send_message(test_conversation.id, OWNER, "Use my folder")
    ]
    assert any(c.content == "Ready" for c in chunks)
    prompt = "\n".join(m.content for m in provider.calls[0]["messages"] if m.role == "system")
    assert folder.id in prompt and folder.name in prompt
    assert folder.description in prompt
    assert "Do not inject this content" not in prompt
    assert any(t["function"]["name"] == "virtual_folders" for t in provider.calls[0]["tools"])
    test_conversation.enabled_tools = []
    await db_session.commit()
    tools, lookup = await chat._resolve_tools_for_conversation(test_conversation)
    assert tools == [] and lookup == {}


@pytest.mark.asyncio
async def test_failed_native_commit_returns_failure(db_session, test_conversation, monkeypatch):
    chat = ChatService(db_session)
    monkeypatch.setattr(
        "app.services.chat_service.execute_native_tool", AsyncMock(return_value={"ok": True})
    )
    monkeypatch.setattr(
        db_session, "commit", AsyncMock(side_effect=RuntimeError("storage unavailable"))
    )
    result = await chat._execute_garbo_tool(
        "memories", {"action": "create", "name": "x"}, test_conversation
    )
    assert not result["ok"] and "not saved" in result["error"]


@pytest.mark.asyncio
async def test_failed_folder_storage_preserves_chat_call_result_and_origin_epoch(
    db_session, test_conversation, monkeypatch
):
    conversation_id = test_conversation.id
    epoch = test_conversation.session_epoch

    async def fail_create(service, user_id, name, *, description=""):
        await service.db.rollback()
        # Emulate a concurrent session switch before the tool error is handled.
        await service.db.execute(
            update(Conversation)
            .where(Conversation.id == conversation_id)
            .values(session_epoch=epoch + 1)
        )
        await service.db.commit()
        raise SQLAlchemyError("Injected folder storage failure")

    monkeypatch.setattr(VirtualFolderService, "create_folder", fail_create)
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(
                    content="",
                    tool_calls=[
                        {
                            "id": "folder-failure",
                            "name": "virtual_folders",
                            "arguments": {"action": "create", "name": "notes"},
                        }
                    ],
                ),
                ChatChunk(content="", is_finished=True),
            ],
            [
                ChatChunk(content="The file operation failed."),
                ChatChunk(content="", is_finished=True),
            ],
        ]
    )
    chat = await _make_service(db_session, provider)
    chat._mcp.list_all_tools = AsyncMock(return_value=[])
    monkeypatch.setattr(chat, "_spawn_title_generation", lambda *args: None)
    chunks = [chunk async for chunk in chat.send_message(conversation_id, OWNER, "Create notes")]
    assert any(c.content == "The file operation failed." for c in chunks)
    errors = [c for c in chunks if c.metadata and c.metadata.get("error")]
    assert not errors
    messages = list(
        await db_session.scalars(select(Message).where(Message.conversation_id == conversation_id))
    )
    assert [m.role for m in messages] == ["user", "tool_call", "tool_result", "assistant"]
    result = next(m for m in messages if m.role == "tool_result")
    assert "Injected folder storage failure" in result.content
    assert all(m.session_epoch == epoch for m in messages)
    db_session.expire_all()
    assert (await db_session.get(Conversation, conversation_id)).session_epoch == epoch + 1


@pytest.mark.asyncio
async def test_disabled_tool_cannot_execute_using_legacy_raw_name(db_session, test_conversation):
    chat = ChatService(db_session)
    for name in ["virtual_folders", "__garbo__:virtual_folders"]:
        result = await chat._execute_tool_call(
            {"name": name, "arguments": {"action": "create", "name": "bypass"}},
            {},
            test_conversation,
        )
        assert not result["ok"]
    assert not await VirtualFolderService(db_session).list_folders(OWNER)
    allowed = await chat._execute_tool_call(
        {"name": "__garbo__:virtual_folders", "arguments": {"action": "create", "name": "allowed"}},
        {"virtual_folders": ("__garbo__", "virtual_folders")},
        test_conversation,
    )
    assert allowed["ok"]


@pytest.mark.asyncio
async def test_spreadsheet_extraction_is_read_only_and_retains_original_bytes(folders_client):
    client, _ = folders_client
    folder_id = await _folder(client)
    workbook = Workbook()
    workbook.active.append(["Country", "Measurement"])
    workbook.active.append(["España", 731.42])
    data = io.BytesIO()
    workbook.save(data)
    raw = data.getvalue()
    response = await client.post(
        f"/api/v1/folders/{folder_id}/files", files={"file": ("data.xlsx", raw)}
    )
    assert response.status_code == 201
    file_id = response.json()["id"]
    url = f"/api/v1/folders/{folder_id}/files/{file_id}/text"
    page = await client.get(url)
    assert page.status_code == 200, page.text
    assert not page.json()["editable"]
    assert "España" in page.json()["text"] and "731.42" in page.json()["text"]
    assert (await client.put(url, json={"revision": 1, "content": "overwrite"})).status_code == 400
    assert (await client.get(f"/api/v1/folders/{folder_id}/files/{file_id}/content")).content == raw
