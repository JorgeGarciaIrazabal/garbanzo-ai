import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.ai_dev import triage


class TriageTests(unittest.TestCase):
    def test_grouping_uses_signature_component_release_and_not_title(self):
        base = {
            "source": "backend",
            "description": "Timeout id 123",
            "metadata": {"component": "chat", "release": "v2"},
        }
        same = {**base, "title": "Unrelated wording", "description": "Timeout id 999"}
        different_release = {**base, "metadata": {"component": "chat", "release": "v3"}}
        groups = triage.group_reports([base, same, different_release])
        self.assertEqual(sorted(map(len, groups.values())), [1, 2])
        self.assertEqual(sum(len(rows) for rows in groups.values()), 3)

    def test_normalization_does_not_merge_distinct_failures_by_title(self):
        left = {"title": "Chat failed", "description": "connection timeout", "source": "frontend"}
        right = {"title": "Chat failed", "description": "permission denied", "source": "frontend"}
        self.assertNotEqual(triage.group_key(left), triage.group_key(right))

    def test_release_aware_recurrence(self):
        self.assertEqual(
            triage.recurrence_action("v1", "v2", True, report_predates_fix=True),
            "retain_old_release_observation",
        )
        self.assertEqual(triage.recurrence_action("v3", "v2", True), "requires_release_comparison")
        self.assertEqual(triage.recurrence_action("v2", "v2", True), "reopen_task_and_report")
        self.assertEqual(triage.recurrence_action("v2", "v2", False), "await_reproduction")

    def test_production_failure_is_not_reported_as_empty_success(self):
        class Completed:
            returncode = 1
            stdout = ""
            stderr = "docker unavailable"

        with tempfile.TemporaryDirectory() as root:
            snapshot = triage.production_snapshot(root, runner=lambda *args, **kwargs: Completed())
        self.assertFalse(snapshot["collection_ok"])
        self.assertFalse(snapshot["services"]["ok"])
        self.assertIn("private error evidence", snapshot["services"]["error"])

    def test_findings_close_when_absent_and_reopen_on_recurrence(self):
        rows = [
            {
                "id": "old",
                "external_ref": "finding:pip-audit:gone",
                "status": "open",
            },
            {
                "id": "again",
                "external_ref": "finding:pip-audit:"
                + triage.hashlib.sha256(b"recurs").hexdigest()[:24],
                "status": "closed",
            },
        ]
        calls = []
        with (
            patch.object(triage.beads, "issues", return_value=rows),
            patch.object(
                triage.beads,
                "call",
                side_effect=lambda root, *args: calls.append(args) or {},
            ),
        ):
            result = triage.ingest_findings(
                Path("/tmp/project"),
                "pip-audit",
                [{"id": "recurs", "severity": "high", "component": "package"}],
            )

        self.assertEqual(result["tasksClosed"], 1)
        self.assertEqual(result["tasksReopened"], 1)
        self.assertIn(("reopen", "again", "--reason", "Finding observed again"), calls)
        self.assertTrue(any(call[:2] == ("close", "old") for call in calls))


if __name__ == "__main__":
    unittest.main()
