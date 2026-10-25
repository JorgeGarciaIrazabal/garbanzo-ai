import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.ai_dev import releases
from scripts.ai_dev.common import run as common_run


class ReleaseTests(unittest.TestCase):
    def test_changelog_codex_model_is_pinned_to_luna(self):
        self.root.joinpath("CHANGELOG.md").write_text("# Changelog\n")
        output = self.root / ".ai/local/release-notes.txt"
        original_run = subprocess.run

        def codex(argv, **kwargs):
            if argv[0] != "codex":
                return original_run(argv, **kwargs)
            self.assertEqual(argv[argv.index("--model") + 1], "gpt-6-luna")
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text("- Luna-authored release note")
            return subprocess.CompletedProcess(argv, 0, "", "")

        with patch.dict(os.environ, {"CHANGELOG_CODEX_MODEL": "gpt-6-luna"}), patch.object(
            releases.subprocess, "run", side_effect=codex
        ):
            result = releases.changelog(self.root, "1.2.3", self.source)

        self.assertEqual(result["method"], "codex")
        self.assertIn("Luna-authored release note", (self.root / "CHANGELOG.md").read_text())

    def test_changelog_rejects_conflicting_model_override(self):
        path = self.root / "CHANGELOG.md"
        path.write_text("# Changelog\n")
        with patch.dict(os.environ, {"CHANGELOG_CODEX_MODEL": "gpt-6.1-sol"}):
            with self.assertRaisesRegex(ValueError, "pinned to gpt-6-luna"):
                releases.changelog(self.root, "1.2.3", self.source)
        self.assertEqual(path.read_text(), "# Changelog\n")

    def test_deploy_builds_android_before_replacing_production(self):
        script = Path(__file__).resolve().parents[3] / "scripts/deploy.sh"
        content = script.read_text()
        self.assertLess(
            content.index('step "Building Android APK'),
            content.index('step "Starting prod stack"'),
        )

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=self.root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "test@example.com"], cwd=self.root, check=True
        )
        subprocess.run(["git", "config", "user.name", "Test"], cwd=self.root, check=True)
        (self.root / "file").write_text("source\n")
        subprocess.run(["git", "add", "file"], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "source"], cwd=self.root, check=True)
        self.source = common_run(self.root, ["git", "rev-parse", "HEAD"]).strip()
        (self.root / "file").write_text("release\n")
        subprocess.run(["git", "commit", "-qam", "release"], cwd=self.root, check=True)
        self.release = common_run(self.root, ["git", "rev-parse", "HEAD"]).strip()

    def tearDown(self):
        self.temporary.cleanup()

    def runtime(self, revision):
        def execute(root, argv, timeout=60, **kwargs):
            if argv == ["just", "ai-prod-revision"]:
                return revision + "\n"
            return common_run(root, argv, timeout, **kwargs)

        return execute

    def test_evidence_requires_exact_runtime_source(self):
        with (
            patch.object(releases, "run", side_effect=self.runtime(self.release)),
            self.assertRaisesRegex(ValueError, "production runs"),
        ):
            releases.deployment_evidence(self.root, "1.2.3", self.source, self.release)

    def test_evidence_accepts_release_descendant_and_exact_runtime(self):
        with patch.object(releases, "run", side_effect=self.runtime(self.source)):
            evidence = releases.deployment_evidence(self.root, "1.2.3", self.source, self.release)

        self.assertEqual(evidence["source_revision"], self.source)
        self.assertEqual(evidence["release_revision"], self.release)
        self.assertEqual(evidence["runtime_revision"], self.source)
        self.assertEqual(evidence["behavior_verification"], "pending")

    def test_evidence_rejects_release_that_predates_source(self):
        with (
            patch.object(releases, "run", side_effect=self.runtime(self.release)),
            self.assertRaisesRegex(ValueError, "does not contain"),
        ):
            releases.deployment_evidence(self.root, "1.2.3", self.release, self.source)


if __name__ == "__main__":
    unittest.main()
