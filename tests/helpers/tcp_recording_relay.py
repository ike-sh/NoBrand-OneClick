#!/usr/bin/env python3
"""Small TCP relay used only to prove the selected proxy transport endpoint."""

from __future__ import annotations

import argparse
import socket
import threading
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, required=True)
    parser.add_argument("--target-host", default="127.0.0.1")
    parser.add_argument("--target-port", type=int, required=True)
    parser.add_argument("--count-file", type=Path, required=True)
    return parser.parse_args()


class Counter:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.lock = threading.Lock()
        self.value = 0
        self.path.write_text("0\n", encoding="ascii")

    def increment(self) -> None:
        with self.lock:
            self.value += 1
            self.path.write_text(f"{self.value}\n", encoding="ascii")


def relay(client: socket.socket, target_host: str, target_port: int) -> None:
    upstream: socket.socket | None = None
    try:
        upstream = socket.create_connection((target_host, target_port), timeout=10)
        client.settimeout(60)
        upstream.settimeout(60)

        def pump(source: socket.socket, destination: socket.socket) -> None:
            try:
                while chunk := source.recv(65536):
                    destination.sendall(chunk)
            except OSError:
                pass
            finally:
                try:
                    destination.shutdown(socket.SHUT_WR)
                except OSError:
                    pass

        reverse = threading.Thread(target=pump, args=(upstream, client), daemon=True)
        reverse.start()
        pump(client, upstream)
        reverse.join(timeout=5)
    except OSError:
        return
    finally:
        try:
            client.close()
        finally:
            if upstream is not None:
                upstream.close()


def main() -> None:
    args = parse_args()
    counter = Counter(args.count_file)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((args.listen_host, args.listen_port))
        listener.listen(128)
        while True:
            client, _ = listener.accept()
            counter.increment()
            threading.Thread(
                target=relay,
                args=(client, args.target_host, args.target_port),
                daemon=True,
            ).start()


if __name__ == "__main__":
    main()
