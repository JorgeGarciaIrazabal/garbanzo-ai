from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.ai_dev.coordination import (
    CoordinationError,
    _workspace_changes,
    add_preview_feedback,
    create_assignment,
    create_preview,
    integrate_handoff,
    prepare_handoff,
    record_review,
    record_session,
    record_verification,
    resume_session,
    stop_session,
)


class CoordinationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.git_run("git", "init", "-q", "-b", "main")
        self.git_run("git", "config", "user.email", "test@example.com")
        self.git_run("git", "config", "user.name", "Test")
        (self.root / "owned.txt").write_text("base\n")
        (self.root / "other.txt").write_text("keep\n")
        os.symlink("other.txt", self.root / "safe-link")
        self.git_run("git", "add", ".")
        self.git_run("git", "commit", "-qm", "base")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def git_run(self, *command: str) -> None:
        subprocess.run(command, cwd=self.root, check=True)

    def assignment(self, task_id: str = "task-1"):
        return create_assignment(
            self.root,
            task_id,
            requirements="change owned",
            owned_files=["owned.txt"],
            dependencies=["dep-1"],
            acceptance=["contains worker"],
        )

    def approve(self, task_id: str) -> None:
        record_verification(
            self.root, task_id, command=["just", "check"], passed=True, summary="passed"
        )
        record_review(
            self.root,
            task_id,
            reviewer="independent-sol",
            reviewer_model="gpt-5.6-sol",
            approved=True,
            summary="approved",
        )

    def test_assignment_is_private_archive_without_git_metadata(self) -> None:
        assignment = self.assignment()
        self.assertEqual((assignment.workspace / "owned.txt").read_text(), "base\n")
        self.assertEqual((assignment.workspace / "safe-link").read_text(), "keep\n")
        self.assertFalse((assignment.workspace / ".git").exists())
        self.assertEqual(self.root.joinpath(".ai/local").stat().st_mode & 0o777, 0o700)

    def test_handoff_integrates_only_owned_file_and_preserves_unrelated_edit(self) -> None:
        assignment = self.assignment()
        (assignment.workspace / "owned.txt").write_text("worker\n")
        (self.root / "other.txt").write_text("local edit\n")
        prepare_handoff(self.root, assignment.task_id)
        self.approve(assignment.task_id)
        changed = integrate_handoff(
            self.root,
            assignment.task_id,
            requirement_revision=assignment.requirement_revision,
            completed_dependencies=["dep-1"],
        )
        self.assertEqual(changed, ["owned.txt"])
        self.assertEqual((self.root / "owned.txt").read_text(), "worker\n")
        self.assertEqual((self.root / "other.txt").read_text(), "local edit\n")
        integrated_revision = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=self.root, text=True
        ).strip()
        next_assignment = create_assignment(
            self.root,
            "task-2",
            requirements="next",
            owned_files=["owned.txt"],
        )
        self.assertEqual(next_assignment.base_revision, integrated_revision)
        self.assertEqual((next_assignment.workspace / "owned.txt").read_text(), "worker\n")

    def test_rejects_unowned_worker_output(self) -> None:
        assignment = self.assignment()
        (assignment.workspace / "surprise.txt").write_text("no\n")
        with self.assertRaisesRegex(CoordinationError, "unowned"):
            prepare_handoff(self.root, assignment.task_id)

    def test_worker_diff_does_not_depend_on_parent_git_discovery(self) -> None:
        assignment = self.assignment()
        isolated = self.root.parent / f"isolated-{self.root.name}"
        try:
            shutil.copytree(assignment.workspace, isolated, symlinks=True)
            (isolated / "owned.txt").write_text("worker\n")
            self.assertEqual(
                _workspace_changes(self.root, isolated, assignment.base_revision), {"owned.txt"}
            )
        finally:
            shutil.rmtree(isolated, ignore_errors=True)

    def test_rejects_stale_requirement_and_base(self) -> None:
        assignment = self.assignment()
        (assignment.workspace / "owned.txt").write_text("worker\n")
        prepare_handoff(self.root, assignment.task_id)
        self.approve(assignment.task_id)
        with self.assertRaisesRegex(CoordinationError, "requirements changed"):
            integrate_handoff(self.root, assignment.task_id, requirement_revision="stale")
        (self.root / "owned.txt").write_text("new base\n")
        self.git_run("git", "add", "owned.txt")
        self.git_run("git", "commit", "-qm", "advance")
        with self.assertRaisesRegex(CoordinationError, "base content changed"):
            integrate_handoff(
                self.root,
                assignment.task_id,
                requirement_revision=assignment.requirement_revision,
                completed_dependencies=["dep-1"],
            )

    def test_integration_requires_dependencies_verification_and_review(self) -> None:
        assignment = self.assignment()
        (assignment.workspace / "owned.txt").write_text("worker\n")
        prepare_handoff(self.root, assignment.task_id)
        with self.assertRaisesRegex(CoordinationError, "dependencies incomplete"):
            integrate_handoff(
                self.root, assignment.task_id, requirement_revision=assignment.requirement_revision
            )
        with self.assertRaisesRegex(CoordinationError, "verification"):
            integrate_handoff(
                self.root,
                assignment.task_id,
                requirement_revision=assignment.requirement_revision,
                completed_dependencies=["dep-1"],
            )

    def test_recollect_invalidates_old_verification_and_review(self) -> None:
        assignment = self.assignment()
        (assignment.workspace / "owned.txt").write_text("first\n")
        prepare_handoff(self.root, assignment.task_id)
        self.approve(assignment.task_id)
        (assignment.workspace / "owned.txt").write_text("second\n")
        prepare_handoff(self.root, assignment.task_id)
        with self.assertRaisesRegex(CoordinationError, "verification"):
            integrate_handoff(
                self.root,
                assignment.task_id,
                requirement_revision=assignment.requirement_revision,
                completed_dependencies=["dep-1"],
            )

    def test_generated_build_outputs_do_not_violate_ownership(self) -> None:
        assignment = self.assignment()
        generated = assignment.workspace / "build" / "cache"
        generated.mkdir(parents=True)
        (generated / "artifact").write_text("generated\n")
        (assignment.workspace / "owned.txt").write_text("worker\n")
        self.assertTrue(prepare_handoff(self.root, assignment.task_id).is_file())
        record_verification(
            self.root,
            assignment.task_id,
            command=["just", "check"],
            passed=True,
            summary="passed",
        )
        with self.assertRaisesRegex(CoordinationError, "review"):
            integrate_handoff(
                self.root,
                assignment.task_id,
                requirement_revision=assignment.requirement_revision,
                completed_dependencies=["dep-1"],
            )

    def test_rejects_paths_and_symlink_outputs(self) -> None:
        with self.assertRaisesRegex(CoordinationError, "unsafe"):
            create_assignment(self.root, "bad", requirements="x", owned_files=["../outside"])
        assignment = create_assignment(
            self.root, "link", requirements="x", owned_files=["owned.txt"]
        )
        (assignment.workspace / "owned.txt").unlink()
        os.symlink("other.txt", assignment.workspace / "owned.txt")
        with self.assertRaisesRegex(CoordinationError, "symlink"):
            prepare_handoff(self.root, assignment.task_id)

    def test_preview_is_revision_stable_and_feedback_is_linked(self) -> None:
        revision = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=self.root, text=True
        ).strip()
        preview = create_preview(self.root, "demo")
        (self.root / "owned.txt").write_text("later\n")
        feedback = add_preview_feedback(self.root, "demo", "needs polish")
        metadata = json.loads((preview / "preview.json").read_text())
        self.assertEqual(metadata["source_revision"], revision)
        self.assertEqual(feedback["source_revision"], revision)
        self.assertEqual(metadata["verification"], "created_unverified")
        self.assertTrue((preview / "source.tar").is_file())
        self.assertEqual((preview / "source" / "owned.txt").read_text(), "base\n")

    def test_resume_uses_persisted_worker_cwd(self) -> None:
        workspace = self.root / "worker-cwd"
        workspace.mkdir()
        record_session(
            self.root,
            "resume-me",
            pid=None,
            command=["codex", "exec"],
            status="stopped",
            cwd=workspace,
        )

        class Process:
            pid = 12345

        with patch("scripts.ai_dev.coordination.subprocess.Popen", return_value=Process()) as popen:
            resume_session(self.root, "resume-me")
        self.assertEqual(Path(popen.call_args.kwargs["cwd"]), workspace)

    def test_stop_rejects_reused_pid_identity(self) -> None:
        record_session(self.root, "old", pid=os.getpid(), command=["codex"])
        state_path = self.root / ".ai/local/sessions/old.json"
        state = json.loads(state_path.read_text())
        state["pid_start"] = "different-process"
        state_path.write_text(json.dumps(state))
        with patch("scripts.ai_dev.coordination.os.killpg") as killpg:
            result = stop_session(self.root, "old")
        killpg.assert_not_called()
        self.assertFalse(result["alive"])


if __name__ == "__main__":
    unittest.main()
