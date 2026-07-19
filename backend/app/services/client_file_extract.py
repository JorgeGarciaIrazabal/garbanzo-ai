"""Extract text from a client-uploaded file's bytes (idea 17: folder reads).

For the "include a folder" feature the attached folder lives *only* on the
desktop client. When the model calls ``read_file``, the client reads the file
locally and sends its raw bytes to the backend; this module turns those bytes
into text. The backend never reads the host filesystem — it only processes an
upload, exactly like a chat attachment.

Reuses the knowledge-base extractors (PDF/CSV/spreadsheet/plain) and falls back
to markitdown for Office/HTML formats (DOCX/PPTX/HTML/…).
"""

from __future__ import annotations

import tempfile
from pathlib import Path

from app.services.knowledge_base_service import _looks_like_text, extract_text

# Files larger than this are refused rather than slurped into the model context.
MAX_FILE_BYTES = 5 * 1024 * 1024

# Handled directly by knowledge_base_service.extract_text (bytes-based).
_STRUCTURED_EXTENSIONS = frozenset({".pdf", ".csv", ".xlsx", ".xls", ".ods"})

# Rich formats with no bytes-native extractor here — routed through markitdown.
_MARKITDOWN_EXTENSIONS = frozenset(
    {".docx", ".pptx", ".doc", ".ppt", ".epub", ".rtf", ".htm", ".html"}
)

# Curated plain-text / source-code extensions decoded directly as UTF-8.
TEXT_EXTENSIONS = frozenset(
    {
        ".txt",
        ".md",
        ".markdown",
        ".rst",
        ".log",
        ".json",
        ".jsonl",
        ".yaml",
        ".yml",
        ".toml",
        ".ini",
        ".cfg",
        ".conf",
        ".env",
        ".xml",
        ".css",
        ".scss",
        ".tsv",
        ".py",
        ".js",
        ".ts",
        ".tsx",
        ".jsx",
        ".dart",
        ".java",
        ".kt",
        ".go",
        ".rs",
        ".rb",
        ".php",
        ".c",
        ".h",
        ".cpp",
        ".hpp",
        ".cs",
        ".swift",
        ".scala",
        ".sh",
        ".bash",
        ".zsh",
        ".sql",
        ".gradle",
        ".properties",
    }
)


def _extract_with_markitdown(filename: str, data: bytes) -> str | None:
    """Convert ``data`` to markdown via markitdown, or ``None`` on failure.

    markitdown dispatches on the file extension, so the bytes are written to a
    short-lived server temp file (never the client's path) to preserve it.
    """
    try:
        from markitdown import MarkItDown

        suffix = Path(filename).suffix or ".bin"
        with tempfile.NamedTemporaryFile(suffix=suffix) as tmp:
            tmp.write(data)
            tmp.flush()
            return MarkItDown().convert(tmp.name).text_content
    except Exception:
        return None


def extract_file_text(filename: str, data: bytes) -> str:
    """Turn client-provided file ``data`` into text, choosing the best extractor.

    Returns a human-readable message (not a raise) for oversized or unreadable
    files so the model gets useful feedback in the tool result.
    """
    if len(data) > MAX_FILE_BYTES:
        return (
            f"File '{filename}' is too large to read "
            f"({len(data) // 1024} KB > {MAX_FILE_BYTES // 1024} KB limit)."
        )

    suffix = Path(filename).suffix.lower()

    if suffix in _STRUCTURED_EXTENSIONS:
        return extract_text(data, filename, "")

    if suffix in _MARKITDOWN_EXTENSIONS:
        text = _extract_with_markitdown(filename, data)
        if text is not None:
            return text

    if suffix in TEXT_EXTENSIONS or suffix == "":
        return data.decode("utf-8", errors="replace")

    # Unknown extension: try markitdown, then a mojibake-guarded plain read.
    text = _extract_with_markitdown(filename, data)
    if text is not None:
        return text
    decoded = data.decode("utf-8", errors="replace")
    if _looks_like_text(decoded):
        return decoded
    return f"File '{filename}' does not appear to be readable text."
