"""Unit tests for the ScheduledAction Pydantic schemas."""

from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError

from app.schemas.scheduled_action import (
    ScheduledActionCreate,
    ScheduledActionUpdate,
)


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

    def test_empty_prompt_rejected(self):
        with pytest.raises(ValidationError):
            ScheduledActionCreate(prompt="", cron_expr="0 9 * * *")


class TestUpdateSchema:
    def test_all_fields_optional(self):
        # Empty patch is valid.
        ScheduledActionUpdate()

    def test_partial_update(self):
        model = ScheduledActionUpdate(is_active=False, title="renamed")
        assert model.is_active is False
        assert model.title == "renamed"
        assert model.prompt is None

    def test_prompt_length_constraint(self):
        # Empty string fails min_length=1.
        with pytest.raises(ValidationError):
            ScheduledActionUpdate(prompt="")
