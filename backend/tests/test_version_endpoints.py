"""Tests for the health version field and GET /api/v1/version/latest."""

from unittest.mock import MagicMock, patch

import httpx
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.services import version_service

pytestmark = pytest.mark.asyncio


_RELEASE_PAYLOAD = {
    "tag_name": "v1.0.4",
    "name": "Release v1.0.4",
    "body": "## What's Changed\n- stuff",
    "published_at": "2026-07-01T12:00:00Z",
    "html_url": "https://github.com/owner/repo/releases/tag/v1.0.4",
    "assets": [
        {
            "name": "garbanzo-ai-linux-1.0.4.tar.gz",
            "browser_download_url": "https://github.com/owner/repo/releases/download/v1.0.4/garbanzo-ai-linux-1.0.4.tar.gz",
            "size": 12345,
        },
        {
            "name": "garbanzo-ai-windows-1.0.4.zip",
            "browser_download_url": "https://github.com/owner/repo/releases/download/v1.0.4/garbanzo-ai-windows-1.0.4.zip",
            "size": 67890,
        },
    ],
}


@pytest.fixture(autouse=True)
def _clear_release_cache():
    version_service.clear_cache()
    yield
    version_service.clear_cache()


def _github_response(status_code: int = 200, payload: dict | None = None) -> MagicMock:
    resp = MagicMock()
    resp.status_code = status_code
    resp.json.return_value = payload if payload is not None else _RELEASE_PAYLOAD
    return resp


def _patch_github(response: MagicMock | Exception):
    """Patch httpx.AsyncClient in the service; returns the patcher."""
    mock_cls = MagicMock()
    client = mock_cls.return_value.__aenter__.return_value
    if isinstance(response, Exception):
        client.get.side_effect = response
    else:
        client.get.return_value = response
    return patch("app.services.version_service.httpx.AsyncClient", mock_cls), mock_cls


async def _get(path: str):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        return await client.get(path)


class TestHealthVersion:
    async def test_health_includes_version(self):
        response = await _get("/api/v1/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["version"]


class TestLatestVersion:
    async def test_returns_parsed_release(self):
        patcher, _ = _patch_github(_github_response())
        with patcher:
            response = await _get("/api/v1/version/latest")
        assert response.status_code == 200
        data = response.json()
        assert data["version"] == "1.0.4"
        assert data["tag_name"] == "v1.0.4"
        assert data["body"].startswith("## What's Changed")
        assert [a["name"] for a in data["assets"]] == [
            "garbanzo-ai-linux-1.0.4.tar.gz",
            "garbanzo-ai-windows-1.0.4.zip",
        ]
        assert all(a["download_url"] and a["size"] for a in data["assets"])

    async def test_second_call_served_from_cache(self):
        patcher, mock_cls = _patch_github(_github_response())
        with patcher:
            first = await _get("/api/v1/version/latest")
            second = await _get("/api/v1/version/latest")
        assert first.status_code == second.status_code == 200
        client = mock_cls.return_value.__aenter__.return_value
        assert client.get.await_count == 1

    async def test_no_releases_maps_to_404(self):
        patcher, _ = _patch_github(_github_response(status_code=404, payload={}))
        with patcher:
            response = await _get("/api/v1/version/latest")
        assert response.status_code == 404

    async def test_github_error_maps_to_502(self):
        patcher, _ = _patch_github(_github_response(status_code=500, payload={}))
        with patcher:
            response = await _get("/api/v1/version/latest")
        assert response.status_code == 502

    async def test_network_failure_maps_to_503(self):
        patcher, _ = _patch_github(httpx.ConnectError("boom"))
        with patcher:
            response = await _get("/api/v1/version/latest")
        assert response.status_code == 503
