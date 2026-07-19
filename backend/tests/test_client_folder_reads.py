"""Tests for on-demand client-served folder reads (idea 17).

The attached folder lives only on the desktop client; the backend never touches
the host filesystem. Covers:
  * ``client_file_extract`` — text extraction from client-provided *bytes*
  * ``ClientToolBridge`` — the in-memory park/resolve/timeout bridge
  * ``ChatService._execute_client_folder_tool`` — the delegated read end-to-end
  * tool advertising gated on ``has_client_folder``
"""

import asyncio
import base64
from types import SimpleNamespace

import pytest

from app.services.chat_service import ChatService
from app.services.client_file_extract import MAX_FILE_BYTES, extract_file_text
from app.services.client_tool_bridge import ClientToolBridge

# ------------------------------------------------------------ extraction


def test_extract_plain_and_csv():
    assert extract_file_text("notes.txt", b"hello world") == "hello world"
    assert "1,2" in extract_file_text("data.csv", b"x,y\n1,2\n")


def test_extract_html_via_markitdown():
    out = extract_file_text("page.html", b"<h1>Title</h1><p>body</p>")
    assert "Title" in out


def test_extract_enforces_size_limit():
    out = extract_file_text("big.txt", b"a" * (MAX_FILE_BYTES + 1))
    assert "too large" in out.lower()


def test_extract_rejects_binary():
    out = extract_file_text("blob.bin", bytes(range(256)) * 40)
    assert "readable text" in out.lower()


# ------------------------------------------------------------ bridge


@pytest.mark.asyncio
async def test_bridge_resolve_completes_request():
    bridge = ClientToolBridge()
    payload = {"ok": True, "data": "x"}

    async def responder():
        # resolve() returns False until the future is registered — retry.
        for _ in range(200):
            if bridge.resolve("c1", "t1", payload):
                return
            await asyncio.sleep(0.005)

    async def emit():
        pass

    task = asyncio.create_task(responder())
    result = await bridge.request(
        conversation_id="c1", tool_call_id="t1", on_registered=emit, timeout_seconds=2
    )
    await task
    assert result == payload


@pytest.mark.asyncio
async def test_bridge_times_out_without_response():
    bridge = ClientToolBridge()

    async def emit():
        pass

    result = await bridge.request(
        conversation_id="c1", tool_call_id="t1", on_registered=emit, timeout_seconds=0.05
    )
    assert result["ok"] is False
    assert "time" in result["error"].lower()


def test_bridge_resolve_unknown_returns_false():
    bridge = ClientToolBridge()
    assert bridge.resolve("c1", "missing", {"ok": True}) is False


# ------------------------------------------ delegated executor end-to-end


@pytest.mark.asyncio
async def test_execute_client_folder_tool_read_file(db_session):
    from app.services import chat_service as chat_service_module

    svc = ChatService(db_session)
    conversation = SimpleNamespace(id="conv1", user_id="u@example.com")
    emitted = []

    async def emit(chunk):
        emitted.append(chunk)

    async def responder():
        data = base64.b64encode(b"hello from the folder").decode()
        payload = {"ok": True, "filename": "a.txt", "data": data}
        for _ in range(200):
            if chat_service_module.client_tool_bridge.resolve("conv1", "tc1", payload):
                return
            await asyncio.sleep(0.005)

    task = asyncio.create_task(responder())
    result = await svc._execute_client_folder_tool(
        {"id": "tc1", "name": "read_file"},
        "read_file",
        {"path": "a.txt"},
        conversation,
        emit,
    )
    await task

    assert result["ok"] is True
    assert result["content"] == "hello from the folder"
    # The client was asked via a client_tool_request chunk.
    assert emitted[0].metadata["client_tool_request"]["tool_name"] == "read_file"
    assert emitted[0].metadata["client_tool_request"]["args"] == {"path": "a.txt"}


@pytest.mark.asyncio
async def test_execute_client_folder_tool_propagates_client_error(db_session):
    from app.services import chat_service as chat_service_module

    svc = ChatService(db_session)
    conversation = SimpleNamespace(id="conv2", user_id="u@example.com")

    async def emit(chunk):
        pass

    async def responder():
        payload = {"ok": False, "error": "Path escapes the folder."}
        for _ in range(200):
            if chat_service_module.client_tool_bridge.resolve("conv2", "tc2", payload):
                return
            await asyncio.sleep(0.005)

    task = asyncio.create_task(responder())
    result = await svc._execute_client_folder_tool(
        {"id": "tc2", "name": "read_file"},
        "read_file",
        {"path": "../../etc/passwd"},
        conversation,
        emit,
    )
    await task
    assert result["ok"] is False
    assert "escape" in result["error"].lower()


# --------------------------------------------- tool advertising gate


@pytest.mark.asyncio
async def test_folder_tools_only_advertised_with_client_folder(db_session):
    svc = ChatService(db_session)
    conversation = SimpleNamespace(id="c", user_id="u@example.com", enabled_tools=None)

    without_tools, without_lookup = await svc._resolve_tools_for_conversation(
        conversation, has_client_folder=False
    )
    without_names = {t["function"]["name"] for t in without_tools}
    assert "read_file" not in without_names
    assert "list_files" not in without_names

    with_tools, with_lookup = await svc._resolve_tools_for_conversation(
        conversation, has_client_folder=True
    )
    with_names = {t["function"]["name"] for t in with_tools}
    assert {"read_file", "list_files"} <= with_names
    assert with_lookup["read_file"] == ("__garbo__", "read_file")
