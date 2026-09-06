import tempfile
import unittest
from pathlib import Path

from scripts.ai_dev import audits
from scripts.ai_dev.common import WorkflowError


class AuditTests(unittest.TestCase):
    def test_secret_identity_uses_stable_relative_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = [
                {
                    "RuleID": "generic-api-key",
                    "File": str(root / "config/example.env"),
                    "StartLine": 4,
                }
            ]
            first = audits.secret_findings(payload, root)
            second = audits.secret_findings(payload, root)

        self.assertEqual(first, second)
        self.assertEqual(first[0]["component"], "config/example.env")

    def test_dependency_identity_includes_package_and_deduplicates_aliases(self):
        payload = {
            "dependencies": [
                {
                    "name": "first",
                    "vulns": [{"id": "CVE-1"}, {"id": "CVE-1"}],
                },
                {"name": "second", "vulns": [{"id": "CVE-1"}]},
            ]
        }

        findings = audits.dependency_findings(payload)

        self.assertEqual(len(findings), 2)
        self.assertNotEqual(findings[0]["id"], findings[1]["id"])
        self.assertEqual({row["component"] for row in findings}, {"first", "second"})

    def test_malformed_valid_json_cannot_be_treated_as_clean_scan(self):
        for payload in ({}, {"dependencies": [{}]}, {"dependencies": "none"}):
            with self.subTest(payload=payload), self.assertRaises(WorkflowError):
                audits.dependency_findings(payload)

    def test_explicitly_skipped_dependency_stays_actionable(self):
        findings = audits.dependency_findings(
            {"dependencies": [{"name": "torch", "skip_reason": "not available from PyPI"}]}
        )
        self.assertEqual(findings[0]["component"], "torch")
        self.assertEqual(findings[0]["severity"], "unknown")

    def test_dart_direct_updates_and_advisories_become_findings(self):
        payload = {
            "packages": [
                {
                    "package": "direct_package",
                    "kind": "direct",
                    "isCurrentAffectedByAdvisory": False,
                    "current": {"version": "1.0.0"},
                    "resolvable": {"version": "1.1.0"},
                },
                {
                    "package": "transitive_package",
                    "kind": "transitive",
                    "isCurrentAffectedByAdvisory": True,
                    "current": {"version": "1.0.0"},
                    "resolvable": {"version": "1.1.0"},
                },
            ]
        }

        findings = audits.dart_findings(payload)

        self.assertEqual(len(findings), 2)
        self.assertEqual(
            {row["component"] for row in findings},
            {"direct_package", "transitive_package"},
        )
        self.assertEqual({row["severity"] for row in findings}, {"low", "high"})


if __name__ == "__main__":
    unittest.main()
