"""Subprocess lifecycle helpers shared by every opencode we spawn.

Extracted from ``microapp_workspace`` (originally ported from the
battle-tested ``garbanzo-books/ui/opencode_client.py``) so delegated workflow
runs get the same guarantee: the children never outlive this process.
"""

from __future__ import annotations

import contextlib
import ctypes
import ctypes.util
import os
import random
import secrets
import signal
import socket
import subprocess
import time

import httpx

# opencode readiness poll: 240 × 0.25s ≈ 60s (first launch may load a model).
OPENCODE_VERSION = "2.1.4"
# Private loopback servers share a fresh credential for this backend lifetime.
OPENCODE_AUTH = ("opencode", secrets.token_urlsafe(32))

OPENCODE_READY_RETRIES = 240
OPENCODE_READY_INTERVAL = 0.25


class PortAllocationError(RuntimeError):
    """No free local port could be found for an opencode server."""


def child_preexec() -> None:
    """After fork / before exec in a child: own session + die-with-parent.

    - ``os.setsid()``: new session/group so we can kill the whole group.
    - ``PR_SET_PDEATHSIG=SIGKILL``: the kernel kills the child the instant this
      process dies for ANY reason — the real guarantee against orphans.
    """
    os.setsid()
    try:
        libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
        libc.prctl(1, signal.SIGKILL)  # PR_SET_PDEATHSIG = 1
    except Exception:  # noqa: BLE001 — non-Linux: fall back to explicit kills
        pass


def default_spawn(cmd: list[str], cwd: str, env: dict[str, str]) -> subprocess.Popen:
    """Spawn a detached child that dies with us. Injectable for tests."""
    if len(cmd) > 1 and cmd[1] == "serve":
        result = subprocess.run(  # noqa: S603
            [cmd[0], "--version"], capture_output=True, text=True, check=True, timeout=15
        )
        if result.stdout.strip().removeprefix("opencode ").removeprefix("v") != OPENCODE_VERSION:
            raise RuntimeError(
                f"OpenCode {OPENCODE_VERSION} is required; run just opencode-install "
                f"(found {result.stdout.strip()!r})"
            )
        env = {
            **env,
            "OPENCODE_PASSWORD": OPENCODE_AUTH[1],
            "OPENCODE_SERVER_PASSWORD": OPENCODE_AUTH[1],
        }
    return subprocess.Popen(  # noqa: S603
        cmd,
        cwd=cwd,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=child_preexec,
    )


def pick_free_port() -> int:
    """Random port in the opencode band, bind-tested so a collision with
    another process (or another user's opencode) retries instead of handing
    out a port that fails at spawn time."""
    for _ in range(20):
        port = random.randint(40000, 60000)  # noqa: S311 — not security-sensitive
        with socket.socket() as s:
            try:
                s.bind(("127.0.0.1", port))
            except OSError:
                continue
        return port
    raise PortAllocationError("Could not find a free local port for opencode")


def wait_ready(base: str, proc: subprocess.Popen) -> bool:
    """Poll the authenticated V2 ``/api/info`` until ready. Injectable-friendly (sync)."""
    for _ in range(OPENCODE_READY_RETRIES):
        if proc.poll() is not None:
            return False
        try:
            response = httpx.get(base + "/api/info", auth=OPENCODE_AUTH, timeout=2.0)
            response.raise_for_status()
            version = response.json()["version"]
            if version != OPENCODE_VERSION:
                raise RuntimeError(
                    f"Incompatible OpenCode server {version!r}; expected {OPENCODE_VERSION}"
                )
            return True
        except (httpx.HTTPError, ValueError, KeyError):  # not up yet
            time.sleep(OPENCODE_READY_INTERVAL)
    return False


def terminate(proc: subprocess.Popen | None) -> None:
    """Kill an opencode process group, escalating to SIGKILL."""
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        with contextlib.suppress(Exception):
            proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            with contextlib.suppress(Exception):
                proc.kill()
