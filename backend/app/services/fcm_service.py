"""Firebase Cloud Messaging integration for push notifications."""

import asyncio
import logging
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, messaging
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.device_token import DeviceToken
from app.services.notification_service import NotificationService

logger = logging.getLogger(__name__)

_app: firebase_admin.App | None = None

VALID_CHANNELS = {"chat_responses", "reminders", "system_alerts"}


def init_firebase() -> None:
    """Initialize the Firebase Admin SDK once at app startup.

    Safe to call when credentials are missing — logs a warning and becomes a
    no-op; ``send_to_user`` will skip silently in that case.
    """
    global _app
    if _app is not None:
        return

    settings = get_settings()
    cred_path_str = settings.firebase_credentials_path
    if not cred_path_str:
        logger.info("Firebase credentials not configured; push notifications disabled")
        return

    cred_path = Path(cred_path_str)
    if not cred_path.is_absolute():
        cred_path = Path.cwd() / cred_path

    if not cred_path.exists():
        logger.warning(
            "Firebase credentials file not found at %s; push notifications disabled",
            cred_path,
        )
        return

    try:
        cred = credentials.Certificate(str(cred_path))
        _app = firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin SDK initialized")
    except Exception:
        logger.exception("Failed to initialize Firebase Admin SDK")


def is_enabled() -> bool:
    return _app is not None


async def send_to_user(
    db: AsyncSession,
    user_id: str,
    *,
    title: str,
    body: str,
    data: dict[str, str] | None = None,
    channel: str = "chat_responses",
    persist: bool = True,
) -> int:
    """Send a push notification to every device registered to ``user_id``.

    Also persists a row in ``notifications`` for the in-app notification center
    (when ``persist=True``). Respects the user's NotificationPreferences: if the
    ``channel`` is disabled for this user, nothing is sent or persisted.

    Returns the number of successful FCM deliveries. Invalid/expired tokens are
    removed from the DB. Returns 0 if FCM is disabled — the in-app notification
    is still persisted in that case.
    """
    if channel not in VALID_CHANNELS:
        logger.warning("Unknown notification channel %r; falling back to chat_responses", channel)
        channel = "chat_responses"

    notif_svc = NotificationService(db)
    if not await notif_svc.is_channel_enabled(user_id, channel):
        return 0

    if persist:
        await notif_svc.create(
            user_id=user_id,
            title=title,
            body=body,
            channel=channel,
            data=dict(data) if data else None,
        )

    if _app is None:
        return 0

    result = await db.execute(
        select(DeviceToken).where(DeviceToken.user_id == user_id)
    )
    tokens = list(result.scalars().all())
    if not tokens:
        return 0

    sent = 0
    expired_tokens: list[str] = []
    for dt in tokens:
        try:
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data=data or {},
                token=dt.token,
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id=channel,
                    ),
                ),
            )
            # firebase_admin is synchronous; run in a thread to avoid blocking.
            await asyncio.to_thread(messaging.send, message)
            sent += 1
        except messaging.UnregisteredError:
            expired_tokens.append(dt.token)
        except Exception:
            logger.exception("Failed to send FCM push to token %s...", dt.token[:12])

    if expired_tokens:
        await db.execute(
            delete(DeviceToken).where(DeviceToken.token.in_(expired_tokens))
        )
        await db.commit()
        logger.info("Removed %d expired FCM tokens for user %s", len(expired_tokens), user_id)

    return sent
