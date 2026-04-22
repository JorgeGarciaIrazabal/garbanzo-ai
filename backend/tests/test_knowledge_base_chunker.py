"""Pure unit tests for KB text extraction and chunking (no DB)."""

import io

from openpyxl import Workbook
from pypdf import PdfWriter

from app.services.knowledge_base_service import chunk_text, extract_text


def test_chunk_text_splits_long_input():
    text = "abcdefghij" * 100  # 1000 chars
    chunks = chunk_text(text, chunk_size=200, overlap=20)
    assert len(chunks) >= 5
    # Every chunk respects size roughly (allow small slack for boundary search).
    assert all(len(c) <= 220 for c in chunks)


def test_chunk_text_preserves_full_content_with_overlap():
    text = "First sentence. Second sentence. Third sentence. Fourth sentence. " \
           "Fifth sentence. Sixth sentence."
    chunks = chunk_text(text, chunk_size=40, overlap=10)
    # Concatenating chunks (minus overlap) should cover every substring of the
    # original text at least once.
    joined = " ".join(chunks)
    for word in ("First", "Second", "Third", "Fourth", "Fifth", "Sixth"):
        assert word in joined


def test_chunk_text_empty_input_returns_empty_list():
    assert chunk_text("", chunk_size=100, overlap=10) == []
    assert chunk_text("   \n  ", chunk_size=100, overlap=10) == []


def test_chunk_text_single_short_input_is_one_chunk():
    chunks = chunk_text("short input", chunk_size=100, overlap=10)
    assert chunks == ["short input"]


def test_chunk_text_prefers_paragraph_boundary():
    text = ("Paragraph one has some content to fill the chunk window. "
            "\n\n"
            "Paragraph two starts here and is separate from paragraph one.")
    chunks = chunk_text(text, chunk_size=70, overlap=10)
    assert len(chunks) >= 2
    # First chunk should end at the paragraph boundary (no leak into paragraph 2).
    assert "Paragraph two" not in chunks[0]


def test_extract_text_from_plain():
    data = b"Hello, world!\nSecond line."
    assert extract_text(data, "notes.txt", "text/plain") == "Hello, world!\nSecond line."


def test_extract_text_from_csv():
    data = b"col1,col2\nfoo,bar\nbaz,qux\n"
    out = extract_text(data, "data.csv", "text/csv")
    assert "col1,col2" in out
    assert "foo,bar" in out


def test_extract_text_from_xlsx():
    wb = Workbook()
    ws = wb.active
    ws.title = "Sheet1"
    ws.append(["name", "age"])
    ws.append(["Alice", 30])
    ws.append(["Bob", 25])
    buf = io.BytesIO()
    wb.save(buf)

    out = extract_text(
        buf.getvalue(),
        "people.xlsx",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )
    assert "Sheet1" in out
    assert "Alice" in out
    assert "Bob" in out


def test_extract_text_from_pdf_no_text_pages():
    writer = PdfWriter()
    writer.add_blank_page(width=72, height=72)
    buf = io.BytesIO()
    writer.write(buf)

    # Blank PDF → empty extracted text (chunker caller validates non-empty).
    out = extract_text(buf.getvalue(), "blank.pdf", "application/pdf")
    assert out == ""


def test_extract_text_dispatches_by_extension_when_mime_missing():
    data = b"col1,col2\n1,2\n"
    out = extract_text(data, "data.csv", "")
    assert "col1,col2" in out


def test_extract_text_unknown_falls_back_to_plain():
    data = b"random text"
    out = extract_text(data, "notes.wtf", "application/x-unknown")
    assert out == "random text"


def test_chunk_text_handles_overlap_larger_than_chunk_size():
    """Overlap >= chunk_size must be clamped so we still make progress."""
    text = "x" * 500
    chunks = chunk_text(text, chunk_size=50, overlap=200)
    assert len(chunks) >= 2
    assert chunks[0] == "x" * 50
