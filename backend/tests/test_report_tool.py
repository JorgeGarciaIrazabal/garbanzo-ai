"""Tests for the submit_report native tool."""

import pytest
from sqlalchemy import select

from app.models.report import Report
from app.services.native_tools import (
    ALL_NATIVE_TOOLS,
    REPORT_TOOL,
    execute_native_tool,
    native_tool_descriptors,
)

pytestmark = pytest.mark.asyncio

OWNER = "test@example.com"


async def _run(db, args):
    return await execute_native_tool(name=REPORT_TOOL, args=args, db=db, user_id=OWNER)


class TestRegistration:
    async def test_tool_registered_and_advertised(self):
        assert REPORT_TOOL in ALL_NATIVE_TOOLS
        names = [d["function"]["name"] for d in native_tool_descriptors()]
        assert REPORT_TOOL in names


class TestSubmitReport:
    async def test_files_a_bug_report(self, db_session):
        result = await _run(
            db_session,
            {"type": "bug", "title": "Mic dead", "description": "No transcription on Android."},
        )
        assert result["ok"] is True
        assert result["report"]["type"] == "bug"
        assert result["report"]["status"] == "open"

        rows = (await db_session.execute(select(Report))).scalars().all()
        assert len(rows) == 1
        assert rows[0].user_id == OWNER
        assert rows[0].title == "Mic dead"

    async def test_files_a_feature_request(self, db_session):
        result = await _run(
            db_session,
            {"type": "feature", "title": "PT voice", "description": "Add Portuguese TTS."},
        )
        assert result["ok"] is True
        assert result["report"]["type"] == "feature"

    async def test_rejects_unknown_type(self, db_session):
        result = await _run(
            db_session,
            {"type": "question", "title": "x", "description": "y"},
        )
        assert result["ok"] is False
        assert "type" in result["error"]
        assert (await db_session.execute(select(Report))).scalars().first() is None

    async def test_requires_title_and_description(self, db_session):
        assert (await _run(db_session, {"type": "bug", "title": "", "description": "y"}))[
            "ok"
        ] is False
        assert (await _run(db_session, {"type": "bug", "title": "x", "description": " "}))[
            "ok"
        ] is False

    async def test_enforces_title_length(self, db_session):
        result = await _run(
            db_session,
            {"type": "bug", "title": "t" * 201, "description": "y"},
        )
        assert result["ok"] is False
        assert "200" in result["error"]
