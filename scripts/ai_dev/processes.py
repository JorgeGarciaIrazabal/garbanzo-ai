"""Bounded cancellation of an owned subprocess and its descendant processes."""

import contextlib
import os
import signal
import subprocess
from pathlib import Path


def stop_tree(process: subprocess.Popen) -> None:
    """Freeze before walking descendants so a cancelled controller cannot spawn more."""
    if process.poll() is not None:
        return
    descendants = []

    def freeze(pid):
        try:
            os.kill(pid, signal.SIGSTOP)
            children = Path(f"/proc/{pid}/task/{pid}/children").read_text().split()
        except (ProcessLookupError, FileNotFoundError):
            return
        descendants.append(pid)
        for child in children:
            freeze(int(child))

    freeze(process.pid)
    for pid in reversed(descendants):
        with contextlib.suppress(ProcessLookupError):
            os.kill(pid, signal.SIGKILL)
    process.wait(timeout=10)
