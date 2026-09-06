from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.ai_dev.common import WorkflowError
from scripts.ai_dev.coordination import (
    create_assignment,
    integrate_handoff,
    record_review,
    update_assignment,
)
from scripts.ai_dev.execution import _thread_id, assign, execute, execute_batch, register, verify


class ExecutionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        for command in (
            ["git", "init", "-q", "-b", "main"],
            ["git", "config", "user.email", "test@example.com"],
            ["git", "config", "user.name", "Test"],
        ):
            subprocess.run(command, cwd=self.root, check=True)
        (self.root / "owned.txt").write_text("base\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "base"], cwd=self.root, check=True)
        model_path = self.root / ".ai" / "local" / "models.json"
        model_path.parent.mkdir(parents=True)
        model_path.write_text(
            json.dumps(
                {
                    "models": [{"id": "gpt-5.6-terra"}],
                    "promoted": ["codex:gpt-5.6-terra"],
                }
            )
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @patch("scripts.ai_dev.execution.beads.call")
    def test_assignment_uses_beads_requirements_and_pins_route(self, call) -> None:
        call.return_value = {
            "id": "task-1",
            "description": "Make the change",
            "acceptance": ["focused test passes"],
            "dependencies": [{"id": "dep-1"}],
            "updated_at": "revision-1",
        }
        result = assign(self.root, "task-1", ["owned.txt"], kind="routine")
        manifest = json.loads((self.root / ".ai/local/workers/task-1/.assignment.json").read_text())
        self.assertEqual(manifest["requirements"], "Make the change")
        self.assertEqual(manifest["model"], "gpt-5.6-terra")
        self.assertEqual(manifest["dependencies"], ["dep-1"])
        self.assertEqual(result["model"]["model"], "gpt-5.6-terra")

    def test_verification_rejects_commands_outside_just(self) -> None:
        with self.assertRaisesRegex(WorkflowError, "allowed just recipe"):
            verify(self.root, "task-1", ["python test.py"])

    def test_verification_rejects_stateful_just_recipe(self) -> None:
        with self.assertRaisesRegex(WorkflowError, "allowed just recipe"):
            verify(self.root, "task-1", ["just deploy"])

    def test_batch_rejects_duplicate_assignment(self) -> None:
        with self.assertRaisesRegex(WorkflowError, "unique"):
            execute_batch(self.root, ["task-1", "task-1"], timeout=1)

    def test_thread_id_is_recovered_for_native_resume(self) -> None:
        events = self.root / "events.jsonl"
        events.write_text('{"type":"other"}\n{"type":"thread.started","thread_id":"abc"}\n')
        self.assertEqual(_thread_id(events), "abc")

    def test_register_exposes_delivery_commands(self) -> None:
        parser = argparse.ArgumentParser()
        commands = parser.add_subparsers(dest="command", required=True)
        register(commands)
        args = parser.parse_args(["run", "assign", "task-1", "--owned", "owned.txt"])
        self.assertEqual((args.command, args.action, args.task_id), ("run", "assign", "task-1"))
        self.assertEqual(parser.parse_args(["batch", "one", "two"]).task_ids, ["one", "two"])
        with self.assertRaises(SystemExit):
            parser.parse_args(["run", "review", "task-1", "--approved"])

    def test_mocked_worker_to_verified_reviewed_integration(self) -> None:
        assignment = create_assignment(
            self.root,
            "flow",
            requirements="change owned",
            owned_files=["owned.txt"],
            acceptance=["test passes"],
        )
        update_assignment(
            self.root,
            "flow",
            model="gpt-5.6-terra",
            reasoning_effort="medium",
        )

        class Worker:
            pid = os.getpid()
            returncode = 0

            def __init__(self, command, *, workspace, event_stream, **kwargs):
                del kwargs
                Path(workspace, "owned.txt").write_text("worker\n")
                output = Path(command[command.index("--output-last-message") + 1])
                output.write_text("implemented")
                event_stream.write('{"type":"thread.started","thread_id":"worker-thread"}\n')

            def wait(self, timeout=None):
                del timeout
                return 0

        with patch("scripts.ai_dev.execution._spawn_worker", Worker):
            result = execute(self.root, "flow", timeout=1)
        self.assertEqual(result["status"], "ready_for_verification")
        completed = subprocess.CompletedProcess(["just", "check"], 0, "passed", "")
        with patch("scripts.ai_dev.execution._run_verification", return_value=completed):
            self.assertTrue(verify(self.root, "flow", ["just check"])["passed"])
        record_review(
            self.root,
            "flow",
            reviewer="review-thread",
            reviewer_model="gpt-5.6-sol",
            approved=True,
            summary="approved",
        )
        files = integrate_handoff(
            self.root,
            "flow",
            requirement_revision=assignment.requirement_revision,
        )
        self.assertEqual(files, ["owned.txt"])
        self.assertEqual((self.root / "owned.txt").read_text(), "worker\n")


if __name__ == "__main__":
    unittest.main()
