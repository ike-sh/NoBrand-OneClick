#!/usr/bin/env python3
import argparse
import selectors
import signal
import socket


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", required=True)
    parser.add_argument("--tcp-port", type=int, required=True)
    parser.add_argument("--udp-port", type=int, required=True)
    return parser.parse_args()


def main():
    args = parse_args()
    selector = selectors.DefaultSelector()
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    tcp.bind((args.bind, args.tcp_port))
    tcp.listen(32)
    tcp.setblocking(False)
    selector.register(tcp, selectors.EVENT_READ, "tcp")

    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    udp.bind((args.bind, args.udp_port))
    udp.setblocking(False)
    selector.register(udp, selectors.EVENT_READ, "udp")

    try:
        while not stopping:
            for key, _mask in selector.select(timeout=0.25):
                if key.data == "tcp":
                    conn, _peer = tcp.accept()
                    conn.settimeout(2)
                    try:
                        payload = conn.recv(65535)
                        if payload:
                            conn.sendall(payload)
                    finally:
                        conn.close()
                else:
                    payload, peer = udp.recvfrom(65535)
                    udp.sendto(payload, peer)
    finally:
        selector.close()
        tcp.close()
        udp.close()


if __name__ == "__main__":
    main()
