#!/usr/bin/env python3
"""Independent RFC 1928 SOCKS5 UDP ASSOCIATE integrity probe.

This diagnostic intentionally does not share address, packet parsing, or
payload-generation code with tests/helpers/socks5_probe.py.  Each trial opens a
fresh UDP association so a delayed response from a timed-out trial cannot be
mistaken for the next response.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import socket
import struct
import sys
from dataclasses import dataclass
from typing import Any


SOCKS_VERSION = 5
ATYP_IPV4 = 1
ATYP_DOMAIN = 3
ATYP_IPV6 = 4
ATYP_NAMES = {
    ATYP_IPV4: "IPv4",
    ATYP_DOMAIN: "DOMAIN",
    ATYP_IPV6: "IPv6",
}


class ProtocolError(RuntimeError):
    """Raised when a SOCKS server returns malformed or unsupported framing."""


@dataclass(frozen=True)
class Endpoint:
    host: str
    port: int
    atyp: int


@dataclass(frozen=True)
class ParsedDatagram:
    endpoint: Endpoint
    header_length: int
    payload: bytes


def read_exact(stream: socket.socket, count: int) -> bytes:
    result = bytearray(count)
    view = memoryview(result)
    received = 0
    while received < count:
        size = stream.recv_into(view[received:])
        if size == 0:
            raise ProtocolError("unexpected EOF in SOCKS5 control reply")
        received += size
    return bytes(result)


def encode_host(host: str) -> tuple[int, bytes]:
    for family, atyp in ((socket.AF_INET, ATYP_IPV4), (socket.AF_INET6, ATYP_IPV6)):
        try:
            return atyp, socket.inet_pton(family, host)
        except OSError:
            pass

    domain = host.encode("idna")
    if not 1 <= len(domain) <= 255:
        raise ProtocolError("SOCKS5 domain length must be between 1 and 255 bytes")
    return ATYP_DOMAIN, bytes((len(domain),)) + domain


def decode_stream_host(stream: socket.socket, atyp: int) -> str:
    if atyp == ATYP_IPV4:
        return socket.inet_ntop(socket.AF_INET, read_exact(stream, 4))
    if atyp == ATYP_IPV6:
        return socket.inet_ntop(socket.AF_INET6, read_exact(stream, 16))
    if atyp == ATYP_DOMAIN:
        length = read_exact(stream, 1)[0]
        if length == 0:
            raise ProtocolError("zero-length domain in SOCKS5 control reply")
        return read_exact(stream, length).decode("idna")
    raise ProtocolError(f"unsupported SOCKS5 ATYP in control reply: {atyp}")


def read_control_endpoint(stream: socket.socket) -> Endpoint:
    version, reply, reserved, atyp = read_exact(stream, 4)
    if version != SOCKS_VERSION:
        raise ProtocolError(f"unexpected SOCKS version in control reply: {version}")
    if reply != 0:
        raise ProtocolError(f"SOCKS5 request rejected with reply code {reply}")
    if reserved != 0:
        raise ProtocolError(f"non-zero reserved byte in control reply: {reserved}")
    host = decode_stream_host(stream, atyp)
    port = struct.unpack("!H", read_exact(stream, 2))[0]
    return Endpoint(host, port, atyp)


def negotiate_udp_associate(stream: socket.socket) -> Endpoint:
    stream.sendall(bytes((SOCKS_VERSION, 1, 0)))
    if read_exact(stream, 2) != bytes((SOCKS_VERSION, 0)):
        raise ProtocolError("SOCKS5 server did not accept no-auth negotiation")

    # CMD=UDP ASSOCIATE, RSV=0, ATYP=IPv4, ADDR=0.0.0.0, PORT=0.
    stream.sendall(struct.pack("!BBBB4sH", SOCKS_VERSION, 3, 0, ATYP_IPV4, b"\0" * 4, 0))
    return read_control_endpoint(stream)


def build_udp_request(target_host: str, target_port: int, payload: bytes) -> bytes:
    atyp, encoded_host = encode_host(target_host)
    # RFC 1928: RSV (2), FRAG (1), ATYP (1), DST.ADDR, DST.PORT, DATA.
    return struct.pack("!HBB", 0, 0, atyp) + encoded_host + struct.pack("!H", target_port) + payload


def require_available(packet: memoryview, cursor: int, count: int, field: str) -> None:
    if cursor + count > len(packet):
        raise ProtocolError(f"truncated SOCKS5 UDP {field}")


def parse_udp_response(raw: bytes) -> ParsedDatagram:
    packet = memoryview(raw)
    require_available(packet, 0, 4, "fixed header")
    reserved, fragment, atyp = struct.unpack_from("!HBB", packet, 0)
    if reserved != 0:
        raise ProtocolError(f"non-zero SOCKS5 UDP RSV: {reserved}")
    if fragment != 0:
        raise ProtocolError(f"fragmented SOCKS5 UDP datagram is unsupported: FRAG={fragment}")

    cursor = 4
    if atyp == ATYP_IPV4:
        require_available(packet, cursor, 4, "IPv4 address")
        host = socket.inet_ntop(socket.AF_INET, packet[cursor : cursor + 4])
        cursor += 4
    elif atyp == ATYP_IPV6:
        require_available(packet, cursor, 16, "IPv6 address")
        host = socket.inet_ntop(socket.AF_INET6, packet[cursor : cursor + 16])
        cursor += 16
    elif atyp == ATYP_DOMAIN:
        require_available(packet, cursor, 1, "domain length")
        domain_length = packet[cursor]
        cursor += 1
        if domain_length == 0:
            raise ProtocolError("zero-length domain in SOCKS5 UDP response")
        require_available(packet, cursor, domain_length, "domain")
        host = bytes(packet[cursor : cursor + domain_length]).decode("idna")
        cursor += domain_length
    else:
        raise ProtocolError(f"unsupported SOCKS5 ATYP in UDP response: {atyp}")

    require_available(packet, cursor, 2, "destination port")
    port = struct.unpack_from("!H", packet, cursor)[0]
    cursor += 2
    return ParsedDatagram(Endpoint(host, port, atyp), cursor, bytes(packet[cursor:]))


def seeded_payload(size: int, seed: int) -> bytes:
    result = bytearray()
    block = 0
    prefix = f"nobrand-rfc1928-reference:{size}:{seed}:".encode("ascii")
    while len(result) < size:
        result.extend(hashlib.sha256(prefix + str(block).encode("ascii")).digest())
        block += 1
    return bytes(result[:size])


def payload_diff(expected: bytes, actual: bytes) -> tuple[int, int | None, int | None]:
    common = min(len(expected), len(actual))
    differing = [index for index in range(common) if expected[index] != actual[index]]
    if len(expected) != len(actual):
        differing.extend(range(common, max(len(expected), len(actual))))
    if not differing:
        return 0, None, None
    return len(differing), differing[0], differing[-1]


def relay_socket(endpoint: Endpoint, proxy_host: str, timeout: float) -> tuple[socket.socket, tuple[Any, ...]]:
    host = proxy_host if endpoint.host in ("0.0.0.0", "::") else endpoint.host
    addresses = socket.getaddrinfo(host, endpoint.port, type=socket.SOCK_DGRAM)
    if not addresses:
        raise ProtocolError("SOCKS5 UDP relay endpoint did not resolve")
    family, socktype, protocol, _, sockaddr = addresses[0]
    datagram = socket.socket(family, socktype, protocol)
    datagram.settimeout(timeout)
    return datagram, sockaddr


def run_trial(args: argparse.Namespace, size: int, attempt: int) -> dict[str, Any]:
    seed = args.seed_base + size * 1000 + attempt
    expected = seeded_payload(size, seed)
    result: dict[str, Any] = {
        "SIZE": size,
        "ATTEMPT": attempt,
        "SEED": seed,
        "STATUS": "ERROR",
        "SOCKS_HEADER_LENGTH": None,
        "PAYLOAD_OFFSET": None,
        "EXPECTED_PAYLOAD_LENGTH": len(expected),
        "EXPECTED_PAYLOAD_SHA256": hashlib.sha256(expected).hexdigest(),
        "PARSED_PAYLOAD_LENGTH": None,
        "PARSED_PAYLOAD_SHA256": None,
        "DIFFERENCE_COUNT": None,
        "FIRST_DIFFERING_PAYLOAD_OFFSET": None,
        "LAST_DIFFERING_PAYLOAD_OFFSET": None,
        "RESPONSE_ATYP": None,
    }

    try:
        with socket.create_connection((args.proxy_host, args.proxy_port), args.timeout) as control:
            control.settimeout(args.timeout)
            endpoint = negotiate_udp_associate(control)
            datagram, sockaddr = relay_socket(endpoint, args.proxy_host, args.timeout)
            with datagram:
                datagram.sendto(build_udp_request(args.target_host, args.target_port, expected), sockaddr)
                raw, _ = datagram.recvfrom(65535)
            parsed = parse_udp_response(raw)

        count, first, last = payload_diff(expected, parsed.payload)
        result.update(
            {
                "STATUS": "PASS" if count == 0 else "MISMATCH",
                "SOCKS_HEADER_LENGTH": parsed.header_length,
                "PAYLOAD_OFFSET": parsed.header_length,
                "PARSED_PAYLOAD_LENGTH": len(parsed.payload),
                "PARSED_PAYLOAD_SHA256": hashlib.sha256(parsed.payload).hexdigest(),
                "DIFFERENCE_COUNT": count,
                "FIRST_DIFFERING_PAYLOAD_OFFSET": first,
                "LAST_DIFFERING_PAYLOAD_OFFSET": last,
                "RESPONSE_ATYP": ATYP_NAMES.get(parsed.endpoint.atyp, str(parsed.endpoint.atyp)),
                "RESPONSE_HOST": parsed.endpoint.host,
                "RESPONSE_PORT": parsed.endpoint.port,
            }
        )
    except socket.timeout:
        result["STATUS"] = "TIMEOUT"
    except (OSError, ProtocolError, UnicodeError) as error:
        result["ERROR_TYPE"] = type(error).__name__
        result["ERROR"] = str(error)
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proxy-host", default="127.0.0.1")
    parser.add_argument("--proxy-port", required=True, type=int)
    parser.add_argument("--target-host", default="127.0.0.1")
    parser.add_argument("--target-port", required=True, type=int)
    parser.add_argument("--sizes", required=True, nargs="+", type=int)
    parser.add_argument("--attempts", default=1, type=int)
    parser.add_argument("--timeout", default=5.0, type=float)
    parser.add_argument("--seed-base", default=20260831, type=int)
    args = parser.parse_args()
    if args.attempts < 1:
        parser.error("--attempts must be positive")
    if any(size < 0 or size > 65000 for size in args.sizes):
        parser.error("all --sizes must be between 0 and 65000")
    return args


def main() -> int:
    args = parse_args()
    totals: dict[str, dict[str, int]] = {}
    all_passed = True
    for size in args.sizes:
        statuses: dict[str, int] = {}
        for attempt in range(1, args.attempts + 1):
            result = run_trial(args, size, attempt)
            status = str(result["STATUS"])
            statuses[status] = statuses.get(status, 0) + 1
            all_passed = all_passed and status == "PASS"
            print(json.dumps(result, sort_keys=True, separators=(",", ":")), flush=True)
        totals[str(size)] = statuses
    print(json.dumps({"MATRIX_SUMMARY": totals}, sort_keys=True, separators=(",", ":")), flush=True)
    return 0 if all_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
