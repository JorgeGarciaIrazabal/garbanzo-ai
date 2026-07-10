"""Authenticated reverse proxy for micro-app dev servers.

In deployments the only public entrypoint is the backend (one ngrok tunnel),
so the Flutter panel cannot reach the per-user dev-server ports directly.
When MICROAPPS_PROXY_MODE is on, the panel loads
``/micro-apps/<app-path>?mp_token=<panel JWT>`` from the backend origin and
this router forwards everything — HTML, assets, the houses SSE stream and the
Vite HMR WebSocket — to the workspace's loopback dev server.

Auth: iframe/WebView subresource requests cannot carry Authorization headers,
so the entry request presents a short-lived panel token (minted alongside
WorkspaceStatus); the proxy exchanges it for an HttpOnly cookie scoped to
``/micro-apps``, and every subsequent request — including the WS upgrade — is
routed by that cookie: slug → deterministic dev port → 127.0.0.1.

Registered at the app root, before the SPA catch-all (see main.py).
"""

from __future__ import annotations

import asyncio
import contextlib
import logging

import httpx
from fastapi import APIRouter, HTTPException, Request, WebSocket
from fastapi.responses import Response, StreamingResponse
from starlette.background import BackgroundTask
from websockets.asyncio.client import ClientConnection
from websockets.asyncio.client import connect as ws_connect

from app.core.config import get_settings
from app.core.security import verify_microapps_panel_token
from app.services.microapp_workspace import manager

logger = logging.getLogger(__name__)

router = APIRouter()

COOKIE_NAME = "mp_panel"
TOKEN_QUERY_PARAM = "mp_token"

# RFC 2616 hop-by-hop headers, never forwarded in either direction.
_HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}

_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        # read=None: SSE streams (/micro-apps/__hmr) stay open indefinitely.
        _client = httpx.AsyncClient(
            timeout=httpx.Timeout(connect=10.0, read=None, write=None, pool=None)
        )
    return _client


def _resolve_slug(token: str | None) -> str | None:
    if not token:
        return None
    return verify_microapps_panel_token(token, get_settings())


def _require_proxy_enabled() -> None:
    if not (get_settings().microapps_proxy_mode and manager.enabled):
        raise HTTPException(status_code=404, detail="Not found")


@router.api_route(
    "/micro-apps/{path:path}",
    methods=["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    include_in_schema=False,
)
async def proxy_http(path: str, request: Request) -> Response:
    _require_proxy_enabled()

    query_token = request.query_params.get(TOKEN_QUERY_PARAM)
    slug = _resolve_slug(query_token or request.cookies.get(COOKIE_NAME))
    if slug is None:
        raise HTTPException(status_code=401, detail="Missing or invalid panel token")

    port = manager.dev_port_for(slug)
    params = [
        (k, v)
        for k, v in request.query_params.multi_items()
        if k != TOKEN_QUERY_PARAM
    ]
    url = httpx.URL(f"http://127.0.0.1:{port}/micro-apps/{path}", params=params)
    headers = {
        k: v
        for k, v in request.headers.items()
        if k.lower() not in _HOP_BY_HOP and k.lower() != "host"
    }
    content = (
        request.stream() if request.method in ("POST", "PUT", "PATCH") else None
    )
    client = _get_client()
    try:
        upstream = await client.send(
            client.build_request(request.method, url, headers=headers, content=content),
            stream=True,
        )
    except httpx.TransportError as exc:
        raise HTTPException(
            status_code=502,
            detail="Micro-apps dev server is not reachable — start the workspace first",
        ) from exc

    response = StreamingResponse(
        upstream.aiter_raw(),
        status_code=upstream.status_code,
        headers={
            k: v for k, v in upstream.headers.items() if k.lower() not in _HOP_BY_HOP
        },
        background=BackgroundTask(upstream.aclose),
    )
    if query_token:
        # Entry request: persist the token so asset/XHR/SSE/WS requests
        # (which can't carry it) keep routing to this workspace.
        secure = (
            request.url.scheme == "https"
            or request.headers.get("x-forwarded-proto") == "https"
        )
        response.set_cookie(
            COOKIE_NAME,
            query_token,
            path="/micro-apps",
            httponly=True,
            samesite="lax",
            secure=secure,
            max_age=12 * 3600,
        )
    return response


@router.websocket("/micro-apps/{path:path}")
async def proxy_websocket(websocket: WebSocket, path: str) -> None:
    """Bridge the Vite HMR WebSocket to the workspace dev server."""
    settings = get_settings()
    if not (settings.microapps_proxy_mode and manager.enabled):
        await websocket.close(code=4404)
        return

    slug = _resolve_slug(
        websocket.query_params.get(TOKEN_QUERY_PARAM)
        or websocket.cookies.get(COOKIE_NAME)
    )
    if slug is None:
        await websocket.close(code=4401)
        return

    port = manager.dev_port_for(slug)
    params = [
        (k, v)
        for k, v in websocket.query_params.multi_items()
        if k != TOKEN_QUERY_PARAM
    ]
    target = str(httpx.URL(f"ws://127.0.0.1:{port}/micro-apps/{path}", params=params))
    subprotocols = websocket.scope.get("subprotocols") or None

    try:
        async with ws_connect(
            target, subprotocols=subprotocols, max_size=None, open_timeout=10
        ) as upstream:
            await websocket.accept(subprotocol=upstream.subprotocol)
            client_task = asyncio.create_task(_pump_client(websocket, upstream))
            upstream_task = asyncio.create_task(_pump_upstream(websocket, upstream))
            _, pending = await asyncio.wait(
                {client_task, upstream_task}, return_when=asyncio.FIRST_COMPLETED
            )
            for task in pending:
                task.cancel()
    except Exception:  # noqa: BLE001 — upstream gone; close quietly
        logger.debug("microapps proxy: WS bridge for %s closed with error", slug)
    finally:
        with contextlib.suppress(Exception):
            await websocket.close()


async def _pump_client(websocket: WebSocket, upstream: ClientConnection) -> None:
    """Client → dev server until the client disconnects."""
    while True:
        message = await websocket.receive()
        if message["type"] == "websocket.disconnect":
            return
        data = message.get("text")
        if data is None:
            data = message.get("bytes")
        if data is not None:
            await upstream.send(data)


async def _pump_upstream(websocket: WebSocket, upstream: ClientConnection) -> None:
    """Dev server → client until the dev server closes."""
    async for message in upstream:
        if isinstance(message, str):
            await websocket.send_text(message)
        else:
            await websocket.send_bytes(message)
