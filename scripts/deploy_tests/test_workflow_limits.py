"""Production Compose forwards workflow defaults and operator overrides."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class WorkflowLimitConfigTests(unittest.TestCase):
    def test_compose_renders_workflow_defaults_and_overrides(self):
        cases = [
            ({}, (10800, 600)),
            ({"WORKFLOW_MAX_RUN_SECONDS": "21600", "WORKFLOW_IDLE_TIMEOUT_SECONDS": "1200"},
             (21600, 1200)),
        ]
        for overrides, expected in cases:
            with self.subTest(overrides=overrides), tempfile.TemporaryDirectory() as directory:
                values = {
                    "PUBLIC_TUNNELS": "cloudflare",
                    "CLOUDFLARE_DOMAIN": "example.test",
                    "CLOUDFLARE_TUNNEL_TOKEN": "test-cloudflare",
                    "POSTGRES_PASSWORD": "test",
                    "SECRET_KEY": "test",
                    "GIT_SSH_KEY_PATH": "/dev/null",
                    "GIT_USER_NAME": "Test",
                    "GIT_USER_EMAIL": "test@example.com",
                    "READ_ALOUD_WORKER_TOKEN": "test-worker",
                    "HF_TOKEN": "test-huggingface",
                    **overrides,
                }
                env_file = Path(directory) / ".env"
                env_file.write_text("\n".join(f"{key}={value}" for key, value in values.items()))
                env = os.environ.copy()
                for name in (
                    "PUBLIC_APP_URL", "WORKFLOW_MAX_RUN_SECONDS", "WORKFLOW_IDLE_TIMEOUT_SECONDS"
                ):
                    env.pop(name, None)
                env["PROD_ENV_FILE"] = str(env_file)
                result = subprocess.run(
                    ["bash", str(ROOT / "scripts/prod-compose.sh"), "config", "--format", "json"],
                    env=env, capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                backend_env = json.loads(result.stdout)["services"]["backend"]["environment"]
                self.assertEqual(
                    (int(backend_env["WORKFLOW_MAX_RUN_SECONDS"]),
                     int(backend_env["WORKFLOW_IDLE_TIMEOUT_SECONDS"])),
                    expected,
                )


if __name__ == "__main__":
    unittest.main()
