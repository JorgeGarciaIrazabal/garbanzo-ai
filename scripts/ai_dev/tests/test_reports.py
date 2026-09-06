import json
import stat
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from scripts.ai_dev import reports


class ReportTests(unittest.TestCase):
    def test_incremental_page_passes_tuple_cursor_and_preserves_metadata(self):
        seen = []
        payload = [
            {"id": "r1", "updated_at": "2026-09-05T10:00:00+00:00", "metadata": {"trace": "x"}}
        ]

        def runner(command):
            seen.append(command)
            return json.dumps(payload)

        rows = reports.fetch_page(
            Path("helper"), cursor=reports.Cursor("2026-09-04T00:00:00+00:00", "old"), runner=runner
        )
        self.assertEqual(rows[0]["metadata"], {"trace": "x"})
        self.assertIn("--after-updated", seen[0])
        self.assertIn("--after-id", seen[0])

    def test_private_evidence_permissions_and_public_redaction(self):
        row = {
            "id": "abc",
            "description": "Email jane@example.com conversation 123e4567-e89b-12d3-a456-426614174000",
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = reports.write_private_evidence(Path(temporary), [row])
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
            reports.write_private_evidence(Path(temporary), [{"id": "second"}])
            self.assertEqual(len(json.loads(path.read_text())), 2)
        public = reports.sanitized_summary(row, "key", "chat", "v1")
        self.assertNotIn("jane@example.com", public["summary"])
        self.assertNotIn("conversation_id", public)

    def test_targeted_private_artifact_keeps_diagnostics_out_of_result(self):
        row = {
            "id": "report-1",
            "description": "private prompt",
            "metadata": {"trace": "private trace"},
        }
        with tempfile.TemporaryDirectory() as temporary:
            path = reports.private_report_artifact(Path(temporary), row)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(json.loads(path.read_text()), row)
            self.assertNotIn("report-1", path.name)

    def test_show_returns_sanitized_summary_and_private_artifact_path(self):
        row = {
            "id": "report-1",
            "type": "bug",
            "status": "open",
            "description": "private prompt",
            "metadata": {"component": "chat", "release": "v1.2.3"},
            "source": "user",
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            reports.write_private_evidence(root, [row])
            result = reports.handle(SimpleNamespace(root=root, action="show", id="report-1"))
            artifact = Path(result["private_artifact"])

            self.assertTrue(artifact.is_file())
            self.assertEqual(result["report"]["source_id"], "report-1")
            self.assertNotIn("private prompt", json.dumps(result))

    def test_beads_mapping_is_idempotent_by_stable_external_ref(self):
        calls = []

        def runner(command):
            calls.append(command)
            if command[1] == "list":
                return '[{"id":"bd-7","external_ref":"garbanzo-report:report-7","description":"stale"}]'
            return '{"id":"bd-7"}'

        task = reports.ensure_beads_task(
            {"id": "report-7", "title": "Crash"}, {"summary": "safe"}, runner=runner
        )
        self.assertEqual(task, "bd-7")
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[1][1], "update")
        self.assertEqual(calls[0][1:5], ["list", "--all", "--limit", "0"])

    def test_status_update_uses_compare_and_set(self):
        row = {
            "id": "r",
            "status": "open",
            "updated_at": "2026-09-05T10:00:00+00:00",
            "version": "42",
        }
        seen = []

        def runner(command):
            seen.append(command)
            return '{"id":"r","status":"in_progress"}'

        updated = reports.set_status(Path("helper"), row, "in_progress", runner=runner)
        self.assertEqual(updated["status"], "in_progress")
        self.assertEqual(seen[0][-3:], ["open", row["updated_at"], "42"])
        with self.assertRaises(reports.ReportError):
            reports.set_status(Path("helper"), row, "closed", runner=runner)

        def conflict(command):
            raise reports.ReportError("report changed concurrently")

        with self.assertRaisesRegex(reports.ReportError, "concurrently"):
            reports.set_status(Path("helper"), row, "in_progress", runner=conflict)

    def test_beads_create_retry_finds_task_without_duplicate(self):
        calls = []

        def runner(command):
            calls.append(command)
            list_calls = sum(call[1] == "list" for call in calls)
            if command[1] == "list":
                return (
                    "[]"
                    if list_calls == 1
                    else '[{"id":"bd-race","external_ref":"garbanzo-report:r"}]'
                )
            raise reports.ReportError("external ref already exists")

        task = reports.ensure_beads_task({"id": "r"}, {"summary": "safe"}, runner=runner)
        self.assertEqual(task, "bd-race")
        self.assertEqual(sum(call[1] == "create" for call in calls), 1)

    def test_close_requires_ancestry_and_behavior_verification(self):
        def ancestor(fix, deployed):
            return (fix, deployed) == ("fix", "deployed")

        self.assertTrue(
            reports.can_close(
                fix_revision="fix",
                deployed_revision="deployed",
                is_ancestor=ancestor,
                behavior_verified=True,
            )
        )
        self.assertFalse(
            reports.can_close(
                fix_revision="fix",
                deployed_revision="deployed",
                is_ancestor=ancestor,
                behavior_verified=False,
            )
        )

    def test_persisted_cursor_uses_overlap_for_timestamp_regressions(self):
        cursor = reports.Cursor("2026-09-05T10:00:00+00:00", "123e4567-e89b-12d3-a456-426614174000")
        overlapped = reports.overlap_cursor(cursor)
        self.assertEqual(overlapped.updated_at, "2026-09-05T09:55:00+00:00")
        self.assertEqual(overlapped.report_id, "00000000-0000-0000-0000-000000000000")

    def test_sync_maps_older_saved_evidence_before_advancing_cursor(self):
        old = {"id": "old", "updated_at": "2026-01-01T00:00:00+00:00"}
        new = {"id": "new", "updated_at": "2026-09-05T00:00:00+00:00"}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            reports.write_private_evidence(root, [old])
            with (
                mock.patch.object(reports, "fetch_page", return_value=[new]),
                mock.patch.object(reports.beads, "issues", return_value=[]),
                mock.patch.object(
                    reports.beads, "call", side_effect=reports.WorkflowError("bd unavailable")
                ) as create,
                self.assertRaises(reports.WorkflowError),
            ):
                reports._sync(root)
            self.assertIn("Production report old", [str(value) for value in create.call_args.args])
            self.assertFalse((root / ".ai/local/reports-cursor.json").exists())

    def test_verification_artifact_is_bound_to_report_and_runtime_revision(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            spec = root / "scripts/ai_checks/report.json"
            spec.parent.mkdir(parents=True)
            spec.write_text('{"report_id":"report-1"}')

            def command_runner(argv):
                return "a" * 40 if argv == ["just", "ai-prod-revision"] else "passed\n"

            command = "just ai-prod-behavior --spec scripts/ai_checks/report.json --report report-1"
            with (
                mock.patch.object(reports, "run", return_value="a" * 40),
                mock.patch("scripts.ai_dev.behavior.load_spec", return_value={}),
            ):
                reports.verify_report(
                    root,
                    "report-1",
                    "a" * 40,
                    [command],
                    runner=command_runner,
                )
            self.assertTrue(reports.verified_manifest(root, "report-1", "a" * 40))
            self.assertFalse(reports.verified_manifest(root, "report-2", "a" * 40))
            self.assertFalse(reports.verified_manifest(root, "report-1", "b" * 40))
            path = reports._verification_path(root, "report-1")
            forged = json.loads(path.read_text())
            forged["runtime_revision"] = "b" * 40
            path.write_text(json.dumps(forged))
            self.assertFalse(reports.verified_manifest(root, "report-1", "a" * 40))
            with (
                mock.patch.object(reports, "run", return_value="a" * 40),
                mock.patch("scripts.ai_dev.behavior.load_spec", return_value={}),
            ):
                reports.verify_report(
                    root,
                    "report-1",
                    "a" * 40,
                    [command],
                    runner=command_runner,
                )
            spec.write_text("tampered")
            self.assertFalse(reports.verified_manifest(root, "report-1", "a" * 40))
            spec.write_text('{"report_id":"report-1"}')
            log_path = next(path.parent.glob("*.log"))
            log_path.write_text("tampered")
            self.assertFalse(reports.verified_manifest(root, "report-1", "a" * 40))

    def test_verification_rejects_health_as_behavior_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with (
                mock.patch.object(reports, "run", return_value="a" * 40),
                self.assertRaisesRegex(reports.WorkflowError, "ai-prod-behavior"),
            ):
                reports.verify_report(
                    root,
                    "report-1",
                    "a" * 40,
                    ["just deploy-status"],
                    runner=lambda argv: "a" * 40,
                )


if __name__ == "__main__":
    unittest.main()
