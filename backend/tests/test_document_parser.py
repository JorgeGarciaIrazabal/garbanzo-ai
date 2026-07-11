"""Unit tests for app.services.document_parser.extract_attachment_text."""

import base64

import pytest

from app.schemas.chat import AttachmentIn
from app.services.document_parser import extract_attachment_text

pytestmark = pytest.mark.asyncio


def _attachment(*, name: str, mime_type: str, raw: bytes) -> AttachmentIn:
    return AttachmentIn(
        name=name,
        mime_type=mime_type,
        type="document",
        data=base64.b64encode(raw).decode("ascii"),
    )


# ============================================================================
# Plain text
# ============================================================================


async def test_plain_text_mime_type_is_decoded():
    att = _attachment(name="notes.txt", mime_type="text/plain", raw=b"hello world")
    result = await extract_attachment_text(att)
    assert result == "hello world"


async def test_plain_text_by_extension_when_mime_type_is_generic():
    # Browsers often send application/octet-stream (or omit type) for source
    # files; the filename extension should still route to plain-text decode.
    att = _attachment(name="script.py", mime_type="application/octet-stream", raw=b"print('hi')")
    result = await extract_attachment_text(att)
    assert result == "print('hi')"


async def test_plain_text_decodes_utf8_with_replacement_on_bad_bytes():
    att = _attachment(name="notes.md", mime_type="text/markdown", raw=b"\xff\xfehello")
    result = await extract_attachment_text(att)
    assert "hello" in result


# ============================================================================
# CSV truncation behavior
# ============================================================================


async def test_csv_under_50_rows_is_included_in_full():
    rows = "\n".join(f"row{i},value{i}" for i in range(10))
    att = _attachment(name="data.csv", mime_type="text/csv", raw=rows.encode())
    result = await extract_attachment_text(att)
    assert "[CSV: data.csv, 10 rows]" in result
    assert "row9,value9" in result
    assert "Preview" not in result


async def test_csv_over_50_rows_is_truncated_to_preview():
    rows = "\n".join(f"row{i},value{i}" for i in range(75))
    att = _attachment(name="big.csv", mime_type="text/csv", raw=rows.encode())
    result = await extract_attachment_text(att)
    assert "[CSV: big.csv, 75 rows]" in result
    assert "--- Preview (first 50 rows) ---" in result
    assert "row49,value49" in result
    # Row 50 (index 50, the 51st row) is beyond the preview window.
    assert "row50,value50" not in result
    assert "... and 25 more rows" in result


# ============================================================================
# Corrupt / invalid base64
# ============================================================================


async def test_corrupt_base64_falls_back_to_raw_data_for_csv():
    att = AttachmentIn(
        name="broken.csv",
        mime_type="text/csv",
        type="document",
        data="not-valid-base64!!!",
    )
    result = await extract_attachment_text(att)
    # No exception propagates; the raw (undecoded) data is returned as-is.
    assert result == "not-valid-base64!!!"


async def test_corrupt_base64_falls_back_to_raw_data_for_plain_text():
    att = AttachmentIn(
        name="broken.txt",
        mime_type="text/plain",
        type="document",
        data="%%%not-base64%%%",
    )
    result = await extract_attachment_text(att)
    assert result == "%%%not-base64%%%"


async def test_corrupt_base64_pdf_returns_inline_error_marker():
    # PDF extraction catches its own errors and embeds a descriptive marker
    # rather than raising or silently falling back.
    att = AttachmentIn(
        name="broken.pdf",
        mime_type="application/pdf",
        type="document",
        data="not-valid-base64!!!",
    )
    result = await extract_attachment_text(att)
    assert result.startswith("[PDF extraction error:")


# ============================================================================
# Unknown mime type
# ============================================================================


async def test_unknown_mime_type_returns_raw_data_unchanged():
    att = AttachmentIn(
        name="mystery.bin",
        mime_type="application/x-mystery-format",
        type="document",
        data="c29tZSBiaW5hcnkgZGF0YQ==",
    )
    result = await extract_attachment_text(att)
    # Unknown mime + non-matching extension: the raw (still base64) string is
    # returned untouched rather than guessed at.
    assert result == "c29tZSBiaW5hcnkgZGF0YQ=="
