"""Tests for the /micro-apps reverse proxy — panel tokens, auth, forwarding."""

import asyncio

import pytest
from httpx import ASGITransport, AsyncClient

from app.api import microapps_proxy
from app.core.config import Settings
from app.core.security import (
    create_access_token,
    create_microapps_panel_token,
    verify_microapps_panel_token,
)
from app.main import app


def _settings(**overrides) -> Settings:
    kwargs = {
        "secret_key": "test-secret-key-do-not-use-in-prod",
        "microapps_repo_path": "/tmp/micro-apps-test",
        "microapps_proxy_mode": True,
        **overrides,
    }
    return Settings(**kwargs)


class _StubManager:
    enabled = True

    def __init__(self, port: int) -> None:
        self._port = port

    def dev_port_for(self, slug: str) -> int:
        return self._port


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


# ============================================================================
# Panel tokens
# ============================================================================


class TestPanelToken:
    def test_round_trip(self):
        settings = _settings()
        token = create_microapps_panel_token("a@b.com", "a-b-com", settings)
        assert verify_microapps_panel_token(token, settings) == "a-b-com"

    def test_access_token_rejected(self):
        settings = _settings()
        token = create_access_token({"sub": "a@b.com"}, settings)
        assert verify_microapps_panel_token(token, settings) is None

    def test_garbage_rejected(self):
        assert verify_microapps_panel_token("not-a-jwt", _settings()) is None

    def test_panel_token_cannot_be_an_access_token(self):
        # get_current_user only accepts type=access; panel tokens carry their own type.
        from app.core.security import decode_token

        settings = _settings()
        token = create_microapps_panel_token("a@b.com", "a-b-com", settings)
        payload = decode_token(token, settings)
        assert payload["type"] == "microapps-panel"


# ============================================================================
# HTTP proxying
# ============================================================================


async def _start_upstream(body: bytes = b"hello-from-dev-server"):
    """One-shot HTTP/1.1 server standing in for a dev server."""
    received: list[bytes] = []

    async def handle(reader, writer):
        received.append(await reader.readuntil(b"\r\n\r\n"))
        writer.write(
            b"HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ncontent-length: "
            + str(len(body)).encode()
            + b"\r\n\r\n"
            + body
        )
        await writer.drain()
        writer.close()

    server = await asyncio.start_server(handle, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    return server, port, received


class TestProxyHttp:
    pytestmark = pytest.mark.asyncio

    @pytest.fixture(autouse=True)
    def _fresh_client(self):
        # The proxy caches its AsyncClient on first use; each test runs in its
        # own event loop, so reset it to avoid cross-loop reuse.
        microapps_proxy._client = None
        yield
        microapps_proxy._client = None

    async def test_404_when_proxy_mode_off(self, monkeypatch):
        monkeypatch.setattr(
            microapps_proxy, "get_settings", lambda: _settings(microapps_proxy_mode=False)
        )
        async with _client() as c:
            resp = await c.get("/micro-apps/house-designer/")
        assert resp.status_code == 404

    async def test_401_without_token(self, monkeypatch):
        settings = _settings()
        monkeypatch.setattr(microapps_proxy, "get_settings", lambda: settings)
        monkeypatch.setattr(microapps_proxy, "manager", _StubManager(1))
        async with _client() as c:
            resp = await c.get("/micro-apps/house-designer/")
        assert resp.status_code == 401

    async def test_401_with_access_token(self, monkeypatch):
        settings = _settings()
        monkeypatch.setattr(microapps_proxy, "get_settings", lambda: settings)
        monkeypatch.setattr(microapps_proxy, "manager", _StubManager(1))
        token = create_access_token({"sub": "a@b.com"}, settings)
        async with _client() as c:
            resp = await c.get(f"/micro-apps/house-designer/?mp_token={token}")
        assert resp.status_code == 401

    async def test_forwards_and_sets_cookie(self, monkeypatch):
        settings = _settings()
        server, port, received = await _start_upstream()
        monkeypatch.setattr(microapps_proxy, "get_settings", lambda: settings)
        monkeypatch.setattr(microapps_proxy, "manager", _StubManager(port))
        token = create_microapps_panel_token("a@b.com", "a-b-com", settings)
        try:
            async with _client() as c:
                resp = await c.get(f"/micro-apps/house-designer/?embed=1&mp_token={token}")
        finally:
            server.close()
            await server.wait_closed()
        assert resp.status_code == 200
        assert resp.content == b"hello-from-dev-server"
        assert "mp_panel" in resp.headers.get("set-cookie", "")
        # mp_token is stripped from the forwarded request; other params kept.
        request_line = received[0].split(b"\r\n")[0].decode()
        assert "mp_token" not in request_line
        assert "embed=1" in request_line
        assert request_line.startswith("GET /micro-apps/house-designer/")

    async def test_cookie_routes_without_query_token(self, monkeypatch):
        settings = _settings()
        server, port, _ = await _start_upstream(b"cookie-ok")
        monkeypatch.setattr(microapps_proxy, "get_settings", lambda: settings)
        monkeypatch.setattr(microapps_proxy, "manager", _StubManager(port))
        token = create_microapps_panel_token("a@b.com", "a-b-com", settings)
        try:
            async with _client() as c:
                c.cookies.set("mp_panel", token)
                resp = await c.get(
                    "/micro-apps/house-designer/assets/app.js",
                )
        finally:
            server.close()
            await server.wait_closed()
        assert resp.status_code == 200
        assert resp.content == b"cookie-ok"
        # No entry token → no new cookie needed.
        assert "set-cookie" not in resp.headers

    async def test_502_when_dev_server_down(self, monkeypatch):
        settings = _settings()
        monkeypatch.setattr(microapps_proxy, "get_settings", lambda: settings)
        # Port 1 is never listening.
        monkeypatch.setattr(microapps_proxy, "manager", _StubManager(1))
        token = create_microapps_panel_token("a@b.com", "a-b-com", settings)
        async with _client() as c:
            resp = await c.get(f"/micro-apps/house-designer/?mp_token={token}")
        assert resp.status_code == 502
