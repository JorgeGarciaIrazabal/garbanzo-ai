import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts.ai_dev import behavior


class Response:
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def read(self, limit):
        return b'{"items":[{"state":"ready"}]}'


class BehaviorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "test@example.com"], cwd=self.root, check=True
        )
        subprocess.run(["git", "config", "user.name", "Test"], cwd=self.root, check=True)
        (self.root / "scripts/ai_checks").mkdir(parents=True)

    def tearDown(self):
        self.temporary.cleanup()

    def spec(self, value):
        path = self.root / "scripts/ai_checks/report.json"
        path.write_text(json.dumps(value))
        subprocess.run(["git", "add", path], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "spec"], cwd=self.root, check=True)
        return path

    def test_executes_bounded_get_and_asserts_response(self):
        path = self.spec(
            {
                "report_id": "r1",
                "method": "GET",
                "path": "/api/v1/items",
                "expect": {"status": 200, "json_equals": {"items.0.state": "ready"}},
            }
        )
        seen = []

        def opener(request, timeout):
            seen.append((request, timeout))
            return Response()

        with mock.patch.dict(os.environ, {"AI_DEPLOYED_BASE_URL": behavior.DEFAULT_BASE_URL}):
            result = behavior.execute(self.root, path, "r1", opener=opener)
        self.assertTrue(result["passed"])
        self.assertEqual(seen[0][0].method, "GET")
        self.assertEqual(seen[0][1], 20)

    def test_rejects_health_version_only_mutation_and_wrong_report(self):
        cases = [
            {"report_id": "r1", "path": "/api/v1/health", "expect": {"text_contains": ["ok"]}},
            {"report_id": "r1", "path": "/x", "expect": {"json_equals": {"version": "1"}}},
            {"report_id": "r1", "method": "POST", "path": "/x", "expect": {"text_contains": ["x"]}},
        ]
        for index, value in enumerate(cases):
            with self.subTest(index=index):
                path = self.root / f"scripts/ai_checks/rejected-{index}.json"
                path.write_text(json.dumps(value))
                subprocess.run(["git", "add", path], cwd=self.root, check=True)
                subprocess.run(["git", "commit", "-qm", f"case {index}"], cwd=self.root, check=True)
                with self.assertRaises(behavior.WorkflowError):
                    behavior.load_spec(self.root, path, "r1")
        valid = self.spec({"report_id": "r1", "path": "/x", "expect": {"text_contains": ["x"]}})
        with self.assertRaisesRegex(behavior.WorkflowError, "report_id"):
            behavior.load_spec(self.root, valid, "r2")


if __name__ == "__main__":
    unittest.main()
