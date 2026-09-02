#!/usr/bin/env python3
"""Root-only UDP echo target that records application payload evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import socket
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--record-dir", required=True, type=Path)
    parser.add_argument("--metadata", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    os.umask(0o077)
    args.record_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    args.metadata.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    family = socket.AF_INET6 if ":" in args.host else socket.AF_INET
    sequence = 0
    with args.metadata.open("a", encoding="utf-8", buffering=1) as metadata:
        os.chmod(args.metadata, 0o600)
        with socket.socket(family, socket.SOCK_DGRAM) as listener:
            listener.bind((args.host, args.port))
            while True:
                payload, peer = listener.recvfrom(65535)
                sequence += 1
                record = args.record_dir / f"{sequence:06d}.payload"
                with record.open("xb") as output:
                    output.write(payload)
                    output.flush()
                    os.fsync(output.fileno())
                digest = hashlib.sha256(payload).hexdigest()
                listener.sendto(payload, peer)
                metadata.write(
                    json.dumps(
                        {
                            "SEQUENCE": sequence,
                            "APPLICATION_LENGTH": len(payload),
                            "REQUEST_SHA256": digest,
                            "RESPONSE_SHA256": digest,
                        },
                        sort_keys=True,
                        separators=(",", ":"),
                    )
                    + "\n"
                )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
