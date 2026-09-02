#!/usr/bin/env python3
"""Controlled HTTP target for 64 MiB proxy download/upload integrity checks."""

from __future__ import annotations

import argparse
import hashlib
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PAYLOAD_SIZE = 64 * 1024 * 1024
CHUNK = b"\0" * (64 * 1024)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *_args: object) -> None:
        return

    def do_GET(self) -> None:  # noqa: N802
        if self.path not in {"/", "/blob"}:
            self.send_error(404)
            return
        if self.path == "/":
            body = b"nobrand-reality-runtime\n"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(PAYLOAD_SIZE))
        self.end_headers()
        remaining = PAYLOAD_SIZE
        while remaining:
            part = CHUNK[: min(len(CHUNK), remaining)]
            self.wfile.write(part)
            remaining -= len(part)

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/upload":
            self.send_error(404)
            return
        try:
            remaining = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return
        digest = hashlib.sha256()
        received = 0
        while remaining:
            chunk = self.rfile.read(min(65536, remaining))
            if not chunk:
                break
            digest.update(chunk)
            received += len(chunk)
            remaining -= len(chunk)
        body = f"{received}:{digest.hexdigest()}\n".encode("ascii")
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.cert, args.key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
