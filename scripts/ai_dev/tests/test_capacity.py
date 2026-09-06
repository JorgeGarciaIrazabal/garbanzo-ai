import json
import subprocess
import unittest
from datetime import UTC, datetime, timedelta

from scripts.ai_dev.capacity import Allowance, codex_allowances, evaluate, ollama_allowances


class Client:
    def request(self, method, params=None):
        if method == "account/read":
            return {"account": {"type": "chatgpt"}, "requiresOpenaiAuth": True}
        return {
            "rateLimits": {
                "limitId": "codex",
                "primary": {"usedPercent": 79},
                "secondary": {"usedPercent": 80},
            },
            "rateLimitsByLimitId": {"spark": {"primary": {"usedPercent": 4}}},
        }


class CapacityTests(unittest.TestCase):
    def test_all_codex_buckets_are_preserved_and_any_80_percent_blocks(self):
        now = datetime.now(UTC)
        values = codex_allowances(Client(), now=now)
        self.assertEqual(
            {item.window for item in values}, {"codex:primary", "codex:secondary", "spark:primary"}
        )
        result = evaluate(values, unattended=True, now=now)
        self.assertFalse(result.allowed_unattended)
        self.assertTrue(any("80%" in reason for reason in result.reasons))

    def test_foreground_displays_invalid_capacity_without_cutoff(self):
        value = Allowance("codex", "x", None, datetime.now(UTC), False, "missing")
        self.assertTrue(evaluate([value], unattended=False).allowed_unattended)

    def test_stale_and_missing_readings_fail_closed(self):
        now = datetime.now(UTC)
        stale = Allowance("codex", "x", 10, now - timedelta(minutes=11), True)
        missing = Allowance("ollama", "x", None, now, False, "missing")
        self.assertFalse(evaluate([stale, missing], unattended=True, now=now).allowed_unattended)

    def test_pinned_ollama_reader_schema(self):
        responses = iter(
            [
                subprocess.CompletedProcess([], 0, "ollama-usage 0.1.3\n", ""),
                subprocess.CompletedProcess(
                    [],
                    0,
                    json.dumps(
                        {
                            "5h": {"identifier": "5h", "pct_used": 79},
                            "weekly": {"identifier": "weekly", "pct_used": 80},
                        }
                    ),
                    "",
                ),
            ]
        )
        values = ollama_allowances(runner=lambda *args, **kwargs: next(responses))
        self.assertEqual([item.used_percent for item in values], [79, 80])

    def test_expired_ollama_auth_fails_closed(self):
        responses = iter(
            [
                subprocess.CompletedProcess([], 0, "ollama-usage 0.1.3\n", ""),
                subprocess.CompletedProcess([], 2, "", "expired"),
            ]
        )
        values = ollama_allowances(runner=lambda *args, **kwargs: next(responses))
        self.assertFalse(values[0].valid)
        self.assertIn("expired", values[0].reason)

    def test_missing_reader_is_returned_as_provider_failure(self):
        def missing(*args, **kwargs):
            raise FileNotFoundError

        values = ollama_allowances(runner=missing)
        self.assertFalse(values[0].valid)

    def test_nan_infinity_bool_and_future_timestamps_fail_closed(self):
        now = datetime.now(UTC)
        invalid = [
            Allowance("x", "nan", float("nan"), now, False),
            Allowance("x", "inf", float("inf"), now, False),
            Allowance("x", "bool", None, now, False),
            Allowance("x", "future", 2, now + timedelta(minutes=1), True),
        ]
        result = evaluate(invalid, unattended=True, now=now)
        self.assertFalse(result.allowed_unattended)
        self.assertTrue(any("future-dated" in reason for reason in result.reasons))
