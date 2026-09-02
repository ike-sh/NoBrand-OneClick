#!/usr/bin/env python3
import argparse
import socket
import sys


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--protocol", choices=("tcp", "udp"), required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--payload", default="nobrand-strict-ingress-proof")
    parser.add_argument("--timeout", type=float, default=0.8)
    return parser.parse_args()


def probe_tcp(args, payload):
    with socket.create_connection((args.host, args.port), timeout=args.timeout) as conn:
        conn.settimeout(args.timeout)
        conn.sendall(payload)
        received = b""
        while len(received) < len(payload):
            chunk = conn.recv(len(payload) - len(received))
            if not chunk:
                break
            received += chunk
    return received == payload


def probe_udp(args, payload):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(args.timeout)
        sock.sendto(payload, (args.host, args.port))
        received, peer = sock.recvfrom(65535)
    return peer[0] == args.host and received == payload


def main():
    args = parse_args()
    payload = args.payload.encode("utf-8")
    try:
        ok = probe_tcp(args, payload) if args.protocol == "tcp" else probe_udp(args, payload)
    except (OSError, TimeoutError):
        ok = False
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
