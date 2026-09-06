"""Small synchronous client for the Codex app-server JSONL protocol."""

from __future__ import annotations

import json
import subprocess
import threading
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from typing import Any, TextIO


class AppServerError(RuntimeError):
    """The app server exited, timed out, or returned a JSON-RPC error."""


@dataclass(frozen=True)
class RpcResponse:
    result: dict[str, Any]


class AppServerClient:
    """A bounded stdio client which ignores notifications while awaiting a response."""

    def __init__(
        self,
        command: Sequence[str] = ("codex", "app-server", "--stdio"),
        *,
        timeout: float = 15.0,
        process: subprocess.Popen[str] | None = None,
    ) -> None:
        self.timeout = timeout
        self._process = process or subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self._next_id = 1
        self._initialized = False

    def __enter__(self) -> AppServerClient:
        self.initialize()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def close(self) -> None:
        if self._process.poll() is None:
            self._process.terminate()
            try:
                self._process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self._process.kill()
                self._process.wait(timeout=2)

    def initialize(self) -> dict[str, Any]:
        if self._initialized:
            return {}
        result = self.request(
            "initialize",
            {
                "clientInfo": {"name": "garbanzo-ai", "title": "Garbanzo AI", "version": "1"},
                "capabilities": {"experimentalApi": True},
            },
        )
        self.notify("initialized")
        self._initialized = True
        return result

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        message: dict[str, Any] = {"method": method}
        if params is not None:
            message["params"] = params
        self._write(message)

    def request(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        request_id = self._next_id
        self._next_id += 1
        message: dict[str, Any] = {"id": request_id, "method": method}
        if params is not None:
            message["params"] = params
        self._write(message)
        response = self._read_for_id(request_id)
        if "error" in response:
            error = response["error"]
            raise AppServerError(f"{method}: {error}")
        result = response.get("result")
        if not isinstance(result, dict):
            raise AppServerError(f"{method}: response result was not an object")
        return result

    def _write(self, message: dict[str, Any]) -> None:
        stream = self._process.stdin
        if stream is None or self._process.poll() is not None:
            raise AppServerError("Codex app-server is not running")
        stream.write(json.dumps(message, separators=(",", ":")) + "\n")
        stream.flush()

    def _read_for_id(self, request_id: int) -> dict[str, Any]:
        stream = self._process.stdout
        if stream is None:
            raise AppServerError("Codex app-server stdout is unavailable")
        while True:
            line = _readline_with_timeout(stream, self.timeout)
            if not line:
                detail = ""
                if self._process.poll() is not None and self._process.stderr is not None:
                    detail = self._process.stderr.read().strip()
                raise AppServerError(detail or "Codex app-server closed its output")
            try:
                message = json.loads(line)
            except json.JSONDecodeError as exc:
                raise AppServerError("Codex app-server returned invalid JSON") from exc
            if isinstance(message, dict) and message.get("id") == request_id:
                return message


def _readline_with_timeout(stream: TextIO, timeout: float) -> str:
    value: list[str] = []
    error: list[BaseException] = []

    def read() -> None:
        try:
            value.append(stream.readline())
        except BaseException as exc:  # pragma: no cover - defensive boundary
            error.append(exc)

    thread = threading.Thread(target=read, daemon=True)
    thread.start()
    thread.join(timeout)
    if thread.is_alive():
        raise AppServerError(f"Codex app-server did not respond within {timeout:g}s")
    if error:
        raise AppServerError("Could not read Codex app-server output") from error[0]
    return value[0]


def paginated(
    client: AppServerClient, method: str, params: dict[str, Any] | None = None
) -> Iterator[dict[str, Any]]:
    request = dict(params or {})
    while True:
        page = client.request(method, request)
        data = page.get("data")
        if not isinstance(data, list):
            raise AppServerError(f"{method}: data was not an array")
        yield page
        cursor = page.get("nextCursor")
        if not cursor:
            return
        request["cursor"] = cursor
