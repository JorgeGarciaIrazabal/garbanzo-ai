import io
import json
import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from scripts.ai_dev import behavior


class Response:
    status = 200
    headers = {}

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

    def docx_spec(self, **overrides):
        value = {
            "report_id": "r1",
            "path": "/export/{conversation_id}",
            "path_parameters": {"conversation_id": "AI_DEPLOYED_CONVERSATION_ID"},
            "expect": {
                "headers": {"Content-Type": "application/docx"},
                "zip_xml": {
                    "word/document.xml": {
                        "paths": [".//w:p"],
                        "text_contains": ["Assistant"],
                    }
                },
            },
        }
        value.update(overrides)
        return self.spec(value)

    def zip_response(self, xml=None, **kwargs):
        body = io.BytesIO()
        with zipfile.ZipFile(body, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(
                "word/document.xml",
                xml
                or '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                "<w:p><w:t>Assistant</w:t></w:p></w:document>",
            )
        response = Response()
        response.headers = {"Content-Type": "application/docx"}
        response.read = lambda limit: body.getvalue()[:limit]
        for name, value in kwargs.items():
            setattr(response, name, value)
        return response

    def test_docx_asserts_real_xml_headers_and_private_uuid(self):
        path = self.docx_spec()
        identifier = "11111111-1111-1111-1111-111111111111"
        seen = []

        def opener(request, timeout):
            seen.append(request.full_url)
            return self.zip_response()

        with mock.patch.dict(os.environ, {"AI_DEPLOYED_CONVERSATION_ID": identifier}):
            result = behavior.execute(self.root, path, "r1", opener=opener)
        self.assertTrue(result["passed"])
        self.assertIn(identifier, seen[0])
        self.assertNotIn(identifier, json.dumps(result))

    def test_docx_rejects_corruption_missing_markup_text_and_wrong_headers(self):
        path = self.docx_spec()
        bad_zip = self.zip_response(read=lambda limit: b"not a zip archive")
        cases = [
            bad_zip,
            self.zip_response("<document><p>Assistant</p></document>"),
            self.zip_response(
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                "<w:p>Other text</w:p></w:document>"
            ),
            self.zip_response("<unclosed"),
            self.zip_response(headers={"Content-Type": "text/plain"}),
            self.zip_response(read=lambda limit: b"x" * 1_000_001),
        ]
        with mock.patch.dict(
            os.environ, {"AI_DEPLOYED_CONVERSATION_ID": "11111111-1111-1111-1111-111111111111"}
        ):
            for response in cases:
                with self.subTest(response=response), self.assertRaises(behavior.WorkflowError):
                    behavior.execute(self.root, path, "r1", opener=mock.Mock(return_value=response))

    def test_rejects_empty_unknown_and_header_only_assertions(self):
        for expected in [
            {"status": 200},
            {"text_contains": []},
            {"headers": {"Content-Type": "application/docx"}},
            {"zip_xml": {"word/document.xml": {}}},
            {"zip_xml": {"word/document.xml": {"paths": [""]}}},
            {"anything": True},
        ]:
            with self.subTest(expected=expected), self.assertRaises(behavior.WorkflowError):
                behavior.load_spec(self.root, self.docx_spec(expect=expected), "r1")

    def test_rejects_private_path_values_that_can_change_the_request_target(self):
        path = self.docx_spec()
        for identifier in ["", "../health", "//example.org", "a?token=secret"]:
            with (
                mock.patch.dict(os.environ, {"AI_DEPLOYED_CONVERSATION_ID": identifier}),
                self.assertRaisesRegex(behavior.WorkflowError, "UUID"),
            ):
                behavior.execute(self.root, path, "r1", opener=mock.Mock())

    def test_zip_expansion_is_bounded(self):
        path = self.docx_spec()
        response = self.zip_response("x" * 10_000_001)
        with (
            mock.patch.dict(
                os.environ, {"AI_DEPLOYED_CONVERSATION_ID": "11111111-1111-1111-1111-111111111111"}
            ),
            self.assertRaisesRegex(behavior.WorkflowError, "bounds"),
        ):
            behavior.execute(self.root, path, "r1", opener=lambda *a, **k: response)


if __name__ == "__main__":
    unittest.main()
