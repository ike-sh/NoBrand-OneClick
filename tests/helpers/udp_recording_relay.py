#!/usr/bin/env python3
"""Single-client UDP relay that records client-to-server packet count."""

from __future__ import annotations

import argparse
from pathlib import Path
import selectors
import socket


def write_count(path: Path, count: int) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(f"{count}\n", encoding="ascii")
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, required=True)
    parser.add_argument("--target-host", default="127.0.0.1")
    parser.add_argument("--target-port", type=int, required=True)
    parser.add_argument("--count-file", type=Path, required=True)
    args = parser.parse_args()

    downstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    downstream.bind((args.listen_host, args.listen_port))
    upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    upstream.connect((args.target_host, args.target_port))
    selector = selectors.DefaultSelector()
    selector.register(downstream, selectors.EVENT_READ, "downstream")
    selector.register(upstream, selectors.EVENT_READ, "upstream")
    client_address: tuple[str, int] | None = None
    count = 0
    write_count(args.count_file, count)

    while True:
        for key, _events in selector.select():
            if key.data == "downstream":
                packet, client_address = downstream.recvfrom(65535)
                count += 1
                write_count(args.count_file, count)
                try:
                    upstream.send(packet)
                except ConnectionRefusedError:
                    # A deliberate server-off regression can leave one queued
                    # ICMP port-unreachable error on the connected UDP socket.
                    # Keep the recording relay alive for the recovery proof.
                    continue
            elif client_address is not None:
                try:
                    packet = upstream.recv(65535)
                except ConnectionRefusedError:
                    continue
                downstream.sendto(packet, client_address)


if __name__ == "__main__":
    raise SystemExit(main())
