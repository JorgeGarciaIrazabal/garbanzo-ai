from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.ai_dev.__main__ import _controller_modules
from scripts.ai_dev.common import WorkflowError, lock
from scripts.ai_dev.coordination import (
    create_assignment,
    integrate_handoff,
    record_review,
    update_assignment,
)
from scripts.ai_dev.execution import (
    WORKER_RECIPE_REQUIREMENTS,
    _direct_patch,
    _direct_review_prompt,
    _preflight_worker_verification,
    _thread_id,
    _verification_argv,
    assign,
    execute,
    execute_batch,
    register,
    verify,
    verify_direct,
)


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
                    "models": [{"id": "gpt-5.6-sol"}, {"id": "gpt-5.6-terra"}],
                    "promoted": ["codex:gpt-5.6-sol", "codex:gpt-5.6-terra"],
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

    def test_verification_rejects_chained_recipe(self) -> None:
        with self.assertRaisesRegex(WorkflowError, "does not accept arguments"):
            verify(self.root, "task-1", ["just check deploy"])

    def test_verification_rejects_shell_syntax_in_recipe_arguments(self) -> None:
        for command in (
            "just be-test 'tests/example.py; just deploy'",
            "just fe-test 'test/example_test.dart && just deploy'",
        ):
            with (
                self.subTest(command=command),
                self.assertRaisesRegex(WorkflowError, "safe path/test-selector characters"),
            ):
                verify(self.root, "task-1", [command])
        self.assertEqual(
            _verification_argv("just be-test tests/test_example.py::test_name"),
            ["just", "be-test", "tests/test_example.py::test_name"],
        )

    def test_direct_patch_rejects_controller_state_paths(self) -> None:
        for path in (".git", ".ai"):
            with (
                self.subTest(path=path),
                self.assertRaisesRegex(WorkflowError, "unsafe owned path"),
            ):
                _direct_patch(self.root, [path])

    def test_worker_verification_preflights_missing_recipe_dependencies(self) -> None:
        create_assignment(
            self.root,
            "missing-env",
            requirements="change owned",
            owned_files=["owned.txt"],
        )
        with (
            patch("scripts.ai_dev.execution._run_verification") as runner,
            self.assertRaisesRegex(WorkflowError, "worker verification environment is incomplete"),
        ):
            verify(self.root, "missing-env", ["just check"])
        runner.assert_not_called()

    def test_worker_recipe_dependency_map_accepts_provisioned_snapshots(self) -> None:
        _preflight_worker_verification(self.root, [["just", "ai-test"]])
        for recipe, requirements in WORKER_RECIPE_REQUIREMENTS.items():
            workspace = self.root / f"workspace-{recipe}"
            workspace.mkdir()
            with (
                self.subTest(recipe=recipe, state="missing"),
                self.assertRaisesRegex(WorkflowError, recipe),
            ):
                _preflight_worker_verification(workspace, [["just", recipe]])
            for requirement in requirements:
                marker = workspace / requirement
                marker.parent.mkdir(parents=True, exist_ok=True)
                marker.touch()
            with self.subTest(recipe=recipe, state="provisioned"):
                _preflight_worker_verification(workspace, [["just", recipe]])

    def test_direct_path_rejects_concurrent_run_before_reading_worktree(self) -> None:
        with lock(self.root, "direct"), self.assertRaisesRegex(WorkflowError, "direct is busy"):
            verify_direct(self.root, "task-1", ["owned.txt"], ["just check"])

    def test_direct_path_rejects_unsafe_task_identifier(self) -> None:
        for task_id in ("../escape", "/tmp/escape"):
            with (
                self.subTest(task_id=task_id),
                self.assertRaisesRegex(WorkflowError, "invalid task identifier"),
            ):
                verify_direct(self.root, task_id, ["owned.txt"], ["just check"])

    def test_worker_verification_rejects_unsafe_task_identifier(self) -> None:
        with self.assertRaisesRegex(WorkflowError, "invalid task identifier"):
            verify(self.root, "../../..", ["just ai-test"])

    def test_batch_rejects_duplicate_assignment(self) -> None:
        with self.assertRaisesRegex(WorkflowError, "unique"):
            execute_batch(self.root, ["task-1", "task-1"], timeout=1)

    def test_thread_id_is_recovered_for_native_resume(self) -> None:
        events = self.root / "events.jsonl"
        events.write_text('{"type":"other"}\n{"type":"thread.started","thread_id":"abc"}\n')
        self.assertEqual(_thread_id(events), "abc")

    def test_execution_dispatch_does_not_import_unrelated_dirty_controllers(self) -> None:
        self.assertEqual(_controller_modules(["--json", "run", "direct"]), ("execution",))
        self.assertEqual(_controller_modules(["status"]), ("execution",))
        self.assertIn("audits", _controller_modules(["audit", "dependencies"]))

    def test_direct_review_prompt_forbids_patch_execution(self) -> None:
        prompt = _direct_review_prompt("task-1", self.root / ".ai/local/direct/task-1")
        self.assertIn("Perform a static review only", prompt)
        self.assertIn("do not run tests, checks, project commands", prompt)
        self.assertIn("or any code from the patch", prompt)

    def test_register_exposes_delivery_commands(self) -> None:
        parser = argparse.ArgumentParser()
        commands = parser.add_subparsers(dest="command", required=True)
        register(commands)
        args = parser.parse_args(["run", "assign", "task-1", "--owned", "owned.txt"])
        self.assertEqual((args.command, args.action, args.task_id), ("run", "assign", "task-1"))
        self.assertEqual(parser.parse_args(["batch", "one", "two"]).task_ids, ["one", "two"])
        verify_args = parser.parse_args(
            ["run", "verify", "task-1", "--command", "just ai-test", "--command", "just ai-lint"]
        )
        self.assertEqual(verify_args.command, "run")
        self.assertEqual(verify_args.verification_commands, ["just ai-test", "just ai-lint"])
        direct_args = parser.parse_args(
            [
                "run",
                "direct",
                "task-1",
                "--owned",
                "owned.txt",
                "--command",
                "just check",
            ]
        )
        self.assertEqual((direct_args.action, direct_args.owned), ("direct", ["owned.txt"]))
        actions = commands.choices["run"]._subparsers._group_actions[0]
        verify_help = " ".join(actions.choices["verify"].format_help().split())
        self.assertIn("isolated worker snapshot", verify_help)
        self.assertIn("installed dependency markers", verify_help)
        direct_help = " ".join(actions.choices["direct"].format_help().split())
        self.assertIn("current coordinator repository", direct_help)
        self.assertIn("ai-test, ai-lint, and check", direct_help)
        self.assertLess(
            direct_help.index("Independently review"), direct_help.index("then run exact")
        )
        with self.assertRaises(SystemExit):
            parser.parse_args(["run", "review", "task-1", "--approved"])

    def test_verify_handler_uses_distinct_command_destination(self) -> None:
        args = argparse.Namespace(
            root=self.root,
            action="verify",
            task_id="task-1",
            verification_commands=["just check"],
        )
        with patch("scripts.ai_dev.execution.verify", return_value={"passed": True}) as verifier:
            from scripts.ai_dev.execution import _handle_run

            result = _handle_run(args)

        verifier.assert_called_once_with(self.root, "task-1", ["just check"])
        self.assertTrue(result["passed"])

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
        (assignment.workspace / "backend/.venv/bin").mkdir(parents=True)
        (assignment.workspace / "backend/.venv/bin/python").touch()
        (assignment.workspace / ".dart_tool").mkdir()
        (assignment.workspace / ".dart_tool/package_config.json").write_text("{}")
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

    @patch("scripts.ai_dev.execution.beads.call")
    def test_direct_path_binds_checks_and_review_to_owned_diff(self, call) -> None:
        call.return_value = {
            "id": "task-1",
            "description": "Make the direct change",
            "acceptance": ["checks and review pass"],
            "dependencies": [],
        }
        controller = self.root / "scripts/ai_dev/example.py"
        controller.parent.mkdir(parents=True)
        controller.write_text("base\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "add controller"], cwd=self.root, check=True)
        controller.write_text("direct\n")
        completed = subprocess.CompletedProcess(["just", "check"], 0, "passed", "")
        review = {
            "approved": True,
            "findings": [],
            "summary": "approved",
            "reviewer": "review-thread",
            "reviewerModel": "gpt-5.6-sol",
        }
        call_order = []

        def run_verification(*_args, **_kwargs):
            call_order.append("verification")
            return completed

        def run_review(*_args, **_kwargs):
            call_order.append("review")
            return review

        with (
            patch("scripts.ai_dev.execution._run_verification", side_effect=run_verification),
            patch("scripts.ai_dev.execution._direct_review", side_effect=run_review) as reviewer,
            patch("scripts.ai_dev.execution.fcntl.flock") as heavy_lock,
        ):
            result = verify_direct(
                self.root,
                "task-1",
                ["scripts/ai_dev/example.py"],
                ["just ai-test", "just check"],
            )
        self.assertEqual(result["status"], "ready_for_commit")
        self.assertEqual(call_order, ["review", "verification", "verification"])
        reviewer.assert_called_once()
        self.assertTrue(any(item.args[1] == fcntl.LOCK_EX for item in heavy_lock.call_args_list))
        evidence = json.loads(Path(result["evidence"]).read_text())
        self.assertEqual(evidence["ownedFiles"], ["scripts/ai_dev/example.py"])
        self.assertEqual([item["passed"] for item in evidence["verification"]], [True, True])
        self.assertEqual(evidence["review"]["reviewer"], "review-thread")

        review["findings"] = ["material problem"]
        with (
            patch("scripts.ai_dev.execution._run_verification", return_value=completed) as verifier,
            patch("scripts.ai_dev.execution._direct_review", return_value=review),
            self.assertRaisesRegex(WorkflowError, "independent review rejected"),
        ):
            verify_direct(
                self.root,
                "task-1",
                ["scripts/ai_dev/example.py"],
                ["just ai-test", "just check"],
            )
        verifier.assert_not_called()

    @patch("scripts.ai_dev.execution.beads.call")
    def test_direct_path_rejects_application_files(self, call) -> None:
        call.return_value = {
            "id": "task-1",
            "description": "Change application code",
            "acceptance": ["check passes"],
            "dependencies": [],
        }
        application = self.root / "backend/app.py"
        application.parent.mkdir()
        application.write_text("base\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "add application"], cwd=self.root, check=True)
        application.write_text("changed\n")
        with self.assertRaisesRegex(WorkflowError, "limited to controller and workflow files"):
            verify_direct(self.root, "task-1", ["backend/app.py"], ["just check"])

    @patch("scripts.ai_dev.execution.beads.call")
    def test_direct_path_rejects_its_own_trust_boundary(self, call) -> None:
        call.return_value = {
            "id": "task-1",
            "description": "Change direct verification",
            "acceptance": ["check passes"],
            "dependencies": [],
        }
        trust_files = [
            self.root / "scripts/ai_dev/execution.py",
            self.root / "scripts/__init__.py",
            self.root / "scripts/ai_dev/__main__.py",
            self.root / "scripts/ai_dev/__init__.py",
            self.root / "scripts/ai_dev/app_server.py",
            self.root / "scripts/ai_dev/AGENTS.md",
            self.root / "backend/.pylintrc",
            self.root / "backend/.pylint-allowlist",
            self.root / "backend/.python-version",
            self.root / "backend/uv.lock",
            self.root / "build.yaml",
            self.root / "pubspec.lock",
        ]
        for trust_file in trust_files:
            trust_file.parent.mkdir(parents=True, exist_ok=True)
            trust_file.write_text("base\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "add trust files"], cwd=self.root, check=True)
        for trust_file in trust_files:
            trust_file.write_text("changed\n")
            with (
                self.subTest(path=trust_file.name),
                self.assertRaisesRegex(WorkflowError, "trust boundary is modified"),
            ):
                verify_direct(
                    self.root,
                    "task-1",
                    [trust_file.relative_to(self.root).as_posix()],
                    ["just check"],
                )
            trust_file.write_text("base\n")

    @patch("scripts.ai_dev.execution.beads.call")
    def test_direct_path_rejects_undeclared_dirty_trust_boundary(self, call) -> None:
        call.return_value = {
            "id": "task-1",
            "description": "Change safe controller code",
            "acceptance": ["check passes"],
            "dependencies": [],
        }
        safe_file = self.root / "scripts/ai_dev/audits.py"
        safe_file.parent.mkdir(parents=True)
        safe_file.write_text("base\n")
        trust_files = [
            self.root / "scripts/ai_dev/common.py",
            self.root / "scripts/__init__.py",
            self.root / "scripts/ai_dev/app_server.py",
            self.root / "justfile",
            self.root / ".agents/skills/testing/SKILL.md",
            self.root / "scripts/ai_dev/CLAUDE.md",
            self.root / "backend/.pylintrc",
            self.root / "backend/.pylint-allowlist",
            self.root / "backend/.python-version",
            self.root / "backend/uv.lock",
            self.root / "build.yaml",
            self.root / "pubspec.lock",
        ]
        for trust_file in trust_files:
            trust_file.parent.mkdir(parents=True, exist_ok=True)
            trust_file.write_text("base\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "add controller files"], cwd=self.root, check=True)
        safe_file.write_text("safe change\n")
        for trust_file in trust_files:
            trust_file.write_text("undeclared trust change\n")
            with (
                self.subTest(path=trust_file.relative_to(self.root)),
                self.assertRaisesRegex(WorkflowError, "trust boundary is modified"),
            ):
                verify_direct(
                    self.root,
                    "task-1",
                    ["scripts/ai_dev/audits.py"],
                    ["just check"],
                )
            trust_file.write_text("base\n")

    @patch("scripts.ai_dev.execution.beads.call")
    def test_direct_path_requires_every_dirty_controller_file_in_review(self, call) -> None:
        call.return_value = {
            "id": "task-1",
            "description": "Change safe controller code",
            "acceptance": ["check passes"],
            "dependencies": [],
        }
        safe_file = self.root / "scripts/ai_dev/audits.py"
        undeclared_test = self.root / "scripts/ai_dev/tests/test_other.py"
        for path in (safe_file, undeclared_test):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("base\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "add controller files"], cwd=self.root, check=True)
        safe_file.write_text("safe change\n")
        undeclared_test.write_text("changes ai-test behavior\n")
        with self.assertRaisesRegex(WorkflowError, "every modified controller input"):
            verify_direct(
                self.root,
                "task-1",
                ["scripts/ai_dev/audits.py"],
                ["just check"],
            )

    @patch("scripts.ai_dev.execution.beads.call")
    def test_direct_path_rejects_verification_mutation_outside_scope(self, call) -> None:
        call.return_value = {
            "id": "task-1",
            "description": "Change controller code",
            "acceptance": ["check passes"],
            "dependencies": [],
        }
        controller = self.root / "scripts/ai_dev/example.py"
        controller.parent.mkdir(parents=True)
        controller.write_text("base\n")
        unrelated = self.root / "backend/app.py"
        unrelated.parent.mkdir()
        unrelated.write_text("base\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "add files"], cwd=self.root, check=True)
        controller.write_text("changed\n")
        unrelated.write_text("user change\n")

        def mutate_unrelated(*_args, **_kwargs):
            unrelated.write_text("formatter change\n")
            return subprocess.CompletedProcess(["just", "check"], 0, "passed", "")

        with (
            patch("scripts.ai_dev.execution._run_verification", side_effect=mutate_unrelated),
            patch(
                "scripts.ai_dev.execution._direct_review",
                return_value={"approved": True, "findings": [], "summary": "approved"},
            ) as reviewer,
        ):
            result = verify_direct(
                self.root,
                "task-1",
                ["scripts/ai_dev/example.py"],
                ["just check"],
            )
        self.assertEqual(result["status"], "unrelated_files_changed")
        self.assertEqual(result["files"], ["backend/app.py"])
        reviewer.assert_called_once()

    @patch("scripts.ai_dev.execution.beads.call")
    def test_direct_path_rejects_verification_mutation_of_declared_file(self, call) -> None:
        call.return_value = {
            "id": "task-1",
            "description": "Change controller code",
            "acceptance": ["check passes"],
            "dependencies": [],
        }
        controller = self.root / "scripts/ai_dev/example.py"
        controller.parent.mkdir(parents=True)
        controller.write_text("base\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "add controller"], cwd=self.root, check=True)
        controller.write_text("user change\n")

        def mutate_declared(*_args, **_kwargs):
            controller.write_text("formatter change\n")
            return subprocess.CompletedProcess(["just", "check"], 0, "passed", "")

        with (
            patch("scripts.ai_dev.execution._run_verification", side_effect=mutate_declared),
            patch(
                "scripts.ai_dev.execution._direct_review",
                return_value={"approved": True, "findings": [], "summary": "approved"},
            ) as reviewer,
        ):
            result = verify_direct(
                self.root,
                "task-1",
                ["scripts/ai_dev/example.py"],
                ["just check"],
            )
        self.assertEqual(result["status"], "declared_files_changed")
        reviewer.assert_called_once()


if __name__ == "__main__":
    unittest.main()
