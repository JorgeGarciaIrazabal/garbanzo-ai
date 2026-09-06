import unittest
from pathlib import Path

from scripts.ai_dev.migration_transport import compose_command


class MigrationSmokeUnitTests(unittest.TestCase):
    def test_compose_command_isolated_by_explicit_project_and_file(self):
        root = Path("/workspace")
        command = compose_command(root, "garbanzo-migration-smoke-42", "up", "--wait")
        self.assertEqual(
            command[:4], ["docker", "compose", "--project-name", "garbanzo-migration-smoke-42"]
        )
        self.assertIn(str(root / "scripts/ai_dev/migration-smoke.compose.yml"), command)


if __name__ == "__main__":
    unittest.main()
