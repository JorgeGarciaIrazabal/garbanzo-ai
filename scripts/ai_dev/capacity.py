"""Fail-closed unattended allowance policy for Codex and Ollama Cloud."""

from __future__ import annotations

import json
import math
import subprocess
from collections.abc import Callable
from dataclasses import asdict, dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from .app_server import AppServerClient

THRESHOLD = 80.0
MAX_SNAPSHOT_AGE = timedelta(minutes=10)
OLLAMA_USAGE_VERSION = "0.1.3"


@dataclass(frozen=True)
class Allowance:
    provider: str
    window: str
    used_percent: float | None
    observed_at: datetime
    valid: bool
    reason: str | None = None


@dataclass(frozen=True)
class Capacity:
    allowed_unattended: bool
    allowances: tuple[Allowance, ...]
    reasons: tuple[str, ...]

    def structured(self) -> dict[str, Any]:
        return {
            "allowedUnattended": self.allowed_unattended,
            "allowances": [
                {key: value for key, value in asdict(item).items() if key != "observed_at"}
                | {"observedAt": item.observed_at.isoformat()}
                for item in self.allowances
            ],
            "reasons": list(self.reasons),
        }


def codex_allowances(client: AppServerClient, *, now: datetime | None = None) -> list[Allowance]:
    # app-server currently provides reset timestamps but no snapshot timestamp. The
    # observed time therefore proves fetch freshness, not upstream reporting lag.
    observed = now or datetime.now(UTC)
    account = client.request("account/read", {"refreshToken": False})
    if account.get("requiresOpenaiAuth") and not account.get("account"):
        return [Allowance("codex", "account", None, observed, False, "authentication required")]
    result = client.request("account/rateLimits/read")
    snapshots: dict[str, Any] = {}
    primary = result.get("rateLimits")
    if isinstance(primary, dict):
        snapshots[str(primary.get("limitId", "default"))] = primary
    extra = result.get("rateLimitsByLimitId")
    if isinstance(extra, dict):
        snapshots.update(extra)
    allowances: list[Allowance] = []
    for limit_id, snapshot in snapshots.items():
        if not isinstance(snapshot, dict):
            continue
        for window in ("primary", "secondary"):
            value = snapshot.get(window)
            if value is None:
                continue
            percent = value.get("usedPercent") if isinstance(value, dict) else None
            valid = (
                isinstance(percent, (int, float))
                and not isinstance(percent, bool)
                and math.isfinite(float(percent))
                and 0 <= float(percent) <= 100
            )
            allowances.append(
                Allowance(
                    "codex",
                    f"{limit_id}:{window}",
                    float(percent) if valid else None,
                    observed,
                    valid,
                    None if valid else "invalid usage reading",
                )
            )
    if not allowances:
        allowances.append(
            Allowance("codex", "unknown", None, observed, False, "missing usage readings")
        )
    return allowances


def ollama_allowances(
    *,
    now: datetime | None = None,
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> list[Allowance]:
    # ollama-usage exposes reset_at but no scrape timestamp; this is receipt time.
    observed = now or datetime.now(UTC)
    try:
        version = runner(
            ["ollama-usage", "--version"], text=True, capture_output=True, timeout=10, check=False
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return [
            Allowance(
                "ollama",
                "reader",
                None,
                observed,
                False,
                f"ollama-usage {OLLAMA_USAGE_VERSION} required",
            )
        ]
    if version.returncode != 0 or OLLAMA_USAGE_VERSION not in version.stdout:
        return [
            Allowance(
                "ollama",
                "reader",
                None,
                observed,
                False,
                f"ollama-usage {OLLAMA_USAGE_VERSION} required",
            )
        ]
    try:
        result = runner(
            ["ollama-usage", "--json"], text=True, capture_output=True, timeout=20, check=False
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return [Allowance("ollama", "reader", None, observed, False, "usage reader failed")]
    if result.returncode == 2:
        return [
            Allowance(
                "ollama", "account", None, observed, False, "authentication required or expired"
            )
        ]
    if result.returncode != 0:
        return [Allowance("ollama", "reader", None, observed, False, "usage reader failed")]
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        payload = None
    allowances: list[Allowance] = []
    if isinstance(payload, dict):
        for name in ("5h", "weekly"):
            window = payload.get(name)
            percent = window.get("pct_used") if isinstance(window, dict) else None
            valid = (
                isinstance(percent, (int, float))
                and not isinstance(percent, bool)
                and math.isfinite(float(percent))
                and 0 <= float(percent) <= 100
            )
            allowances.append(
                Allowance(
                    "ollama",
                    name,
                    float(percent) if valid else None,
                    observed,
                    valid,
                    None if valid else "missing or invalid usage reading",
                )
            )
    return allowances or [
        Allowance("ollama", "unknown", None, observed, False, "invalid usage schema")
    ]


def evaluate(
    allowances: list[Allowance], *, unattended: bool, now: datetime | None = None
) -> Capacity:
    current = now or datetime.now(UTC)
    reasons: list[str] = []
    if not allowances:
        reasons.append("missing allowance readings")
    for item in allowances:
        age = current - item.observed_at.astimezone(UTC)
        if item.observed_at.astimezone(UTC) > current + timedelta(seconds=5):
            reasons.append(f"{item.provider} {item.window}: future-dated reading")
        elif not item.valid:
            reasons.append(f"{item.provider} {item.window}: {item.reason or 'invalid reading'}")
        elif age > MAX_SNAPSHOT_AGE:
            reasons.append(f"{item.provider} {item.window}: stale reading")
        elif (
            item.used_percent is None
            or isinstance(item.used_percent, bool)
            or not math.isfinite(item.used_percent)
            or not 0 <= item.used_percent <= 100
        ):
            reasons.append(f"{item.provider} {item.window}: missing reading")
        elif item.used_percent >= THRESHOLD:
            reasons.append(f"{item.provider} {item.window}: {item.used_percent:g}% used")
    return Capacity(not unattended or not reasons, tuple(allowances), tuple(reasons))


def register(subparsers) -> None:
    parser = subparsers.add_parser("capacity", help="Show Codex and Ollama allowance capacity")
    parser.add_argument("--unattended", action="store_true", help="Apply the overnight 80% cutoff")
    parser.set_defaults(func=handle)


def handle(args) -> dict[str, Any]:
    now = datetime.now(UTC)
    try:
        with AppServerClient() as client:
            values = codex_allowances(client, now=now)
    except (OSError, RuntimeError) as exc:
        values = [Allowance("codex", "reader", None, now, False, str(exc))]
    values.extend(ollama_allowances())
    return evaluate(values, unattended=bool(args.unattended)).structured()
