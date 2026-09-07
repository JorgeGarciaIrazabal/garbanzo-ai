import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from scripts.ai_dev import beads


def sample_rows():
    return [
        {
            "id": "feature-old",
            "title": "Conversation export",
            "status": "open",
            "priority": 2,
            "updated_at": "2026-09-05T10:00:00Z",
            "dependency_count": 0,
            "external_ref": "backlog:feature-old",
            "labels": ["backlog"],
        },
        {
            "id": "feature-new",
            "title": "Conversation sharing",
            "status": "open",
            "priority": 2,
            "updated_at": "2026-09-06T10:00:00Z",
            "dependency_count": 0,
            "external_ref": "backlog:feature-new",
            "labels": ["backlog"],
        },
        {
            "id": "feature-blocked",
            "title": "Blocked feature",
            "status": "open",
            "priority": 1,
            "updated_at": "2026-09-06T11:00:00Z",
            "dependency_count": 2,
            "labels": ["backlog"],
        },
        {
            "id": "in-progress",
            "title": "Threads (in progress)",
            "status": "in_progress",
            "priority": 2,
            "updated_at": "2026-09-06T12:00:00Z",
            "dependency_count": 0,
            "labels": ["backlog"],
        },
        {
            "id": "dependency-completed",
            "title": "Task with completed dependencies",
            "status": "open",
            "priority": 2,
            "updated_at": "2026-09-06T15:00:00Z",
            "dependency_count": 1,
            "labels": ["backlog"],
        },
        {
            "id": "report",
            "title": "Production report 123",
            "status": "open",
            "priority": 2,
            "updated_at": "2026-09-06T13:00:00Z",
            "dependency_count": 0,
            "external_ref": "garbanzo-report:123",
            "labels": ["report"],
        },
        {
            "id": "finding",
            "title": "dart-pub finding abc",
            "status": "open",
            "priority": 3,
            "updated_at": "2026-09-06T14:00:00Z",
            "dependency_count": 0,
            "external_ref": "finding:dart-pub:abc",
            "labels": ["finding", "dart-pub"],
        },
        {
            "id": "closed",
            "title": "Closed task",
            "status": "closed",
            "priority": 2,
            "dependency_count": 0,
        },
    ]


class BeadsSummaryTests(unittest.TestCase):
    def test_summary_groups_open_tasks_and_recommends_bounded_unblocked_work(self):
        result = beads.summarize(
            sample_rows(),
            ready_ids={"feature-old", "feature-new", "dependency-completed"},
            limit=2,
        )

        self.assertEqual(result["open_total"], 7)
        self.assertEqual(result["blocked_total"], 1)
        self.assertEqual(result["by_priority"], {"P1": 1, "P2": 5, "P3": 1})
        self.assertEqual(
            result["by_group"],
            {
                "in_progress": 1,
                "feature_or_infrastructure": 4,
                "production_report": 1,
                "dependency_finding": 1,
            },
        )
        self.assertEqual(
            [task["id"] for task in result["recommended_tasks"]],
            ["dependency-completed", "feature-new"],
        )
        self.assertEqual(
            {task["group"] for task in result["recommended_tasks"]},
            {"feature_or_infrastructure"},
        )

    def test_summary_can_explicitly_include_reports_and_findings(self):
        result = beads.summarize(
            sample_rows(),
            ready_ids={"feature-old", "feature-new", "report", "finding"},
            limit=4,
            include_reports=True,
            include_findings=True,
        )

        self.assertEqual(
            [task["id"] for task in result["recommended_tasks"]],
            ["feature-new", "feature-old", "report", "finding"],
        )

    def test_summary_excludes_non_actionable_statuses(self):
        rows = sample_rows()
        rows.extend(
            [
                {"id": "blocked", "title": "Blocked status", "status": "blocked", "priority": 1},
                {"id": "deferred", "title": "Deferred status", "status": "deferred", "priority": 1},
            ]
        )

        result = beads.summarize(rows)

        self.assertNotIn("blocked", result["by_priority"])
        self.assertNotIn("deferred", result["by_priority"])
        self.assertNotIn(
            {"id": "blocked"},
            [dict(task, id=task["id"]) for task in result["recommended_tasks"]],
        )

    def test_summary_groups_imported_titles_and_status_as_in_progress(self):
        result = beads.summarize(
            [
                {"id": "status", "title": "Active task", "status": "in_progress"},
                {"id": "title", "title": "Legacy task (in progress)", "status": "open"},
            ],
            ready_ids=set(),
        )

        self.assertEqual(result["by_group"]["in_progress"], 2)
        self.assertEqual(result["recommended_tasks"], [])

    def test_ready_fetches_every_ready_task(self):
        with mock.patch.object(beads, "call", return_value=[]) as call:
            result = beads.ready(Path("root"))

        call.assert_called_once_with(Path("root"), "ready", "--limit", "0")
        self.assertEqual(result, [])

    def test_summary_prioritizes_explicitly_included_urgent_groups(self):
        result = beads.summarize(
            [
                {
                    "id": "feature-new",
                    "title": "Feature new",
                    "status": "open",
                    "priority": 2,
                    "updated_at": "2026-09-06T10:00:00Z",
                    "dependency_count": 0,
                },
                {
                    "id": "feature-old",
                    "title": "Feature old",
                    "status": "open",
                    "priority": 2,
                    "updated_at": "2026-09-05T10:00:00Z",
                    "dependency_count": 0,
                },
                {
                    "id": "urgent-report",
                    "title": "Production report urgent",
                    "status": "open",
                    "priority": 0,
                    "updated_at": "2026-09-01T10:00:00Z",
                    "dependency_count": 0,
                    "external_ref": "garbanzo-report:urgent",
                    "labels": ["report"],
                },
            ],
            ready_ids={"feature-new", "feature-old", "urgent-report"},
            limit=2,
            include_reports=True,
        )

        self.assertEqual(
            [task["id"] for task in result["recommended_tasks"]],
            ["urgent-report", "feature-new"],
        )

    def test_summary_rejects_non_positive_limits(self):
        with self.assertRaisesRegex(ValueError, "at least 1"):
            beads.summarize(sample_rows(), limit=0)

    def test_summary_action_queries_beads_ready_ids(self):
        with tempfile.TemporaryDirectory() as temporary:
            args = SimpleNamespace(
                root=Path(temporary),
                action="summary",
                limit=2,
                include_reports=False,
                include_findings=False,
            )
            with (
                mock.patch.object(beads, "issues", return_value=sample_rows()) as issues,
                mock.patch.object(
                    beads,
                    "ready",
                    return_value=[{"id": "dependency-completed", "status": "open"}],
                ) as ready,
            ):
                result = beads.handle(args)

            issues.assert_called_once_with(Path(temporary))
            ready.assert_called_once_with(Path(temporary))
            self.assertEqual(result["open_total"], 7)
            self.assertEqual(
                [task["id"] for task in result["recommended_tasks"]],
                ["dependency-completed"],
            )


if __name__ == "__main__":
    unittest.main()
