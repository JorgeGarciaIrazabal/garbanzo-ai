import json
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from scripts.ai_dev import setup
from scripts.ai_dev.common import WorkflowError


class SetupTests(unittest.TestCase):
    @staticmethod
    def _write_catalog(root: Path, models: list[dict]) -> None:
        path = root / ".ai/local/models.json"
        path.parent.mkdir(parents=True)
        path.write_text(
            json.dumps({"refreshedAt": datetime.now(UTC).isoformat(), "models": models})
        )

    def test_doctor_reports_unavailable_beads_graph_without_crashing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / ".codex/config.toml"
            config.parent.mkdir(parents=True)
            config.write_text('model = "gpt-6-astra"\n')
            with (
                patch.object(setup.shutil, "which", return_value="/tool"),
                patch.object(setup, "run", return_value="1.0"),
                patch.object(setup.beads, "issues", side_effect=WorkflowError("offline")),
            ):
                result = setup.doctor(SimpleNamespace(root=root))

        graph = next(row for row in result["checks"] if row["name"] == "beads-task-graph")
        self.assertFalse(graph["ok"])
        self.assertFalse(result["ok"])

    def test_guided_inspect_is_local_by_default(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            args = SimpleNamespace(root=root, full=False, inspect=True, prompt=[])
            with (
                patch.object(setup.reports, "sync") as sync,
                patch.object(setup.capacity, "handle") as capacity,
            ):
                result = setup.guided(args)

        self.assertEqual(result, {"status": "local"})
        sync.assert_not_called()
        capacity.assert_not_called()

    def test_guided_full_inspect_collects_and_preserves_failures(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            args = SimpleNamespace(root=root, full=True, inspect=True, prompt=[])
            with (
                patch.object(setup.reports, "sync", side_effect=OSError("reports offline")),
                patch.object(
                    setup.capacity,
                    "handle",
                    side_effect=RuntimeError("capacity unavailable"),
                ),
            ):
                result = setup.guided(args)

        self.assertEqual(
            result,
            {
                "collection_failure": "reports offline",
                "capacity_failure": "capacity unavailable",
            },
        )

    def test_guided_launches_selected_cached_model_and_effort(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._write_catalog(
                root,
                [
                    {
                        "id": "gpt-5.6-terra",
                        "supportedReasoningEfforts": [{"reasoningEffort": "medium"}],
                    }
                ],
            )
            args = SimpleNamespace(
                root=root,
                full=False,
                inspect=False,
                model="gpt-5.6-terra",
                effort="medium",
                prompt=["Fix", "it"],
            )
            with patch.object(setup.subprocess, "call", return_value=0) as call:
                result = setup.guided(args)

        self.assertEqual(result, {"status": "session_ended"})
        argv = call.call_args.args[0]
        self.assertEqual(
            argv,
            [
                "codex",
                "-C",
                str(root),
                "-m",
                "gpt-5.6-terra",
                "-c",
                'model_reasoning_effort="medium"',
                "Fix it",
            ],
        )

    def test_guided_rejects_model_missing_from_cached_catalog(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._write_catalog(root, [{"id": "gpt-6-astra"}])

            with self.assertRaisesRegex(WorkflowError, "not in the cached account catalog"):
                setup.guided_route(root, model="gpt-5.6-terra", effort="medium")

    def test_guided_rejects_stale_model_catalog(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._write_catalog(root, [{"id": "gpt-6-astra"}])
            path = root / ".ai/local/models.json"
            catalog = json.loads(path.read_text())
            catalog["refreshedAt"] = "2000-01-01T00:00:00+00:00"
            path.write_text(json.dumps(catalog))

            with self.assertRaisesRegex(WorkflowError, "missing or stale"):
                setup.guided_route(root, model="gpt-6-astra", effort="medium")

    def test_guided_rejects_unsupported_reasoning_effort(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._write_catalog(
                root,
                [
                    {
                        "id": "gpt-5.6-terra",
                        "supportedReasoningEfforts": [{"reasoningEffort": "low"}],
                    }
                ],
            )

            with self.assertRaisesRegex(WorkflowError, "is not supported"):
                setup.guided_route(root, model="gpt-5.6-terra", effort="medium")

    def test_guided_rejects_missing_or_malformed_reasoning_effort_metadata(self):
        for metadata in (None, [], [{}]):
            with self.subTest(metadata=metadata), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self._write_catalog(
                    root,
                    [{"id": "gpt-5.6-terra", "supportedReasoningEfforts": metadata}],
                )

                with self.assertRaisesRegex(WorkflowError, "missing or malformed"):
                    setup.guided_route(root, model="gpt-5.6-terra", effort="medium")


if __name__ == "__main__":
    unittest.main()
