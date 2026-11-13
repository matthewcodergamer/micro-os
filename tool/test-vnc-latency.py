#!/usr/bin/env python3
"""Measure local RFB handshake and noVNC HTTP latency inside the PRoot guest.

This is a transport/endpoint check, not a full rendered-frame benchmark.
Run after the desktop stack is active:
    python3 /root/.microos/test-vnc-latency.py
or from the repository:
    python3 tool/test-vnc-latency.py
"""
from __future__ import annotations

import math
import socket
import statistics
import sys
import time

HOST = "127.0.0.1"
RFB_PORT = 5900
HTTP_PORT = 6080
SAMPLES = int(sys.argv[1]) if len(sys.argv) > 1 else 20


def read_until(sock: socket.socket, marker: bytes, limit: int = 65536) -> bytes:
    data = bytearray()
    while marker not in data and len(data) < limit:
        part = sock.recv(4096)
        if not part:
            break
        data.extend(part)
    return bytes(data)


def measure_rfb() -> float:
    started = time.perf_counter()
    with socket.create_connection((HOST, RFB_PORT), timeout=3) as sock:
        sock.settimeout(3)
        banner = bytearray()
        while len(banner) < 12:
            chunk = sock.recv(12 - len(banner))
            if not chunk:
                raise RuntimeError("RFB server closed before sending its 12-byte banner")
            banner.extend(chunk)
        if not banner.startswith(b"RFB "):
            raise RuntimeError(f"Unexpected RFB banner: {bytes(banner)!r}")
    return (time.perf_counter() - started) * 1000


def measure_novnc_http() -> tuple[float, int]:
    started = time.perf_counter()
    with socket.create_connection((HOST, HTTP_PORT), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(
            b"GET /vnc.html HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"Connection: close\r\n\r\n"
        )
        response = read_until(sock, b"\r\n\r\n")
    if not response:
        raise RuntimeError("noVNC HTTP endpoint returned no response")
    status = response.split(b"\r\n", 1)[0].decode("ascii", "replace")
    if " 200 " not in status:
        raise RuntimeError(f"noVNC HTTP returned: {status}")
    return (time.perf_counter() - started) * 1000, 200


def report(name: str, values: list[float]) -> None:
    ordered = sorted(values)
    p95 = ordered[min(len(ordered) - 1, math.ceil(len(ordered) * 0.95) - 1)]
    print(
        f"{name}: median={statistics.median(values):.2f} ms "
        f"p95={p95:.2f} ms min={ordered[0]:.2f} ms max={ordered[-1]:.2f} ms"
    )


def main() -> int:
    if SAMPLES < 3 or SAMPLES > 200:
        print("Choose between 3 and 200 samples.", file=sys.stderr)
        return 2
    rfb: list[float] = []
    http: list[float] = []
    try:
        for _ in range(SAMPLES):
            rfb.append(measure_rfb())
            http_ms, _ = measure_novnc_http()
            http.append(http_ms)
    except (OSError, RuntimeError) as error:
        print(f"VNC latency test failed: {error}", file=sys.stderr)
        print("Check that start-desktop.sh has started X11, x11vnc :5900 and noVNC :6080.", file=sys.stderr)
        return 1

    print(f"Local desktop endpoint test ({SAMPLES} samples; host={HOST})")
    report("RFB TCP + server banner (5900)", rfb)
    report("noVNC HTTP response (6080)", http)
    print("Note: these numbers do not measure screen encoding, WebView decoding, or touch-to-photon frame latency.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
