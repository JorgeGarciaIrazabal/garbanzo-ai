"""Send a test FCM push notification to verify the Firebase setup.

Usage:
    uv run python scripts/test_fcm.py <fcm_token>

Credentials are read from ./firebase-service-account.json (relative to backend/).
"""

import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, messaging

CREDENTIALS_PATH = Path(__file__).resolve().parent.parent / "firebase-service-account.json"


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: python scripts/test_fcm.py <fcm_token>", file=sys.stderr)
        sys.exit(1)

    token = sys.argv[1].strip()

    if not CREDENTIALS_PATH.exists():
        print(f"Missing credentials file: {CREDENTIALS_PATH}", file=sys.stderr)
        sys.exit(1)

    cred = credentials.Certificate(str(CREDENTIALS_PATH))
    firebase_admin.initialize_app(cred)

    message = messaging.Message(
        notification=messaging.Notification(
            title="Garbanzo AI test",
            body="If you see this, FCM is wired up correctly.",
        ),
        token=token,
    )

    response = messaging.send(message)
    print(f"Sent successfully. Message ID: {response}")


if __name__ == "__main__":
    main()
