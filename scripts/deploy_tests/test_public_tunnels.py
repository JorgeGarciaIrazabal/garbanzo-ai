"""Production tunnel configuration and legacy compatibility."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "scripts/prod-config.sh"


class PublicTunnelConfigTests(unittest.TestCase):
    def run_config(self, values):
        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / ".env"
            env_file.write_text("\n".join(f"{key}={value}" for key, value in values.items()))
            env = os.environ.copy()
            env["PROD_ENV_FILE"] = str(env_file)
            for key in (
                "PUBLIC_TUNNELS", "PUBLIC_APP_URL", "CLOUDFLARE_DOMAIN",
                "CLOUDFLARE_TUNNEL_TOKEN", "NGROK_DOMAIN", "NGROK_AUTHTOKEN",
            ):
                env.pop(key, None)
            return subprocess.run(
                ["bash", "-c", 'source "$1"; prod_config "$2" && printf "%s\\n" "$PUBLIC_APP_URL" "$PROD_CORS_ORIGINS" "${PROD_TUNNEL_SERVICES[*]}"', "test", str(CONFIG), str(ROOT)],
                env=env, capture_output=True, text=True, check=False,
            )

    def test_existing_ngrok_configuration_still_works(self):
        result = self.run_config({"NGROK_DOMAIN": "old.ngrok-free.app", "NGROK_AUTHTOKEN": "test"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["https://old.ngrok-free.app", "https://old.ngrok-free.app", "ngrok"])

    def test_cloudflare_only_requires_no_ngrok_credentials(self):
        result = self.run_config({"PUBLIC_TUNNELS": "cloudflare", "CLOUDFLARE_DOMAIN": "garbanzo.fyi", "CLOUDFLARE_TUNNEL_TOKEN": "test"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["https://garbanzo.fyi", "https://garbanzo.fyi", "cloudflared"])

    def test_dual_mode_allows_both_origins_and_explicit_primary(self):
        result = self.run_config({
            "PUBLIC_TUNNELS": "both", "NGROK_DOMAIN": "old.ngrok-free.app", "NGROK_AUTHTOKEN": "test",
            "CLOUDFLARE_DOMAIN": "garbanzo.fyi", "CLOUDFLARE_TUNNEL_TOKEN": "test",
            "PUBLIC_APP_URL": "https://garbanzo.fyi",
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["https://garbanzo.fyi", "https://old.ngrok-free.app,https://garbanzo.fyi", "ngrok cloudflared"])

    def test_compose_renders_both_connectors_and_both_cors_origins(self):
        values = {
            "PUBLIC_TUNNELS": "both", "NGROK_DOMAIN": "old.ngrok-free.app",
            "NGROK_AUTHTOKEN": "test-ngrok", "CLOUDFLARE_DOMAIN": "garbanzo.fyi",
            "CLOUDFLARE_TUNNEL_TOKEN": "test-cloudflare",
            "PUBLIC_APP_URL": "https://old.ngrok-free.app",
            "POSTGRES_PASSWORD": "test", "SECRET_KEY": "test", "GIT_SSH_KEY_PATH": "/dev/null",
            "GIT_USER_NAME": "Test", "GIT_USER_EMAIL": "test@example.com",
        }
        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / ".env"
            env_file.write_text("\n".join(f"{key}={value}" for key, value in values.items()))
            env = os.environ.copy()
            env["PROD_ENV_FILE"] = str(env_file)
            for key in ("PUBLIC_TUNNELS", "PUBLIC_APP_URL", "CLOUDFLARE_DOMAIN", "CLOUDFLARE_TUNNEL_TOKEN", "NGROK_DOMAIN", "NGROK_AUTHTOKEN"):
                env.pop(key, None)
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/prod-compose.sh"), "config", "--format", "json"],
                env=env, capture_output=True, text=True, check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        import json
        config = json.loads(result.stdout)
        self.assertEqual(config["services"]["backend"]["environment"]["CORS_ORIGINS"],
                         "https://old.ngrok-free.app,https://garbanzo.fyi")
        self.assertIn("ngrok", config["services"])
        self.assertIn("cloudflared", config["services"])

    def test_compose_cloudflare_only_excludes_ngrok(self):
        values = {
            "PUBLIC_TUNNELS": "cloudflare", "CLOUDFLARE_DOMAIN": "garbanzo.fyi",
            "CLOUDFLARE_TUNNEL_TOKEN": "test-cloudflare", "POSTGRES_PASSWORD": "test",
            "SECRET_KEY": "test", "GIT_SSH_KEY_PATH": "/dev/null",
            "GIT_USER_NAME": "Test", "GIT_USER_EMAIL": "test@example.com",
        }
        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / ".env"
            env_file.write_text("\n".join(f"{key}={value}" for key, value in values.items()))
            env = os.environ.copy()
            env["PROD_ENV_FILE"] = str(env_file)
            for key in ("PUBLIC_TUNNELS", "PUBLIC_APP_URL", "NGROK_DOMAIN", "NGROK_AUTHTOKEN"):
                env.pop(key, None)
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/prod-compose.sh"), "config", "--format", "json"],
                env=env, capture_output=True, text=True, check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        import json
        config = json.loads(result.stdout)
        self.assertEqual(config["services"]["backend"]["environment"]["CORS_ORIGINS"], "https://garbanzo.fyi")
        self.assertIn("cloudflared", config["services"])
        self.assertNotIn("ngrok", config["services"])

    def test_dual_mode_needs_explicit_primary(self):
        result = self.run_config({
            "PUBLIC_TUNNELS": "both", "NGROK_DOMAIN": "old.ngrok-free.app", "NGROK_AUTHTOKEN": "test",
            "CLOUDFLARE_DOMAIN": "garbanzo.fyi", "CLOUDFLARE_TUNNEL_TOKEN": "test",
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PUBLIC_APP_URL is required", result.stderr)

    def test_missing_cloudflare_token_fails_without_echoing_credentials(self):
        result = self.run_config({
            "PUBLIC_TUNNELS": "both", "NGROK_DOMAIN": "old.ngrok-free.app", "NGROK_AUTHTOKEN": "secret-ngrok",
            "CLOUDFLARE_DOMAIN": "garbanzo.fyi", "PUBLIC_APP_URL": "https://garbanzo.fyi",
        })
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CLOUDFLARE_TUNNEL_TOKEN", result.stderr)
        self.assertNotIn("secret-ngrok", result.stderr)


if __name__ == "__main__":
    unittest.main()
