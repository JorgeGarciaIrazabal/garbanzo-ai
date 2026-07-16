-- Friend request / accepted notifications (Idea 5, subtask 2) get their own
-- NotificationPreferences channel so they can be muted independently of chat
-- replies and reminders. Default on, like every other channel.
ALTER TABLE notification_preferences
    ADD COLUMN IF NOT EXISTS friend_updates_enabled BOOLEAN NOT NULL DEFAULT true;
