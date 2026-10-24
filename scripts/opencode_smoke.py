"""Real pinned OpenCode V2 smoke against a local OpenAI-compatible fake model.

Run with just opencode-smoke; no provider credentials or external model calls.
"""

from __future__ import annotations

import asyncio
import json
import os
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace

import httpx

from app.core.config import Settings
from app.services.microapp_agent import MicroappAgent
from app.services.opencode_config import build_config, write_config
from app.services.opencode_process import OPENCODE_AUTH, default_spawn, pick_free_port, terminate, wait_ready


class Model(BaseHTTPRequestHandler):
    calls = 0
    blocked = threading.Event()
    release = threading.Event()

    def log_message(self, *_args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        type(self).calls += 1
        if "Hold for interruption" in str(body["messages"]):
            self.blocked.set()
            self.release.wait(timeout=20)
            return
        tool_done = any(m["role"] == "tool" for m in body["messages"])
        delta = {"content": "V2 smoke complete"} if tool_done else {
            "tool_calls": [{"index": 0, "id": "call_smoke", "type": "function", "function": {
                "name": "execute", "arguments": json.dumps({"code": "return 'V2 tool result'"})}}],
        }
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for item in [
            {"id": "fake", "object": "chat.completion.chunk", "model": "fake", "created": 1,
             "choices": [{"index": 0, "delta": delta, "finish_reason": None}]},
            {"id": "fake", "object": "chat.completion.chunk", "model": "fake", "created": 1,
             "choices": [{"index": 0, "delta": {}, "finish_reason": "stop" if tool_done else "tool_calls"}]},
        ]:
            self.wfile.write(f"data: {json.dumps(item)}\n\n".encode())
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


async def smoke():
    model = ThreadingHTTPServer(("127.0.0.1", 0), Model)
    thread = threading.Thread(target=model.serve_forever, daemon=True)
    thread.start()
    proc = None
    try:
        with tempfile.TemporaryDirectory(prefix="garbanzo-opencode-smoke-") as directory:
            root = Path(directory)
            workdir = root / "project"
            workdir.mkdir()
            settings = Settings(_env_file=None, ollama_base_url=f"http://127.0.0.1:{model.server_port}", microapps_opencode_model="ollama/fake")
            config = build_config(settings)
            config["permissions"].insert(0, {"action": "*", "resource": "*", "effect": "allow"})
            write_config(workdir, config)
            base = f"http://127.0.0.1:{pick_free_port()}"
            env = {**os.environ, "OPENCODE_CONFIG_PROJECT_DISABLE": "false", "OPENCODE_DISABLE_MODELS_FETCH": "true"}
            for name in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
                env[name] = str(root / name.lower())
            # Global instructions/credentials must not influence this isolated probe.
            env.pop("OPENCODE_CONFIG", None)
            env.pop("OPENCODE_CONFIG_CONTENT", None)
            proc = default_spawn([settings.microapps_opencode_bin, "serve", "--hostname", "127.0.0.1", "--port", base.rsplit(":", 1)[1]], str(workdir), env)
            assert await asyncio.to_thread(wait_ready, base, proc), "V2 server did not become ready"
            endpoint = SimpleNamespace(opencode_base=base, opencode_ready=True)
            async with asyncio.timeout(90):
                chunks = [c async for c in MicroappAgent(settings).stream_instruction(endpoint, "Run the execute tool once and report the result.")]
            errors = [c.error for c in chunks if c.type == "error"]
            assert not errors, errors
            assert "".join(c.content or "" for c in chunks if c.type == "chunk") == "V2 smoke complete"
            assert any(c.type == "tool_call" for c in chunks), [c.type for c in chunks]
            assert any(c.type == "tool_result" and not c.tool_result["is_error"] for c in chunks)
            assert chunks[-1].type == "done"
            sid = chunks[0].metadata["session_id"]
            assert await MicroappAgent(settings).abort(endpoint, sid), "Idle interrupt request failed"
            interrupted_chunks = []
            async def interrupted_turn():
                async for chunk in MicroappAgent(settings).stream_instruction(endpoint, "Hold for interruption"):
                    interrupted_chunks.append(chunk)
            running = asyncio.create_task(interrupted_turn())
            assert await asyncio.to_thread(Model.blocked.wait, 10), "Second prompt did not start"
            active_sid = interrupted_chunks[0].metadata["session_id"]
            async with httpx.AsyncClient(base_url=base, auth=OPENCODE_AUTH) as client:
                response = await client.get("/api/session/active")
                response.raise_for_status()
                assert active_sid in response.json()["data"], "Second session was not active"
            assert await MicroappAgent(settings).abort(endpoint, active_sid)
            async with asyncio.timeout(10):
                await running
            assert any(c.type == "error" and "interrupted" in c.error for c in interrupted_chunks)
            Model.release.set()
            print(f"OpenCode V2 real-server smoke passed: {len(chunks)} chunks, {Model.calls} model requests, text/tool/completion/interrupt.")
    finally:
        Model.release.set()
        terminate(proc)
        model.shutdown()
        model.server_close()


if __name__ == "__main__":
    asyncio.run(smoke())
