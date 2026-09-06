import tempfile
import threading
import unittest
from datetime import UTC, datetime
from pathlib import Path

from scripts.ai_dev.capacity import Allowance
from scripts.ai_dev.nightly import NightlyRunner, NightTask, select_tasks, within_window


def allowance(now, used=0):
    return [Allowance("codex", "weekly", used, now, True)]


class NightlyTests(unittest.TestCase):
    def test_window_is_midnight_to_six_new_york(self):
        self.assertTrue(within_window(datetime(2026, 1, 1, 6, 0, tzinfo=UTC)))
        self.assertFalse(within_window(datetime(2026, 1, 1, 12, 0, tzinfo=UTC)))

    def test_selects_two_low_risk_tasks_and_excludes_consequential_work(self):
        tasks = [
            NightTask("migration", frozenset({"migration"})),
            NightTask("one", frozenset({"test"}), ("backend/tests/test_one.py",)),
            NightTask("two", frozenset({"docs"}), ("docs/two.md",)),
            NightTask("three", frozenset({"lint"}), ("lib/three.dart",)),
        ]
        self.assertEqual([task.id for task in select_tasks(tasks)], ["one", "two"])

    def test_sensitive_owned_paths_are_not_unattended(self):
        tasks = [
            NightTask("auth", frozenset({"nightly-safe"}), ("backend/app/auth.py",)),
            NightTask("migration", frozenset({"nightly-safe"}), ("backend/migrations/999.sql",)),
        ]
        self.assertEqual(select_tasks(tasks), [])

    def test_daytime_never_catches_up_and_foreground_wins(self):
        day = datetime(2026, 1, 1, 17, tzinfo=UTC)
        runner = NightlyRunner(
            lambda: allowance(day), foreground_active=lambda: False, clock=lambda: day
        )
        self.assertEqual(
            runner.run([NightTask("one", frozenset())], lambda *_: (True, "ok"), now=day), []
        )
        night = datetime(2026, 1, 1, 6, tzinfo=UTC)
        foreground = NightlyRunner(lambda: allowance(night), foreground_active=lambda: True)
        self.assertEqual(
            foreground.run([NightTask("one", frozenset())], lambda *_: (True, "ok"), now=night), []
        )

    def test_one_repair_attempt_and_triage_share_batch(self):
        now = datetime(2026, 1, 1, 6, tzinfo=UTC)
        calls, attempts = [], []
        runner = NightlyRunner(
            lambda: allowance(now), foreground_active=lambda: False, clock=lambda: now
        )

        def worker(task, cancel):
            calls.append(task.id)
            attempts.append(task.id)
            return len(attempts) == 2, "done"

        results = runner.run(
            [NightTask("one", frozenset(), ("docs/one.md",))],
            worker,
            now=now,
            triage=lambda: calls.append("triage"),
        )
        self.assertEqual(calls, ["triage", "one", "one"])
        self.assertEqual(results[0].attempts, 2)

    def test_capacity_guard_blocks_batch_at_80_percent(self):
        now = datetime(2026, 1, 1, 6, tzinfo=UTC)
        runner = NightlyRunner(
            lambda: allowance(now, 80), foreground_active=lambda: False, clock=lambda: now
        )
        self.assertEqual(
            runner.run([NightTask("one", frozenset())], lambda *_: (True, "ok"), now=now), []
        )

    def test_only_one_batch_is_claimed_per_night(self):
        now = datetime(2026, 1, 1, 6, tzinfo=UTC)
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "nightly.json"
            runner = NightlyRunner(
                lambda: allowance(now),
                foreground_active=lambda: False,
                clock=lambda: now,
                state_path=state,
            )
            tasks = [NightTask("one", frozenset(), ("docs/one.md",))]
            self.assertTrue(runner.run(tasks, lambda *_: (True, "ok"), now=now))
            self.assertEqual(runner.run(tasks, lambda *_: (True, "ok"), now=now), [])

    def test_concurrent_schedulers_claim_once(self):
        now = datetime(2026, 1, 1, 6, tzinfo=UTC)
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "nightly.json"
            results = []

            def launch():
                runner = NightlyRunner(
                    lambda: allowance(now),
                    foreground_active=lambda: False,
                    clock=lambda: now,
                    state_path=state,
                )
                results.append(
                    bool(
                        runner.run(
                            [NightTask("one", frozenset(), ("docs/one.md",))],
                            lambda *_: (True, "ok"),
                            now=now,
                        )
                    )
                )

            threads = [threading.Thread(target=launch) for _ in range(2)]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()
            self.assertEqual(sorted(results), [False, True])
