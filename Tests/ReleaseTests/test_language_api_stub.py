import contextlib
import io
import json
import pathlib
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request


REPO = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))

import language_api_stub  # noqa: E402


class RunningStub:
    def __init__(self, scenario):
        self.server = language_api_stub.create_server(scenario)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, method="POST", path="/detect", body=None):
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.server.server_port}{path}",
            data=body if body is not None else json.dumps({"text": "Tere"}).encode(),
            method=method,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())


class LanguageAPIStubTests(unittest.TestCase):
    def test_configuration_is_validated(self):
        with self.assertRaisesRegex(ValueError, "otsus"):
            language_api_stub.Scenario(verdict="maybe")
        with self.assertRaisesRegex(ValueError, "viivitus"):
            language_api_stub.Scenario(delay_seconds=31)

    def test_binds_only_to_ipv4_loopback(self):
        with RunningStub(language_api_stub.Scenario()) as stub:
            self.assertEqual(stub.server.server_address[0], "127.0.0.1")

    def test_returns_each_supported_verdict(self):
        for verdict in sorted(language_api_stub.VERDICTS):
            with self.subTest(verdict=verdict):
                with RunningStub(language_api_stub.Scenario(verdict=verdict)) as stub:
                    status, body = stub.request()
                self.assertEqual(status, 200)
                self.assertEqual(body, {"verdict": verdict})

    def test_rejects_invalid_requests(self):
        with RunningStub(language_api_stub.Scenario()) as stub:
            self.assertEqual(stub.request(path="/other")[0], 404)
            self.assertEqual(stub.request(method="GET")[0], 405)
            self.assertEqual(stub.request(body=b"{}")[0], 400)
            self.assertEqual(stub.request(body=b"not-json")[0], 400)

    def test_delay_and_log_expose_no_text(self):
        secret = "SALAJANE-TESTTEKST"
        output = io.StringIO()
        with RunningStub(language_api_stub.Scenario(delay_seconds=0.05)) as stub:
            started = time.monotonic()
            with contextlib.redirect_stdout(output):
                status, _ = stub.request(body=json.dumps({"text": secret}).encode())
            elapsed = time.monotonic() - started
            self.assertEqual(stub.server.request_count, 1)
        self.assertEqual(status, 200)
        self.assertGreaterEqual(elapsed, 0.04)
        self.assertNotIn(secret, output.getvalue())
        self.assertIn('"request_count": 1', output.getvalue())


if __name__ == "__main__":
    unittest.main()
