#!/usr/bin/env python3
"""Lihtne ainult loopback'il töötav keeleteenuse testserver."""

from __future__ import annotations

import json
import os
import sys
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


VERDICTS = {"jah", "ei", "ebakindel"}
MAX_REQUEST_BYTES = 64 * 1024


@dataclass(frozen=True)
class Scenario:
    verdict: str = "jah"
    delay_seconds: float = 0

    def __post_init__(self) -> None:
        if self.verdict not in VERDICTS:
            raise ValueError("testserveri otsus peab olema jah, ei või ebakindel")
        if not 0 <= self.delay_seconds <= 30:
            raise ValueError("testserveri viivitus peab olema 0 kuni 30 sekundit")


class StubServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], scenario: Scenario) -> None:
        super().__init__(address, StubHandler)
        self.scenario = scenario
        self.request_count = 0
        self.request_count_lock = threading.Lock()

    def record_request(self, text_length: int) -> None:
        with self.request_count_lock:
            self.request_count += 1
            count = self.request_count
        print(
            json.dumps(
                {"event": "request", "request_count": count, "text_length": text_length},
                ensure_ascii=False,
            ),
            flush=True,
        )


class StubHandler(BaseHTTPRequestHandler):
    server: StubServer

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_POST(self) -> None:
        if self.path != "/detect":
            self._send_json(404, {"error": "not_found"})
            return

        content_type = self.headers.get("Content-Type", "").split(";", 1)[0].strip()
        try:
            content_length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            content_length = -1
        if content_type != "application/json" or not 0 < content_length <= MAX_REQUEST_BYTES:
            self._send_json(400, {"error": "invalid_request"})
            return

        try:
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send_json(400, {"error": "invalid_request"})
            return

        if (
            not isinstance(payload, dict)
            or set(payload) != {"text"}
            or not isinstance(payload["text"], str)
            or not payload["text"]
        ):
            self._send_json(400, {"error": "invalid_request"})
            return

        self.server.record_request(len(payload["text"]))
        time.sleep(self.server.scenario.delay_seconds)
        self._send_json(200, {"verdict": self.server.scenario.verdict})

    def do_GET(self) -> None:
        self._send_json(405, {"error": "method_not_allowed"})

    do_PUT = do_GET
    do_PATCH = do_GET
    do_DELETE = do_GET

    def _send_json(self, status: int, value: object) -> None:
        body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


def create_server(scenario: Scenario, port: int = 0) -> StubServer:
    return StubServer(("127.0.0.1", port), scenario)


def scenario_from_environment() -> tuple[Scenario, int]:
    verdict = os.environ.get("AUTOMAATKORREKTOR_STUB_VERDICT", "jah")
    try:
        delay = float(os.environ.get("AUTOMAATKORREKTOR_STUB_DELAY_SECONDS", "0"))
        port = int(os.environ.get("AUTOMAATKORREKTOR_STUB_PORT", "8000"))
    except ValueError as error:
        raise ValueError("testserveri port ja viivitus peavad olema arvud") from error
    if not 1 <= port <= 65_535:
        raise ValueError("testserveri port peab olema 1 kuni 65535")
    return Scenario(verdict=verdict, delay_seconds=delay), port


def main() -> int:
    try:
        scenario, port = scenario_from_environment()
        server = create_server(scenario, port)
    except (OSError, ValueError) as error:
        print(f"testserveri käivitamine ebaõnnestus: {error}", file=sys.stderr)
        return 2

    print(
        json.dumps(
            {
                "event": "started",
                "url": f"http://127.0.0.1:{server.server_port}",
                "verdict": scenario.verdict,
                "delay_seconds": scenario.delay_seconds,
            },
            ensure_ascii=False,
        ),
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
