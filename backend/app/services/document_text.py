"""Shared document byte readers and text classification, without persistence.

These readers preserve the legacy knowledge-base/client decoding contract.
Strict durable document reads add validation and isolation in document_extraction.
"""

import io

from openpyxl import load_workbook
from pypdf import PdfReader

# Handled directly by extract_text (bytes-based).
STRUCTURED_EXTENSIONS = frozenset({".pdf", ".csv", ".xlsx", ".xls", ".ods"})

# Rich formats with no bytes-native extractor here — routed through markitdown.
MARKITDOWN_EXTENSIONS = frozenset(
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


def _extract_pdf(data: bytes) -> str:
    reader = PdfReader(io.BytesIO(data))
    pages: list[str] = []
    for page in reader.pages:
        text = page.extract_text() or ""
        if text.strip():
            pages.append(text)
    return "\n\n".join(pages)


def _extract_csv(data: bytes) -> str:
    return data.decode("utf-8", errors="replace")


def _extract_spreadsheet(data: bytes) -> str:
    wb = load_workbook(filename=io.BytesIO(data), read_only=True, data_only=True)
    parts: list[str] = []
    for sheet_name in wb.sheetnames:
        sheet = wb[sheet_name]
        parts.append(f"## Sheet: {sheet_name}")
        for row in sheet.iter_rows(values_only=True):
            cells = [str(c) if c is not None else "" for c in row]
            parts.append(" | ".join(cells))
    return "\n".join(parts)


def _extract_plain(data: bytes) -> str:
    return data.decode("utf-8", errors="replace")


def looks_like_text(text: str, sample_size: int = 4000) -> bool:
    """Heuristic check that extracted content is human-readable text.

    Binary input decoded with errors="replace" is dominated by U+FFFD
    replacement characters and control bytes; readable text is not.
    """
    sample = text[:sample_size]
    if not sample:
        return False
    bad = sum(1 for ch in sample if ch == "�" or (ord(ch) < 32 and ch not in "\n\r\t"))
    return bad / len(sample) < 0.10


def extract_text(data: bytes, filename: str, mime_type: str) -> str:
    """Dispatch to the right extractor for ``mime_type`` / filename."""
    mime = (mime_type or "").lower()
    lower_name = filename.lower()

    if mime == "application/pdf" or lower_name.endswith(".pdf"):
        return _extract_pdf(data)
    if mime == "text/csv" or lower_name.endswith(".csv"):
        return _extract_csv(data)
    if mime in {
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "application/vnd.ms-excel",
        "application/vnd.oasis.opendocument.spreadsheet",
    } or lower_name.endswith((".xlsx", ".xls", ".ods")):
        return _extract_spreadsheet(data)
    return _extract_plain(data)
