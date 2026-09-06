import json
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path

from scripts.ai_dev.models import (
    CodexQualificationHarness,
    Qualification,
    catalog_is_stale,
    discover,
    discover_ollama,
    resolve_route,
    save_catalog,
)


class Client:
    def __init__(self):
        self.calls = []

    def request(self, method, params=None):
        self.calls.append((method, params))
        if params.get("cursor") == "next":
            return {"data": [{"id": "gpt-5.6-sol"}], "nextCursor": None}
        return {"data": [{"id": "gpt-6-astra"}], "nextCursor": "next"}


class ModelTests(unittest.TestCase):
    def test_discover_paginates_account_catalog(self):
        client = Client()
        self.assertEqual([item["id"] for item in discover(client)], ["gpt-6-astra", "gpt-5.6-sol"])
        self.assertEqual(client.calls[-1][1]["cursor"], "next")

    def test_architecture_never_silently_downgrades(self):
        with self.assertRaisesRegex(ValueError, "refusing silent downgrade"):
            resolve_route("architecture", [{"id": "gpt-5.6-sol"}])

    def test_route_pins_model_and_requested_effort(self):
        catalog = [
            {"id": "gpt-6-astra", "supportedReasoningEfforts": [{"reasoningEffort": "medium"}]}
        ]
        self.assertEqual(
            resolve_route("architecture", catalog),
            {"model": "gpt-6-astra", "reasoningEffort": "medium"},
        )

    def test_route_does_not_silently_change_effort(self):
        catalog = [{"id": "gpt-6-astra", "supportedReasoningEfforts": [{"reasoningEffort": "low"}]}]
        with self.assertRaisesRegex(ValueError, "reasoning effort.*refusing silent downgrade"):
            resolve_route("architecture", catalog)

    def test_only_fully_evidenced_qualification_is_promoted(self):
        checks = {
            name: True for name in ("tool_call", "patch", "test", "interrupt", "failure_report")
        }
        good = Qualification(
            "good", datetime.now(UTC).isoformat(), checks, {name: "artifact" for name in checks}
        )
        bad = Qualification(
            "bad",
            datetime.now(UTC).isoformat(),
            checks | {"patch": False},
            {name: "artifact" for name in checks},
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "catalog.json"
            save_catalog(path, [], [good, bad])
            self.assertEqual(json.loads(path.read_text())["promoted"], ["codex:good"])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_catalog_refreshes_weekly(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "catalog.json"
            old = datetime.now(UTC) - timedelta(days=7)
            path.write_text(json.dumps({"refreshedAt": old.isoformat()}))
            self.assertTrue(catalog_is_stale(path))

    def test_ollama_catalog_checks_exact_requested_families(self):
        import unittest.mock

        response = unittest.mock.MagicMock()
        response.__enter__.return_value = response
        response.__exit__.return_value = False
        response.read.return_value = json.dumps(
            {"models": [{"model": "glm-5.3:cloud"}, {"model": "deepseek-v4-pro:cloud"}]}
        ).encode()
        with unittest.mock.patch("urllib.request.urlopen", return_value=response):
            result = discover_ollama(api_key="secret")
        self.assertTrue(result["requestedFamilies"]["glm-5.3"])
        self.assertFalse(result["requestedFamilies"]["kimi-k3"])

    def test_interrupt_requires_observed_running_sleep(self):
        quota_failure = '{"type":"turn.failed","error":{"message":"quota"}}\n'
        self.assertFalse(
            CodexQualificationHarness._validate("interrupt", 1, quota_failure, Path("."), 2)
        )

    def test_failure_requires_failed_command_and_agent_report(self):
        events = "\n".join(
            [
                json.dumps(
                    {
                        "type": "item.completed",
                        "item": {
                            "type": "command_execution",
                            "command": "just fail",
                            "status": "failed",
                            "exit_code": 1,
                        },
                    }
                ),
                json.dumps(
                    {
                        "type": "item.completed",
                        "item": {
                            "type": "agent_message",
                            "text": "Command failed with exit code 1",
                        },
                    }
                ),
            ]
        )
        self.assertTrue(
            CodexQualificationHarness._validate("failure_report", 0, events, Path("."), 1)
        )
