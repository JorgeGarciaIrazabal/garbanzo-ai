"""Tests for NotificationService — in-app notifications + preferences."""

import pytest

from app.services.notification_service import NotificationService

pytestmark = pytest.mark.asyncio


class TestNotificationCrud:
    async def test_create_and_list(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        notif = await svc.create(
            user_id=test_user_email,
            title="Hello",
            body="world",
            channel="chat_responses",
            data={"foo": "bar"},
        )
        assert notif.id
        assert notif.is_read is False

        listed = await svc.list_for_user(test_user_email)
        assert len(listed) == 1
        assert listed[0].id == notif.id

    async def test_unread_count(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        await svc.create(user_id=test_user_email, title="a", body="b")
        await svc.create(user_id=test_user_email, title="c", body="d")
        assert await svc.unread_count(test_user_email) == 2

    async def test_mark_read(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        notif = await svc.create(user_id=test_user_email, title="a", body="b")
        assert await svc.mark_read(test_user_email, notif.id) is True
        assert await svc.unread_count(test_user_email) == 0

    async def test_mark_read_missing(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        assert await svc.mark_read(test_user_email, "missing") is False

    async def test_mark_read_other_user_cannot_touch(
        self, db_session, test_user_email
    ):
        from app.core.security import hash_password
        from app.models.user import User

        other = User(email="other@example.com", hashed_password=hash_password("x"))
        db_session.add(other)
        await db_session.commit()

        svc = NotificationService(db_session)
        notif = await svc.create(user_id=test_user_email, title="a", body="b")
        # Wrong user can't mark read.
        assert await svc.mark_read("other@example.com", notif.id) is False
        assert await svc.unread_count(test_user_email) == 1

    async def test_mark_all_read(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        await svc.create(user_id=test_user_email, title="a", body="b")
        await svc.create(user_id=test_user_email, title="c", body="d")
        count = await svc.mark_all_read(test_user_email)
        assert count == 2
        assert await svc.unread_count(test_user_email) == 0

    async def test_delete_notification(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        notif = await svc.create(user_id=test_user_email, title="a", body="b")
        assert await svc.delete(test_user_email, notif.id) is True
        assert await svc.list_for_user(test_user_email) == []

    async def test_delete_missing(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        assert await svc.delete(test_user_email, "missing") is False


class TestNotificationPreferences:
    async def test_get_preferences_creates_default(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        prefs = await svc.get_preferences(test_user_email)
        assert prefs.chat_responses_enabled is True
        assert prefs.reminders_enabled is True
        assert prefs.system_alerts_enabled is True

    async def test_update_preferences(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        prefs = await svc.update_preferences(
            test_user_email, reminders_enabled=False
        )
        assert prefs.reminders_enabled is False
        assert prefs.chat_responses_enabled is True

    async def test_is_channel_enabled(self, db_session, test_user_email):
        svc = NotificationService(db_session)
        # Seed preferences then disable reminders.
        await svc.update_preferences(test_user_email, reminders_enabled=False)
        assert await svc.is_channel_enabled(test_user_email, "reminders") is False
        assert (
            await svc.is_channel_enabled(test_user_email, "chat_responses") is True
        )
        # Unknown channels default to True.
        assert await svc.is_channel_enabled(test_user_email, "weird") is True
