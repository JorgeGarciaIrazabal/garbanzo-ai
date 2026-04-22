# Push Notifications

This document describes how push notifications work in Garbanzo AI and how to set them up on a new machine.

## Overview

Push notifications are delivered through **Firebase Cloud Messaging (FCM)**. When a user backgrounds the app during a long-running assistant response, the backend detects the disconnection and sends a push containing a snippet of the generated response so the user can return to the conversation.

The design is intentionally minimal for now. Only Android is wired up end-to-end.

## Architecture

```
┌─────────────────────┐         ┌─────────────────────┐          ┌──────────────┐
│ Flutter (Android)   │         │ FastAPI backend     │          │   Firebase   │
│                     │         │                     │          │    (FCM)     │
│  ┌──────────────┐   │         │  ┌──────────────┐   │          │              │
│  │PushService   │───│─(1)─────│─▶│devices.py    │   │          │              │
│  │  init        │   │  reg    │  │POST /register│   │          │              │
│  │  getToken    │   │  token  │  └──────┬───────┘   │          │              │
│  └──────────────┘   │         │         │           │          │              │
│                     │         │         ▼           │          │              │
│                     │         │  ┌──────────────┐   │          │              │
│                     │         │  │ device_tokens│   │          │              │
│                     │         │  │    table     │   │          │              │
│                     │         │  └──────┬───────┘   │          │              │
│                     │         │         │           │          │              │
│                     │◀─(4)─SSE│─ chat.py│           │          │              │
│                     │  stream │         │           │          │              │
│    backgrounded ────│─(5)X    │         │           │          │              │
│                     │         │         ▼           │          │              │
│                     │         │  ┌──────────────┐   │          │              │
│                     │         │  │ fcm_service  │───│───(6)───▶│              │
│                     │         │  │ send_to_user │   │   send   │              │
│                     │         │  └──────────────┘   │          │              │
│                     │         │                     │          │              │
│  [notification]◀────│─────────│─────────────────────│──────(7)─│              │
└─────────────────────┘         └─────────────────────┘          └──────────────┘
```

### Flow

1. After login, the Flutter app obtains an FCM token and POSTs it to `/api/v1/devices/register`.
2. The backend stores it in `device_tokens` (keyed by token, one user can have many).
3. The user sends a chat message — the backend streams the assistant's response as Server-Sent Events.
4. SSE frames arrive in the app and render live.
5. The user backgrounds the app. The OS eventually kills the HTTP connection.
6. The backend sees `asyncio.CancelledError` from `yield` inside `_sse_stream`, fires a background task that calls `FCMService.send_to_user`.
7. Firebase delivers the notification to the device. Android displays it automatically (it's a `notification`-typed FCM payload).

## Backend

### Files

| File | Role |
|------|------|
| `backend/app/models/device_token.py` | SQLAlchemy model |
| `backend/migrations/005_device_tokens.sql` | Schema migration |
| `backend/app/schemas/device.py` | Pydantic request/response models |
| `backend/app/services/device_service.py` | Token CRUD (register upsert, unregister) |
| `backend/app/services/fcm_service.py` | Firebase Admin SDK wrapper |
| `backend/app/api/v1/endpoints/devices.py` | REST endpoints |
| `backend/app/api/v1/endpoints/chat.py` | SSE stream with disconnect hook |
| `backend/app/main.py` | Calls `init_firebase()` on startup |
| `backend/app/core/config.py` | `firebase_credentials_path` setting |

### `device_tokens` table

| Column | Type | Notes |
|--------|------|-------|
| `id` | VARCHAR(36) PK | UUID |
| `user_id` | VARCHAR(255) FK → `users.email` | `ON DELETE CASCADE` |
| `token` | VARCHAR(512) UNIQUE | The FCM registration token |
| `platform` | VARCHAR(16) | `android`, `ios`, or `web` |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | Touched on reassignment |

### Endpoints

All require a JWT (`Authorization: Bearer <token>`).

| Method | Path | Body | Behavior |
|--------|------|------|----------|
| `POST` | `/api/v1/devices/register` | `{token, platform}` | Inserts the token, or reassigns to the current user if it already exists (handles device reuse after account switch). |
| `DELETE` | `/api/v1/devices/register` | `{token, platform}` | Removes the token. 404 if not found for the user. |

### Disconnect detection

`backend/app/api/v1/endpoints/chat.py::_sse_stream` accumulates assistant text as chunks flow through. When the client disconnects mid-stream, the `yield` raises `asyncio.CancelledError`. The handler schedules a background task (`asyncio.create_task`) that spins up its own DB session, looks up the user's devices, and sends a push. The re-raise ensures the generator exits cleanly.

The push is NOT sent when:
- The stream completes while the client is still connected (normal case).
- The accumulated body is empty (no content to preview).
- FCM isn't configured (`firebase_credentials_path` missing or file not found).

### Firebase Admin SDK init

`fcm_service.init_firebase()` is called from the FastAPI lifespan. It's a no-op if the credentials file is absent — the backend works fine without push, calls to `send_to_user` just return `0`.

## Flutter

### Files

| File | Role |
|------|------|
| `lib/features/notifications/services/push_service.dart` | Singleton managing Firebase + backend registration |
| `lib/main.dart` | Calls `PushService.instance.init()` at app start; registers/unregisters on auth transitions |
| `lib/core/api_client.dart` | `delete()` accepts an optional `data` body (needed to send the token on unregister) |

### `PushService` lifecycle

| When | Method | Effect |
|------|--------|--------|
| App start (cold) | `init()` | Calls `Firebase.initializeApp()`, subscribes to token-refresh and foreground-message streams. No-op on web/desktop. |
| After login/register success, or when already-logged-in | `registerDevice()` | Requests permission, fetches the FCM token, POSTs it to `/api/v1/devices/register`. |
| Logout | `unregisterDevice()` | DELETEs the stored token from the backend. |
| FCM rotates the token | `onTokenRefresh` listener | Re-POSTs the new token to the backend. |

### Android-specific setup

Three things must be present for the build to work:

1. `android/app/google-services.json` (downloaded from Firebase Console — see `Setup` below)
2. `com.google.gms.google-services` Gradle plugin applied in:
   - `android/build.gradle.kts` (declared)
   - `android/app/build.gradle.kts` (applied)
3. `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` in `AndroidManifest.xml`

All three are committed to the repo **except** `google-services.json`, which is gitignored because it embeds the Firebase API key.

## Setup on a new machine

### 1. Firebase Console

One-time per Firebase project; the credentials live in the shared project at [console.firebase.google.com](https://console.firebase.google.com/).

Obtain two files:

- **`google-services.json`** — Project Settings → General → *Your apps* → Android app `com.example.garbanzo_ai` → "google-services.json"
- **Service account JSON** — Project Settings → Service accounts → *Generate new private key*

### 2. Drop them in place

```bash
# Flutter side
cp google-services.json <repo>/android/app/google-services.json

# Backend side — filename must match FIREBASE_CREDENTIALS_PATH in .env
cp firebase-service-account.json <repo>/backend/firebase-service-account.json
```

Both files are gitignored.

### 3. Configure the backend

In `backend/.env`:

```
FIREBASE_CREDENTIALS_PATH=firebase-service-account.json
```

(Leave empty to disable push notifications without failing startup.)

### 4. Install dependencies

```bash
just install     # pulls firebase_core + firebase_messaging (Flutter) and firebase-admin (backend)
just db-migrate  # creates device_tokens table
```

## Testing

### Smoke test — prove FCM end-to-end

`backend/scripts/test_fcm.py` sends a test push to a given token:

```bash
cd backend
uv run python scripts/test_fcm.py <fcm_token>
```

To get a token, run the app (`just android`), log in, and copy the `[FCM] token:` line from the logs. If you've already wired registration in, you can also pull the latest token from the DB:

```bash
docker exec -i garbanzo_ai_postgres psql -U garbanzo -d garbanzo_ai \
  -c "SELECT token FROM device_tokens ORDER BY updated_at DESC LIMIT 1;"
```

### Full flow

1. Start backend: `just be-dev`. Look for `Firebase Admin SDK initialized` in the logs.
2. Run the app: `just android`.
3. Log in. The app will request notification permission and register with the backend. Confirm:
   ```bash
   docker exec -i garbanzo_ai_postgres psql -U garbanzo -d garbanzo_ai \
     -c "SELECT user_id, platform FROM device_tokens;"
   ```
4. Ask for a long response ("explain async Python in detail").
5. While it's streaming, press the home button to background the app.
6. Notification should appear with title "Response ready" and a content snippet.

## Troubleshooting

**App hangs on the Flutter splash screen at launch**
Usually means `Firebase.initializeApp()` is failing natively. Check `adb logcat` for Firebase/google-services errors. Confirm `google-services.json` is present at `android/app/google-services.json` and its `package_name` is `com.example.garbanzo_ai`.

**Gradle build fails with `File google-services.json is missing`**
Exactly what it says — place the file at `android/app/google-services.json`.

**`PushService` logs `Firebase init failed`**
Non-Android platform (web/desktop), or `google-services.json` is malformed. Expected on Linux desktop builds; push just won't work there.

**`POST /api/v1/devices/register` returns 401**
The user isn't logged in (no Authorization header), or the token expired.

**Notification never arrives after disconnect**
- Check backend log for `Firebase Admin SDK initialized`. If missing, credentials file isn't found.
- Check for `Failed to send push notification on disconnect` in logs.
- Verify the device token still exists (`SELECT * FROM device_tokens`). FCM auto-prunes expired tokens, so an old token from a re-installed app would return `UnregisteredError` and get deleted.
- Android's Doze mode on unplugged devices can delay notifications by several minutes. Plug the phone in to test.

**Notification arrives but the app is in the foreground and nothing visible happens**
This is expected. When the app is foregrounded, Android delivers the message to `FirebaseMessaging.onMessage` and does **not** show a system notification automatically. We currently just log it — to display it in-app, wire in `flutter_local_notifications`.

## Future work (not yet implemented)

Items from `TASKS.md` under `## Notifications`:

- Android notification channels (chat_responses, reminders, system_alerts) with per-channel importance — currently only `chat_responses` is referenced in code, not yet declared.
- In-app notification center (bell icon, unread list).
- Per-user notification preferences synced with channel settings.
- Tap-to-navigate: open the relevant conversation when the notification is tapped. The `data.conversation_id` field is already set by the backend; the Flutter side just needs a `onMessageOpenedApp` handler that routes to the chat page.
