"""Unit tests for scheduler helpers."""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from app.scheduler import (
    _job_id,
    register_scheduled_action,
    unregister_scheduled_action,
)


def _action(is_active: bool = True, cron: str | None = "0 9 * * *"):
    return SimpleNamespace(
        id="a1",
        title="Standup",
        cron_expr=cron,
        run_at=None,
        is_active=is_active,
    )


def test_job_id_prefixed():
    assert _job_id("abc").startswith("scheduled-action:")


def test_register_active_adds_job():
    fake_scheduler = MagicMock()
    with patch("app.scheduler.get_scheduler", return_value=fake_scheduler):
        register_scheduled_action(_action())
    fake_scheduler.add_job.assert_called_once()
    kwargs = fake_scheduler.add_job.call_args.kwargs
    assert kwargs["id"] == _job_id("a1")
    assert kwargs["replace_existing"] is True


def test_register_inactive_triggers_unregister():
    fake_scheduler = MagicMock()
    fake_scheduler.get_job.return_value = MagicMock()
    with patch("app.scheduler.get_scheduler", return_value=fake_scheduler):
        register_scheduled_action(_action(is_active=False))
    # add_job was not called; remove_job was.
    fake_scheduler.add_job.assert_not_called()
    fake_scheduler.remove_job.assert_called_once_with(_job_id("a1"))


def test_register_invalid_cron_is_logged_not_raised(caplog):
    fake_scheduler = MagicMock()
    bad = SimpleNamespace(id="bad", title=None, cron_expr="nonsense", run_at=None, is_active=True)
    with patch("app.scheduler.get_scheduler", return_value=fake_scheduler):
        register_scheduled_action(bad)
    # No add_job call.
    fake_scheduler.add_job.assert_not_called()


def test_register_with_run_at_uses_date_trigger():
    fake_scheduler = MagicMock()
    action = SimpleNamespace(
        id="one-off",
        title=None,
        cron_expr=None,
        run_at=datetime.now(tz=UTC) + timedelta(days=1),
        is_active=True,
    )
    with patch("app.scheduler.get_scheduler", return_value=fake_scheduler):
        register_scheduled_action(action)
    fake_scheduler.add_job.assert_called_once()


def test_unregister_removes_job_when_present():
    fake_scheduler = MagicMock()
    fake_scheduler.get_job.return_value = MagicMock()
    with patch("app.scheduler.get_scheduler", return_value=fake_scheduler):
        unregister_scheduled_action("a1")
    fake_scheduler.remove_job.assert_called_once_with(_job_id("a1"))


def test_unregister_is_noop_when_missing():
    fake_scheduler = MagicMock()
    fake_scheduler.get_job.return_value = None
    with patch("app.scheduler.get_scheduler", return_value=fake_scheduler):
        unregister_scheduled_action("missing")
    fake_scheduler.remove_job.assert_not_called()
