"""Strict extraction limits and failures stay independent of caller persistence."""

import io
import json
import subprocess
import sys
import zipfile
from unittest.mock import Mock

import pytest
from docx import Document
from openpyxl import Workbook

from app.services import document_extraction
from app.services.client_file_extract import extract_file_text
from app.services.document_extraction import (
    DocumentExtractionError,
    extract_document,
    extract_isolated,
)
from app.services.document_text import extract_text


def _archive(entries):
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, text in entries:
            archive.writestr(name, text)
    return data.getvalue()


def test_xlsm_isolated_extraction_and_mime_dispatch():
    workbook = Workbook()
    workbook.active.title = "Annual consumption"
    workbook.active.append(["Energy", 125])
    workbook.active.append(["Formula", "=1+1"])
    original = io.BytesIO()
    workbook.save(original)
    workbook.close()
    # Give the synthetic workbook the actual macro-enabled workbook content
    # type, with an inert VBA entry that must never become extracted text.
    output = io.BytesIO()
    with zipfile.ZipFile(original) as source, zipfile.ZipFile(output, "w") as target:
        for name in source.namelist():
            value = source.read(name)
            if name == "[Content_Types].xml":
                value = value.replace(
                    b"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
                    b"application/vnd.ms-excel.sheet.macroEnabled.main+xml",
                )
            target.writestr(name, value)
        target.writestr("xl/vbaProject.bin", b"inert-macro-sentinel")

    data = output.getvalue()
    isolated = extract_isolated("annual.xlsm", data)
    by_mime = extract_text(data, "annual.bin", "application/vnd.ms-excel.sheet.macroEnabled.12")

    assert isolated == by_mime
    assert "## Sheet: Annual consumption" in isolated
    assert "Energy | 125" in isolated
    assert "=1+1" not in isolated
    assert "inert-macro-sentinel" not in isolated


def test_docx_isolated_conversion_uses_known_format_without_detection():
    document = Document()
    document.add_heading("Energy summary", 1)
    document.add_paragraph("Annual consumption is available.")
    buffer = io.BytesIO()
    document.save(buffer)
    text = extract_isolated("summary.docx", buffer.getvalue())
    assert "Energy summary" in text
    assert "Annual consumption is available." in text


@pytest.mark.parametrize("filename", ["report.docx", "report.xlsm"])
def test_archive_entry_limit_is_explicit(monkeypatch, filename):
    monkeypatch.setattr(document_extraction, "MAX_ARCHIVE_ENTRIES", 1)
    payload = _archive([("one.xml", "one"), ("two.xml", "two")])
    with pytest.raises(DocumentExtractionError, match="expanded extraction limits"):
        extract_document(filename, payload)


def test_malformed_archive_is_an_error():
    with pytest.raises(DocumentExtractionError, match="Document extraction failed"):
        extract_document("report.xlsx", b"not a zip archive")


def test_text_limit_is_explicit(monkeypatch):
    monkeypatch.setattr(document_extraction, "MAX_TEXT_CHARS", 4)
    with pytest.raises(DocumentExtractionError, match="text limit"):
        extract_isolated("notes.txt", b"12345")


def test_utf8_and_csv_reads_do_not_launch_a_parser_process(monkeypatch):
    run = Mock(side_effect=AssertionError("Text must not launch a parser process"))
    monkeypatch.setattr(document_extraction.subprocess, "run", run)
    assert extract_isolated("notes.txt", "España 🌱".encode()) == "España 🌱"
    assert extract_isolated("rows.csv", b"name,value\na,1\n") == "name,value\na,1\n"
    with pytest.raises(DocumentExtractionError, match="no supported text representation"):
        extract_isolated("rows.csv", b"\xff")


@pytest.mark.parametrize(
    ("failure", "message"),
    [
        (subprocess.TimeoutExpired("parser", 20), "timed out"),
        (OSError("cannot start parser"), "cannot start parser"),
    ],
)
def test_parser_launch_failures_are_explicit(monkeypatch, failure, message):
    monkeypatch.setattr(document_extraction.subprocess, "run", Mock(side_effect=failure))
    with pytest.raises(DocumentExtractionError, match=message):
        extract_isolated("report.pdf", b"pdf bytes")


@pytest.mark.parametrize("returncode", [1, -9, -24])
def test_parser_crash_or_resource_failure_is_explicit(monkeypatch, returncode):
    response = subprocess.CompletedProcess([], returncode, stdout=b"", stderr=b"")
    monkeypatch.setattr(document_extraction.subprocess, "run", Mock(return_value=response))
    with pytest.raises(DocumentExtractionError, match="failed or exceeded resource limits"):
        extract_isolated("report.pdf", b"pdf bytes")


@pytest.mark.parametrize("response", [b"not json", b"{}", b'{"ok": true, "text": 12}'])
def test_invalid_worker_response_is_an_explicit_document_error(monkeypatch, response):
    proc = subprocess.CompletedProcess([], 0, stdout=response, stderr=b"")
    monkeypatch.setattr(document_extraction.subprocess, "run", Mock(return_value=proc))
    with pytest.raises(DocumentExtractionError, match="Document extraction failed"):
        extract_isolated("report.pdf", b"pdf bytes")


def test_worker_input_limit_is_explicit():
    # Run the real worker so its bounded stdin read is exercised before parsing.
    with pytest.raises(DocumentExtractionError, match="input limit"):
        extract_isolated("report.pdf", b"x" * (document_extraction.MAX_INPUT_BYTES + 1))


def test_worker_only_loads_document_services_and_enforces_limits():
    # Inspect only the child process; importing this worker in pytest would limit pytest itself.
    proc = subprocess.run(  # noqa: S603
        [
            sys.executable,
            "-c",
            "import app.services.document_extract_worker; import json, resource, sys; "
            "print(json.dumps({'limits': [resource.getrlimit(resource.RLIMIT_AS), "
            "resource.getrlimit(resource.RLIMIT_CPU)], "
            "'services': sorted(n for n in sys.modules if n.startswith('app.services.')), "
            "'state': sorted(n for n in sys.modules if n.startswith("
            "('app.db', 'app.models', 'app.core', 'app.schemas')))}))",
        ],
        capture_output=True,
        timeout=20,
        check=True,
    )
    result = json.loads(proc.stdout)
    assert result["limits"] == [[1024 * 1024 * 1024] * 2, [30, 30]]
    assert result["services"] == [
        "app.services.document_extract_worker",
        "app.services.document_extraction",
        "app.services.document_text",
    ]
    assert result["state"] == []


def test_client_known_format_conversion_failure_is_explicit(monkeypatch):
    monkeypatch.setattr(
        document_extraction.HtmlConverter,
        "convert",
        Mock(side_effect=ValueError("conversion failed")),
    )
    # Both readers must surface the failure of a known document parser.
    monkeypatch.setattr(
        "app.services.client_file_extract.extract_isolated", document_extraction.extract_document
    )
    with pytest.raises(DocumentExtractionError, match="conversion failed"):
        extract_file_text("notes.html", b"plain readable bytes")
    with pytest.raises(DocumentExtractionError, match="conversion failed"):
        extract_document("notes.html", b"plain readable bytes")


def test_worker_parser_failure_propagates_without_a_text_fallback(monkeypatch):
    response = subprocess.CompletedProcess(
        [], 0, stdout=json.dumps({"ok": False, "error": "Document exceeds the input limit."})
    )
    monkeypatch.setattr(document_extraction.subprocess, "run", Mock(return_value=response))
    with pytest.raises(DocumentExtractionError, match="input limit"):
        extract_isolated("report.xlsx", b"sheet bytes")
