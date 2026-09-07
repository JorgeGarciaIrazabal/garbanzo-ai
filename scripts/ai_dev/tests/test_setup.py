import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from scripts.ai_dev import setup
from scripts.ai_dev.common import WorkflowError


class SetupTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
