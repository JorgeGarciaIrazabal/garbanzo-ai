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

from app.services.document_extraction import MAX_INPUT_BYTES, extract_document  # noqa: E402


def main() -> None:
    try:
        data = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
        if len(data) > MAX_INPUT_BYTES:
            raise ValueError("Document extraction failed: Document exceeds the input limit.")
        text = extract_document(sys.argv[1], data)
        result = {"ok": True, "text": text}
    except Exception as exc:
        result = {"ok": False, "error": str(exc)}
    sys.stdout.write(json.dumps(result))


if __name__ == "__main__":
    main()
