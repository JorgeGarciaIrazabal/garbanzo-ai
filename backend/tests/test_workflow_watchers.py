"""The in-memory "is anyone looking at the app?" signal that gates the
completion push (see workflow_watchers' module docstring)."""

from app.services import workflow_watchers


def _clean(*run_ids: str):
    for run_id in run_ids:
        workflow_watchers.forget(run_id)


def test_a_recent_poll_counts_as_watching():
    try:
        assert not workflow_watchers.is_watched("r1")
        workflow_watchers.mark_watching("r1")
        assert workflow_watchers.is_watched("r1")
    finally:
        _clean("r1")


def test_forget_releases_the_entry():
    workflow_watchers.mark_watching("r1")
    workflow_watchers.forget("r1")
    assert not workflow_watchers.is_watched("r1")


def test_an_old_poll_does_not_count(monkeypatch):
    try:
        workflow_watchers.mark_watching("r1")
        monkeypatch.setattr(workflow_watchers, "WATCHING_WINDOW_SECONDS", -1.0)
        assert not workflow_watchers.is_watched("r1")
    finally:
        _clean("r1")


def test_abandoned_entries_are_pruned_on_the_next_poll(monkeypatch):
    """Completion normally forgets an entry; a run that never completes must
    not leak its entry forever."""
    try:
        workflow_watchers.mark_watching("ghost")
        monkeypatch.setattr(workflow_watchers, "_STALE_AFTER_SECONDS", -1.0)
        workflow_watchers.mark_watching("live")
        assert "ghost" not in workflow_watchers._last_seen
    finally:
        _clean("ghost", "live")
