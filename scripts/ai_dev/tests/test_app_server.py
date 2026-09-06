import io
import json
import unittest

from scripts.ai_dev.app_server import AppServerClient, AppServerError


class Process:
    def __init__(self, output):
        self.stdin = io.StringIO()
        self.stdout = io.StringIO(output)
        self.stderr = io.StringIO()
        self.returncode = None

    def poll(self):
        return self.returncode

    def terminate(self):
        self.returncode = 0

    def wait(self, timeout=None):
        return self.returncode


class AppServerTests(unittest.TestCase):
    def test_request_ignores_notifications_and_matches_id(self):
        process = Process(
            '{"method":"account/rateLimits/updated","params":{}}\n{"id":1,"result":{"data":[]}}\n'
        )
        client = AppServerClient(process=process)
        self.assertEqual(client.request("model/list", {"includeHidden": False}), {"data": []})
        self.assertEqual(json.loads(process.stdin.getvalue())["method"], "model/list")

    def test_rpc_errors_are_actionable(self):
        client = AppServerClient(
            process=Process('{"id":1,"error":{"code":-1,"message":"no auth"}}\n')
        )
        with self.assertRaisesRegex(AppServerError, "no auth"):
            client.request("account/read")

    def test_invalid_result_is_rejected(self):
        client = AppServerClient(process=Process('{"id":1,"result":[]}\n'))
        with self.assertRaisesRegex(AppServerError, "not an object"):
            client.request("model/list")
