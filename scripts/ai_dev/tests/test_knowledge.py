import json
import tempfile
import unittest
from pathlib import Path

from scripts.ai_dev import knowledge
from scripts.ai_dev.common import WorkflowError


class KnowledgeTests(unittest.TestCase):
    def test_refresh_rejects_unsafe_paths_from_old_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "AGENTS.md").write_text("# Guidance\n")
            manifest = root / ".ai/local/knowledge-manifest.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({"sources": {"../../outside.md": {}}}))

            with self.assertRaisesRegex(WorkflowError, "unsafe source path"):
                knowledge.refresh(root)


if __name__ == "__main__":
    unittest.main()
