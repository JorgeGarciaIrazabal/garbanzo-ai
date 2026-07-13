"""Tests for the ScheduledAction custom schedule validator.

Only the cron_expr/run_at mutual-exclusivity validator is covered here;
plain field constraints are Pydantic's job.
"""

from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError

from app.schemas.scheduled_action import ScheduledActionCreate


class TestCreateValidator:
    def test_cron_only_passes(self):
        model = ScheduledActionCreate(prompt="x", cron_expr="0 9 * * *")
        assert model.cron_expr == "0 9 * * *"
        assert model.run_at is None

    def test_run_at_only_passes(self):
        when = datetime.now(tz=UTC) + timedelta(days=1)
        model = ScheduledActionCreate(prompt="x", run_at=when)
        assert model.run_at == when

    def test_both_rejected(self):
        with pytest.raises(ValidationError):
            ScheduledActionCreate(
                prompt="x",
                cron_expr="0 9 * * *",
                run_at=datetime.now(tz=UTC),
            )

    def test_neither_rejected(self):
        with pytest.raises(ValidationError):
            ScheduledActionCreate(prompt="x")

    def test_empty_cron_treated_as_missing(self):
        with pytest.raises(ValidationError):
            ScheduledActionCreate(prompt="x", cron_expr="  ")
