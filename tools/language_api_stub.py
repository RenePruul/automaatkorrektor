#!/usr/bin/env python3
"""Võrguühenduseta loopback-keele-API teststub macOS-i väljalaskekontrollidele.

See on testitaristu, mitte keeletuvastaja. Päringukeha töödeldakse ainult
vastamiseks vajalikul ajal ning seda ei säilitata ega logita.
"""

from __future__ import annotations

from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import hmac
import json
import os
import signal
import sys
import threading
import time
from typing import Callable


LOOPBACK_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
MAX_BODY_BYTES = 1_048_576
VERDICTS = frozenset(("jah", "ei", "ebakindel"))
RESPONSE_MODES = frozenset(("verdict", "incompatible", "invalid-json", "server-error"))


@dataclass(frozen=True)
class Scenario:
    verdict: str = "jah"
    response_mode: str = "verdict"
    delay_seconds: float = 0.0
    canary_sha256: str | None = None

    def __post_init__(self) -> None:
        if self.verdict not in VERDICTS:
            raise ValueError("teststubi otsus peab olema jah, ei või ebakindel")
        if self.response_mode not in RESPONSE_MODES:
            raise ValueError("teststubi vastuserežiimi ei toetata")
        if not 0 <= self.delay_seconds <= 30:
            raise ValueError("teststubi viivitus peab olema 0 kuni 30 sekundit")
        if self.canary_sha256 is not None:
            if len(self.canary_sha256) != 64 or any(
                character not in "0123456789abcdef" for character in self.canary_sha256
            ):
                raise ValueError(
                    "teststubi privaatsusnäite SHA-256 peab koosnema 64 "
                    "väiketähelisest kuueteistkümnendsüsteemi märgist"
                )


class FixtureState:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._request_count = 0
        self._last_request: dict[str, object] | None = None

    def record(self, metadata: dict[str, object]) -> dict[str, object]:
        with self._lock:
            self._request_count += 1
            self._last_request = dict(metadata)
            return {
                "event": "detect-request",
                "request_count": self._request_count,
                **metadata,
            }

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            return {
                "request_count": self._request_count,
                "last_request": (
                    dict(self._last_request) if self._last_request is not None else None
                ),
            }


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(
        self,
        server_address: tuple[str, int],
        handler_class: type[BaseHTTPRequestHandler],
        *,
        scenario: Scenario,
        event_sink: Callable[[dict[str, object]], None],
    ) -> None:
        super().__init__(server_address, handler_class)
        self.scenario = scenario
        self.event_sink = event_sink
        self.state = FixtureState()


class FixtureHandler(BaseHTTPRequestHandler):
    server: FixtureServer
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: object) -> None:
        # BaseHTTPRequestHandler lisab vaikelogisse teed ja vastaspoole andmed.
        # Teststub väljastab selle asemel ainult lubatud metaandmed.
        return

    def do_POST(self) -> None:
        if self.path != "/detect":
            self._send_json(404, {"error": "test-only-not-found"})
            return

        parsed = self._read_request()
        if parsed is None:
            return

        text, body_size, json_fields = parsed
        scenario = self.server.scenario
        canary_digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
        metadata: dict[str, object] = {
            "method": "POST",
            "path": "/detect",
            "body_bytes": body_size,
            "json_fields": json_fields,
            "canary_configured": scenario.canary_sha256 is not None,
            "canary_match": scenario.canary_sha256 is not None
            and hmac.compare_digest(canary_digest, scenario.canary_sha256),
        }
        self.server.event_sink(self.server.state.record(metadata))

        if scenario.delay_seconds:
            time.sleep(scenario.delay_seconds)

        if scenario.response_mode == "server-error":
            self._send_json(503, {"error": "test-only-unavailable"})
        elif scenario.response_mode == "incompatible":
            self._send_json(200, {"verdict": "test-only-unknown"})
        elif scenario.response_mode == "invalid-json":
            self._send_bytes(200, b"test-only-invalid-json", "application/json")
        else:
            self._send_json(200, {"verdict": scenario.verdict})

    def do_GET(self) -> None:
        if self.path == "/_test/status":
            self._send_json(200, self.server.state.snapshot())
        else:
            self._send_json(404, {"error": "test-only-not-found"})

    def do_PUT(self) -> None:
        self._method_not_allowed()

    def do_PATCH(self) -> None:
        self._method_not_allowed()

    def do_DELETE(self) -> None:
        self._method_not_allowed()

    def _method_not_allowed(self) -> None:
        self._send_json(405, {"error": "test-only-method-not-allowed"})

    def _read_request(self) -> tuple[str, int, list[str]] | None:
        content_type = self.headers.get("Content-Type", "")
        if content_type.split(";", 1)[0].strip().lower() != "application/json":
            self._send_json(415, {"error": "test-only-content-type"})
            return None

        try:
            body_size = int(self.headers.get("Content-Length", ""))
        except ValueError:
            body_size = -1
        if not 0 <= body_size <= MAX_BODY_BYTES:
            self._send_json(400, {"error": "test-only-invalid-body"})
            return None

        body = self.rfile.read(body_size)
        try:
            value = json.loads(body)
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send_json(400, {"error": "test-only-invalid-json"})
            return None

        if not isinstance(value, dict) or set(value) != {"text"} or not isinstance(value["text"], str):
            self._send_json(400, {"error": "test-only-invalid-contract"})
            return None

        text = value["text"]
        del value
        del body
        return text, body_size, ["text"]

    def _send_json(self, status: int, value: object) -> None:
        self._send_bytes(
            status,
            json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
            "application/json",
        )

    def _send_bytes(self, status: int, body: bytes, content_type: str) -> None:
        try:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # Oodatud, kui klient katkestab viivitusega päringu.
            return


def emit_json(event: dict[str, object]) -> None:
    print(json.dumps(event, sort_keys=True, separators=(",", ":")), flush=True)


def create_server(
    *,
    scenario: Scenario,
    port: int = 0,
    event_sink: Callable[[dict[str, object]], None] = emit_json,
) -> FixtureServer:
    return FixtureServer(
        (LOOPBACK_HOST, port),
        FixtureHandler,
        scenario=scenario,
        event_sink=event_sink,
    )


def scenario_from_environment() -> tuple[Scenario, int]:
    verdict = os.environ.get("AUTOMAATKORREKTOR_STUB_VERDICT", "jah")
    response_mode = os.environ.get("AUTOMAATKORREKTOR_STUB_RESPONSE", "verdict")
    delay_seconds = float(os.environ.get("AUTOMAATKORREKTOR_STUB_DELAY_SECONDS", "0"))
    canary_sha256 = os.environ.get("AUTOMAATKORREKTOR_STUB_CANARY_SHA256")
    port = int(os.environ.get("AUTOMAATKORREKTOR_STUB_PORT", str(DEFAULT_PORT)))
    if not 1 <= port <= 65535:
        raise ValueError("teststubi port peab olema 1 kuni 65535")
    return Scenario(verdict, response_mode, delay_seconds, canary_sha256), port


def main() -> int:
    if len(sys.argv) != 1:
        print(
            "seadistamiseks kasutatakse keskkonnamuutujaid; käsuargumente ei lubata",
            file=sys.stderr,
        )
        return 64
    try:
        scenario, port = scenario_from_environment()
        server = create_server(scenario=scenario, port=port)
    except (OSError, ValueError) as error:
        print(f"teststubi seadistusviga: {error}", file=sys.stderr)
        return 64

    emit_json(
        {
            "event": "ready",
            "host": LOOPBACK_HOST,
            "port": server.server_address[1],
            "response_mode": scenario.response_mode,
            "verdict": scenario.verdict if scenario.response_mode == "verdict" else None,
            "delay_seconds": scenario.delay_seconds,
            "canary_configured": scenario.canary_sha256 is not None,
        }
    )

    def stop_server(signum: int, frame: object) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, stop_server)
    signal.signal(signal.SIGTERM, stop_server)
    try:
        server.serve_forever()
    finally:
        server.server_close()
    emit_json({"event": "stopped", **server.state.snapshot()})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
