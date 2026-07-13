"""Tests for ScheduledActionService — CRUD + trigger validation."""

from datetime import UTC, datetime, timedelta

import pytest
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.date import DateTrigger

from app.services.scheduled_action_service import (
    ScheduledActionService,
    build_trigger,
    compute_next_run,
)


class TestBuildTrigger:
    def test_cron_only(self):
        trigger = build_trigger("0 9 * * *", None)
        assert isinstance(trigger, CronTrigger)

    def test_run_at_only(self):
        when = datetime(2099, 1, 1, 10, tzinfo=UTC)
        trigger = build_trigger(None, when)
        assert isinstance(trigger, DateTrigger)

    def test_naive_run_at_is_coerced_to_utc(self):
        naive = datetime(2099, 1, 1, 10)
        trigger = build_trigger(None, naive)
        assert isinstance(trigger, DateTrigger)
        assert trigger.run_date.tzinfo is not None

    def test_both_raises(self):
        with pytest.raises(ValueError, match="cron_expr OR run_at"):
            build_trigger("0 9 * * *", datetime(2099, 1, 1, tzinfo=UTC))

    def test_neither_raises(self):
        with pytest.raises(ValueError, match="Either cron_expr or run_at"):
            build_trigger(None, None)

    def test_invalid_cron_raises(self):
        with pytest.raises(ValueError, match="Invalid cron expression"):
            build_trigger("not a cron", None)


class TestComputeNextRun:
    def test_daily_cron_produces_future_datetime(self):
        nxt = compute_next_run("0 9 * * *", None)
        assert nxt is not None
        assert nxt > datetime.now(tz=UTC)

    def test_one_off_in_past_returns_none(self):
        past = datetime.now(tz=UTC) - timedelta(days=1)
        assert compute_next_run(None, past) is None

    def test_one_off_in_future_returns_that_time(self):
        future = datetime.now(tz=UTC) + timedelta(days=1)
        nxt = compute_next_run(None, future)
        assert nxt is not None
        assert abs((nxt - future).total_seconds()) < 1


class TestScheduledActionServiceCreate:
    pytestmark = pytest.mark.asyncio

    async def test_create_recurring(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="Do the thing",
            title="Morning",
            cron_expr="0 9 * * *",
        )
        assert action.id
        assert action.prompt == "Do the thing"
        assert action.cron_expr == "0 9 * * *"
        assert action.run_at is None
        assert action.is_active is True
        assert action.next_run is not None

    async def test_create_one_off(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        when = datetime.now(tz=UTC) + timedelta(days=1)
        action = await svc.create(
            user_id=test_user_email,
            prompt="Ping me",
            run_at=when,
        )
        assert action.run_at is not None
        assert action.cron_expr is None
        assert action.next_run is not None

    async def test_create_inactive_skips_next_run(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="Later",
            cron_expr="0 9 * * *",
            is_active=False,
        )
        assert action.is_active is False
        assert action.next_run is None

    async def test_create_invalid_cron_raises(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        with pytest.raises(ValueError):
            await svc.create(
                user_id=test_user_email,
                prompt="bad",
                cron_expr="not-a-cron",
            )


class TestScheduledActionServiceReads:
    pytestmark = pytest.mark.asyncio

    async def test_get_scoped_to_user(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="X",
            cron_expr="* * * * *",
        )
        assert (await svc.get(action.id, test_user_email)) is not None
        assert (await svc.get(action.id, "other@example.com")) is None

    async def test_get_any_ignores_user(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="X",
            cron_expr="* * * * *",
        )
        assert (await svc.get_any(action.id)) is not None
        assert (await svc.get_any("missing")) is None

    async def test_list_for_user_excludes_others(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        await svc.create(user_id=test_user_email, prompt="a", cron_expr="* * * * *")
        await svc.create(user_id=test_user_email, prompt="b", cron_expr="* * * * *")

        actions = await svc.list_for_user(test_user_email)
        assert len(actions) == 2
        prompts = {a.prompt for a in actions}
        assert prompts == {"a", "b"}

        others = await svc.list_for_user("other@example.com")
        assert others == []

    async def test_list_active_only_returns_active(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        await svc.create(user_id=test_user_email, prompt="on", cron_expr="* * * * *")
        await svc.create(
            user_id=test_user_email,
            prompt="off",
            cron_expr="* * * * *",
            is_active=False,
        )

        active = await svc.list_active()
        assert len(active) == 1
        assert active[0].prompt == "on"


class TestScheduledActionServiceUpdate:
    pytestmark = pytest.mark.asyncio

    async def test_update_prompt_and_title(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="orig",
            cron_expr="0 9 * * *",
        )
        updated = await svc.update(
            action.id,
            test_user_email,
            prompt="new",
            title="renamed",
        )
        assert updated is not None
        assert updated.prompt == "new"
        assert updated.title == "renamed"

    async def test_update_toggle_inactive_clears_next_run(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="x",
            cron_expr="0 9 * * *",
        )
        assert action.next_run is not None

        updated = await svc.update(action.id, test_user_email, is_active=False)
        assert updated is not None
        assert updated.is_active is False
        assert updated.next_run is None

        reactivated = await svc.update(action.id, test_user_email, is_active=True)
        assert reactivated is not None
        assert reactivated.is_active is True
        assert reactivated.next_run is not None

    async def test_update_swap_cron_to_run_at(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="x",
            cron_expr="0 9 * * *",
        )
        when = datetime.now(tz=UTC) + timedelta(days=1)
        updated = await svc.update(
            action.id,
            test_user_email,
            cron_expr=None,
            run_at=when,
            set_cron=True,
            set_run_at=True,
        )
        assert updated is not None
        assert updated.cron_expr is None
        assert updated.run_at is not None

    async def test_update_both_triggers_raises(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="x",
            cron_expr="0 9 * * *",
        )
        with pytest.raises(ValueError, match="not both"):
            await svc.update(
                action.id,
                test_user_email,
                run_at=datetime.now(tz=UTC) + timedelta(days=1),
                set_run_at=True,
            )

    async def test_update_clearing_both_triggers_raises(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="x",
            cron_expr="0 9 * * *",
        )
        with pytest.raises(ValueError, match="required"):
            await svc.update(
                action.id,
                test_user_email,
                cron_expr=None,
                set_cron=True,
            )

    async def test_update_returns_none_for_missing(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        result = await svc.update("missing", test_user_email, prompt="x")
        assert result is None


class TestScheduledActionServiceDelete:
    pytestmark = pytest.mark.asyncio

    async def test_delete_existing(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="x",
            cron_expr="0 9 * * *",
        )
        assert await svc.delete(action.id, test_user_email) is True
        assert await svc.get(action.id, test_user_email) is None

    async def test_delete_missing_returns_false(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        assert await svc.delete("missing", test_user_email) is False

    async def test_delete_wrong_user_returns_false(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="x",
            cron_expr="0 9 * * *",
        )
        assert await svc.delete(action.id, "other@example.com") is False
        # Still present for the actual owner.
        assert await svc.get(action.id, test_user_email) is not None


class TestScheduledActionServiceRecordRun:
    pytestmark = pytest.mark.asyncio

    async def test_record_run_recurring_keeps_active(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        action = await svc.create(
            user_id=test_user_email,
            prompt="x",
            cron_expr="0 9 * * *",
        )
        new_next = datetime.now(tz=UTC) + timedelta(days=1)
        await svc.record_run(action.id, status_label="success", next_run=new_next)

        refreshed = await svc.get(action.id, test_user_email)
        assert refreshed is not None
        assert refreshed.is_active is True
        assert refreshed.last_run_status == "success"
        assert refreshed.last_run_at is not None
        assert refreshed.next_run is not None

    async def test_record_run_one_off_auto_deactivates(self, db_session, test_user_email):
        svc = ScheduledActionService(db_session)
        when = datetime.now(tz=UTC) + timedelta(days=1)
        action = await svc.create(user_id=test_user_email, prompt="x", run_at=when)
        await svc.record_run(action.id, status_label="success", next_run=None)

        refreshed = await svc.get(action.id, test_user_email)
        assert refreshed is not None
        assert refreshed.is_active is False
        assert refreshed.next_run is None

    async def test_record_run_missing_is_noop(self, db_session):
        svc = ScheduledActionService(db_session)
        # Should not raise.
        await svc.record_run("missing", status_label="error", next_run=None)
