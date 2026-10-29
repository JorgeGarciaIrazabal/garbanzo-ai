"""Strict document extraction shared by durable folders and workflow outputs."""

import io
import json
import subprocess
import sys
import zipfile
from pathlib import Path

from markitdown import StreamInfo
from markitdown.converters import DocxConverter, EpubConverter, HtmlConverter, PptxConverter

from app.file_limits import MAX_FILE_BYTES
from app.services.document_text import (
    MARKITDOWN_EXTENSIONS,
    STRUCTURED_EXTENSIONS,
    TEXT_EXTENSIONS,
    extract_text,
    looks_like_text,
)

# Parser budgets are independent of workflow storage and folder quotas.
MAX_INPUT_BYTES = MAX_FILE_BYTES
MAX_EXPANDED_BYTES = 250 * 1024 * 1024
MAX_ARCHIVE_ENTRIES = 10000
MAX_TEXT_CHARS = 25 * 1024 * 1024
EXTRACTION_TIMEOUT_SECONDS = 60


class DocumentExtractionError(Exception):
    """A document cannot be represented safely as extracted text."""


def extract_document(path: str, data: bytes) -> str:
    """Extract filename + bytes strictly; rich formats use extract_isolated in callers."""
    try:
        return _extract_document(path, data)
    except DocumentExtractionError:
        raise
    except Exception as exc:
        raise DocumentExtractionError(f"Document extraction failed: {exc}") from exc


def _extract_document(path: str, data: bytes) -> str:
    """Strict extraction: unsupported/corrupt/oversized content is an error, never text."""
    if len(data) > MAX_INPUT_BYTES:
        raise DocumentExtractionError("Document exceeds the input limit.")
    suffix = Path(path).suffix.lower()
    if suffix in {".xlsx", ".xlsm", ".ods", ".docx", ".pptx", ".epub"}:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            if (
                len(archive.infolist()) > MAX_ARCHIVE_ENTRIES
                or sum(entry.file_size for entry in archive.infolist()) > MAX_EXPANDED_BYTES
            ):
                raise DocumentExtractionError(
                    "Document exceeds the expanded extraction limits; download it instead."
                )
    if suffix in STRUCTURED_EXTENSIONS and suffix != ".csv":
        text = extract_text(data, path, "")
    elif suffix in MARKITDOWN_EXTENSIONS:
        text = _strict_markdown(path, data)
    else:
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise DocumentExtractionError(
                "This file has no supported text representation; download it instead."
            ) from exc
        if suffix not in TEXT_EXTENSIONS and text and not looks_like_text(text):
            raise DocumentExtractionError(
                "This file has no supported text representation; download it instead."
            )
    if len(text) > MAX_TEXT_CHARS:
        raise DocumentExtractionError(
            "Extracted document exceeds the text limit; download it instead."
        )
    return text


def _strict_markdown(path: str, data: bytes) -> str:
    # The extension is already known. Calling MarkItDown() would initialize
    # Magika's ONNX detector and its thread pool inside the worker's memory cap.
    # Direct public converters avoid that unrelated model dependency.
    suffix = Path(path).suffix.lower()
    converters = {
        ".docx": DocxConverter,
        ".pptx": PptxConverter,
        ".epub": EpubConverter,
        ".html": HtmlConverter,
        ".htm": HtmlConverter,
    }
    converter = converters.get(suffix)
    if converter is None:
        raise DocumentExtractionError(f"No supported document parser for {suffix} files.")
    return (
        converter()
        .convert(io.BytesIO(data), StreamInfo(extension=suffix), strict=True)
        .text_content
    )


def extract_isolated(path: str, data: bytes) -> str:
    """Document parsers run with memory/CPU/time limits outside the API process."""
    suffix = Path(path).suffix.lower()
    if suffix not in STRUCTURED_EXTENSIONS | MARKITDOWN_EXTENSIONS or suffix == ".csv":
        return extract_document(path, data)
    try:
        proc = subprocess.run(  # noqa: S603
            [sys.executable, "-m", "app.services.document_extract_worker", path],
            input=data,
            capture_output=True,
            timeout=EXTRACTION_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise DocumentExtractionError(
            "Document extraction timed out; download it instead."
        ) from exc
    except OSError as exc:
        raise DocumentExtractionError(f"Document extraction failed: {exc}") from exc
    if proc.returncode != 0:
        raise DocumentExtractionError(
            "Document extraction failed or exceeded resource limits; download it instead."
        )
    try:
        result = json.loads(proc.stdout)
        if result["ok"] is False:
            raise DocumentExtractionError(result["error"])
        if result["ok"] is not True or not isinstance(result["text"], str):
            raise ValueError("Invalid document worker response.")
        return result["text"]
    except (ValueError, KeyError, TypeError) as exc:
        raise DocumentExtractionError(f"Document extraction failed: {exc}") from exc
