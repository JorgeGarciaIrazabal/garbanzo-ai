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


if __name__ == "__main__":
    unittest.main()
