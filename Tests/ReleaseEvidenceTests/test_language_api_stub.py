import http.client
import hashlib
import io
import json
import pathlib
import secrets
import sys
import threading
import time
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))

import language_api_stub  # noqa: E402


class RunningStub:
    def __init__(self, scenario):
        self.events = []
        self.server = language_api_stub.create_server(
            scenario=scenario,
            event_sink=self.events.append,
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    @property
    def port(self):
        return self.server.server_address[1]

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=2)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        payload = response.read()
        connection.close()
        return response.status, payload, dict(response.getheaders())


class LanguageAPIStubTests(unittest.TestCase):
    def test_binds_only_to_ipv4_loopback(self):
        with RunningStub(language_api_stub.Scenario()) as stub:
            self.assertEqual(stub.server.server_address[0], "127.0.0.1")

    def test_exact_detect_contract_returns_each_verdict(self):
        for verdict in ("jah", "ei", "ebakindel"):
            with self.subTest(verdict=verdict):
                with RunningStub(language_api_stub.Scenario(verdict=verdict)) as stub:
                    status, body, headers = stub.request(
                        "POST",
                        "/detect",
                        body=json.dumps({"text": "Tere, õun 🍎"}, ensure_ascii=False).encode(),
                        headers={"Content-Type": "application/json"},
                    )

                    self.assertEqual(status, 200)
                    self.assertEqual(json.loads(body), {"verdict": verdict})
                    self.assertEqual(headers["Content-Type"], "application/json")

    def test_rejects_other_routes_methods_and_request_shapes(self):
        with RunningStub(language_api_stub.Scenario()) as stub:
            status, _, _ = stub.request("POST", "/other", body=b"{}")
            self.assertEqual(status, 404)
            status, _, _ = stub.request("PUT", "/detect", body=b"{}")
            self.assertEqual(status, 405)

            for body in (b"not-json", b"{}", b'{"text":"Tere","extra":true}', b'{"text":7}'):
                status, _, _ = stub.request(
                    "POST", "/detect", body=body, headers={"Content-Type": "application/json"}
                )
                self.assertEqual(status, 400)

    def test_supports_delay_and_deterministic_failure_scenarios(self):
        with RunningStub(language_api_stub.Scenario(verdict="jah", delay_seconds=0.08)) as stub:
            started = time.monotonic()
            status, _, _ = stub.request(
                "POST",
                "/detect",
                body=b'{"text":"Tere"}',
                headers={"Content-Type": "application/json"},
            )
            self.assertEqual(status, 200)
            self.assertGreaterEqual(time.monotonic() - started, 0.07)

        with RunningStub(language_api_stub.Scenario(response_mode="incompatible")) as stub:
            status, body, _ = stub.request(
                "POST",
                "/detect",
                body=b'{"text":"Tere"}',
                headers={"Content-Type": "application/json"},
            )
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body), {"verdict": "test-only-unknown"})

        with RunningStub(language_api_stub.Scenario(response_mode="invalid-json")) as stub:
            status, body, headers = stub.request(
                "POST",
                "/detect",
                body=b'{"text":"Tere"}',
                headers={"Content-Type": "application/json"},
            )
            self.assertEqual(status, 200)
            self.assertEqual(headers["Content-Type"], "application/json")
            self.assertEqual(body, b"test-only-invalid-json")

        with RunningStub(language_api_stub.Scenario(response_mode="server-error")) as stub:
            status, body, _ = stub.request(
                "POST",
                "/detect",
                body=b'{"text":"Tere"}',
                headers={"Content-Type": "application/json"},
            )
            self.assertEqual(status, 503)
            self.assertEqual(json.loads(body), {"error": "test-only-unavailable"})

    def test_status_and_events_expose_metadata_but_never_request_text(self):
        canary = "AUTOMAATKORREKTOR-PRIVACY-CANARY-" + secrets.token_hex(8)
        canary_sha256 = hashlib.sha256(canary.encode()).hexdigest()
        output = io.StringIO()
        with RunningStub(
            language_api_stub.Scenario(canary_sha256=canary_sha256),
        ) as stub:
            stub.server.event_sink = lambda event: print(
                json.dumps(event, sort_keys=True), file=output
            )
            status, _, _ = stub.request(
                "POST",
                "/detect",
                body=json.dumps({"text": canary}).encode(),
                headers={"Content-Type": "application/json"},
            )
            self.assertEqual(status, 200)

            status, body, _ = stub.request("GET", "/_test/status")
            self.assertEqual(status, 200)
            metadata = json.loads(body)

        self.assertEqual(metadata["request_count"], 1)
        self.assertTrue(metadata["last_request"]["canary_match"])
        self.assertEqual(metadata["last_request"]["path"], "/detect")
        self.assertEqual(metadata["last_request"]["json_fields"], ["text"])
        self.assertNotIn("text", metadata["last_request"])
        self.assertNotIn(canary, body.decode())
        self.assertNotIn(canary, output.getvalue())
        self.assertNotIn(canary, repr(stub.server.state.snapshot()))


if __name__ == "__main__":
    unittest.main()
