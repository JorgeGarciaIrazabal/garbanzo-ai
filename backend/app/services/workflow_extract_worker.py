"""Isolated document extraction entry point; no DB or provider calls."""

import json
import os
import resource
import sys

# Set limits before importing the document parser stack.
resource.setrlimit(resource.RLIMIT_AS, (1024 * 1024 * 1024, 1024 * 1024 * 1024))
resource.setrlimit(resource.RLIMIT_CPU, (10, 10))
for thread_setting in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ[thread_setting] = "1"

from app.schemas.workflow import MAX_FILE_BYTES  # noqa: E402
from app.services.workflow_outputs import extract_output  # noqa: E402


def main() -> None:
    try:
        data = sys.stdin.buffer.read(MAX_FILE_BYTES + 1)
        if len(data) > MAX_FILE_BYTES:
            raise ValueError("Document exceeds the input limit.")
        text = extract_output(sys.argv[1], data)
        result = {"ok": True, "text": text}
    except Exception as exc:
        result = {"ok": False, "error": f"Document extraction failed: {exc}"}
    sys.stdout.write(json.dumps(result))


if __name__ == "__main__":
    main()
