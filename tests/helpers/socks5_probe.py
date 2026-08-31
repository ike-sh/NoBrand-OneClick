#!/usr/bin/env python3
"""Small dependency-free SOCKS5 TCP/UDP probe used by runtime qualification."""

import argparse
import ipaddress
import socket
import struct
import sys


def recv_exact(stream: socket.socket, size: int) -> bytes:
    chunks = bytearray()
    while len(chunks) < size:
        part = stream.recv(size - len(chunks))
        if not part:
            raise RuntimeError("unexpected EOF")
        chunks.extend(part)
    return bytes(chunks)


def socks_greeting(stream: socket.socket) -> None:
    stream.sendall(b"\x05\x01\x00")
    if recv_exact(stream, 2) != b"\x05\x00":
        raise RuntimeError("SOCKS5 no-auth negotiation failed")


def address_field(host: str) -> bytes:
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        encoded = host.encode("idna")
        if len(encoded) > 255:
            raise RuntimeError("domain is too long")
        return b"\x03" + bytes([len(encoded)]) + encoded
    if address.version == 4:
        return b"\x01" + address.packed
    return b"\x04" + address.packed


def read_reply_address(stream: socket.socket) -> tuple[str, int]:
    version, status, reserved, address_type = recv_exact(stream, 4)
    if version != 5 or status != 0 or reserved != 0:
        raise RuntimeError(f"SOCKS5 request failed with status {status}")
    if address_type == 1:
        host = str(ipaddress.ip_address(recv_exact(stream, 4)))
    elif address_type == 4:
        host = str(ipaddress.ip_address(recv_exact(stream, 16)))
    elif address_type == 3:
        host = recv_exact(stream, recv_exact(stream, 1)[0]).decode("idna")
    else:
        raise RuntimeError(f"unsupported SOCKS5 address type {address_type}")
    port = struct.unpack("!H", recv_exact(stream, 2))[0]
    return host, port


def parse_udp_packet(packet: bytes) -> bytes:
    if len(packet) < 4 or packet[:3] != b"\x00\x00\x00":
        raise RuntimeError("invalid SOCKS5 UDP header")
    offset = 4
    address_type = packet[3]
    if address_type == 1:
        offset += 4
    elif address_type == 4:
        offset += 16
    elif address_type == 3:
        if len(packet) <= offset:
            raise RuntimeError("truncated SOCKS5 UDP domain")
        offset += 1 + packet[offset]
    else:
        raise RuntimeError(f"unsupported SOCKS5 UDP address type {address_type}")
    offset += 2
    if len(packet) < offset:
        raise RuntimeError("truncated SOCKS5 UDP packet")
    return packet[offset:]


def deterministic_payload(size: int) -> bytes:
    return bytes((index * 37 + size) % 251 for index in range(size))


def tcp_probe(args: argparse.Namespace) -> None:
    with socket.create_connection((args.proxy_host, args.proxy_port), args.timeout) as stream:
        stream.settimeout(args.timeout)
        socks_greeting(stream)
        request = b"\x05\x01\x00" + address_field(args.target_host) + struct.pack("!H", args.target_port)
        stream.sendall(request)
        read_reply_address(stream)
        payload = deterministic_payload(args.size)
        stream.sendall(payload)
        echoed = recv_exact(stream, len(payload))
        if echoed != payload:
            raise RuntimeError("TCP payload integrity mismatch")


def udp_probe(args: argparse.Namespace) -> None:
    with socket.create_connection((args.proxy_host, args.proxy_port), args.timeout) as control:
        control.settimeout(args.timeout)
        socks_greeting(control)
        control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
        relay_host, relay_port = read_reply_address(control)
        if relay_host in ("0.0.0.0", "::"):
            relay_host = args.proxy_host
        with socket.socket(socket.AF_INET6 if ":" in relay_host else socket.AF_INET, socket.SOCK_DGRAM) as datagram:
            datagram.settimeout(args.timeout)
            for size in args.sizes:
                payload = deterministic_payload(size)
                packet = b"\x00\x00\x00" + address_field(args.target_host) \
                    + struct.pack("!H", args.target_port) + payload
                datagram.sendto(packet, (relay_host, relay_port))
                echoed, _ = datagram.recvfrom(size + 512)
                if parse_udp_packet(echoed) != payload:
                    raise RuntimeError(f"UDP payload integrity mismatch at {size} bytes")


def echo_server(args: argparse.Namespace) -> None:
    family = socket.AF_INET6 if ":" in args.host else socket.AF_INET
    if args.protocol == "tcp":
        with socket.socket(family, socket.SOCK_STREAM) as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind((args.host, args.port))
            listener.listen(16)
            while True:
                connection, _ = listener.accept()
                with connection:
                    while True:
                        data = connection.recv(65536)
                        if not data:
                            break
                        connection.sendall(data)
    else:
        with socket.socket(family, socket.SOCK_DGRAM) as listener:
            listener.bind((args.host, args.port))
            while True:
                data, peer = listener.recvfrom(65535)
                listener.sendto(data, peer)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    modes = root.add_subparsers(dest="mode", required=True)
    for mode in ("tcp", "udp"):
        probe = modes.add_parser(mode)
        probe.add_argument("--proxy-host", default="127.0.0.1")
        probe.add_argument("--proxy-port", type=int, required=True)
        probe.add_argument("--target-host", default="127.0.0.1")
        probe.add_argument("--target-port", type=int, required=True)
        probe.add_argument("--timeout", type=float, default=8.0)
        if mode == "tcp":
            probe.add_argument("--size", type=int, default=65536)
        else:
            probe.add_argument("--sizes", type=int, nargs="+", default=[64, 512, 1200, 1400])
    server = modes.add_parser("echo-server")
    server.add_argument("--protocol", choices=("tcp", "udp"), required=True)
    server.add_argument("--host", default="127.0.0.1")
    server.add_argument("--port", type=int, required=True)
    return root


def main() -> int:
    args = parser().parse_args()
    if args.mode == "tcp":
        tcp_probe(args)
    elif args.mode == "udp":
        udp_probe(args)
    else:
        echo_server(args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"probe failed: {error}", file=sys.stderr)
        raise SystemExit(1)
