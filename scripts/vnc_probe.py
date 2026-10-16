#!/usr/bin/env python3
"""Probe an unauthenticated VNC server and optionally capture a PNG."""

from __future__ import annotations

import argparse
import binascii
import socket
import struct
import sys
import time
import zlib
from pathlib import Path


def recv_exact(sock: socket.socket, size: int) -> bytes:
    chunks: list[bytes] = []
    remaining = size
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise EOFError(f"server closed the connection with {remaining} bytes pending")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack("!I", len(payload)) + body + struct.pack(
        "!I", binascii.crc32(body) & 0xFFFFFFFF
    )


def write_png(path: Path, width: int, height: int, bgra: bytes) -> None:
    scanlines = bytearray()
    for y in range(height):
        scanlines.append(0)
        row = memoryview(bgra)[y * width * 4 : (y + 1) * width * 4]
        for x in range(0, len(row), 4):
            blue, green, red = row[x], row[x + 1], row[x + 2]
            scanlines.extend((red, green, blue))

    path.parent.mkdir(parents=True, exist_ok=True)
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack("!IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(
        signature
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(scanlines), 6))
        + png_chunk(b"IEND", b"")
    )


def negotiate(sock: socket.socket) -> tuple[int, int, str]:
    version = recv_exact(sock, 12)
    if not version.startswith(b"RFB "):
        raise RuntimeError(f"unexpected VNC banner: {version!r}")
    try:
        server_minor = int(version[8:11])
    except ValueError as exc:
        raise RuntimeError(f"invalid VNC banner: {version!r}") from exc

    client_minor = 8 if server_minor >= 7 else 3
    sock.sendall(f"RFB 003.{client_minor:03d}\n".encode("ascii"))
    if client_minor >= 7:
        count = recv_exact(sock, 1)[0]
        if count == 0:
            length = struct.unpack("!I", recv_exact(sock, 4))[0]
            reason = recv_exact(sock, length).decode("utf-8", "replace")
            raise RuntimeError(f"server rejected security negotiation: {reason}")
        security_types = recv_exact(sock, count)
        if 1 not in security_types:
            raise RuntimeError(
                f"server does not offer unauthenticated security; types={list(security_types)}"
            )
        sock.sendall(b"\x01")
        result = struct.unpack("!I", recv_exact(sock, 4))[0]
        if result != 0:
            reason = "security negotiation failed"
            if client_minor >= 8:
                length = struct.unpack("!I", recv_exact(sock, 4))[0]
                reason = recv_exact(sock, length).decode("utf-8", "replace")
            raise RuntimeError(reason)
    else:
        security_type = struct.unpack("!I", recv_exact(sock, 4))[0]
        if security_type != 1:
            raise RuntimeError(f"unsupported RFB 3.3 security type: {security_type}")

    sock.sendall(b"\x01")
    width, height = struct.unpack("!HH", recv_exact(sock, 4))
    recv_exact(sock, 16)
    name_length = struct.unpack("!I", recv_exact(sock, 4))[0]
    name = recv_exact(sock, name_length).decode("utf-8", "replace")
    return width, height, name


def receive_frame(sock: socket.socket, width: int, height: int) -> bytes:
    framebuffer = bytearray(width * height * 4)
    while True:
        message_type = recv_exact(sock, 1)[0]
        if message_type == 0:
            recv_exact(sock, 1)
            rectangle_count = struct.unpack("!H", recv_exact(sock, 2))[0]
            saw_pixels = False
            for _ in range(rectangle_count):
                x, y, rect_width, rect_height, encoding = struct.unpack(
                    "!HHHHi", recv_exact(sock, 12)
                )
                print(
                    f"Framebuffer rectangle: {rect_width}x{rect_height}+{x}+{y}, "
                    f"encoding={encoding}"
                )
                if encoding != 0:
                    raise RuntimeError(f"unexpected VNC encoding {encoding}; raw was requested")
                pixels = recv_exact(sock, rect_width * rect_height * 4)
                for row_number in range(rect_height):
                    source = row_number * rect_width * 4
                    target = ((y + row_number) * width + x) * 4
                    framebuffer[target : target + rect_width * 4] = pixels[
                        source : source + rect_width * 4
                    ]
                saw_pixels = True
            if saw_pixels:
                return bytes(framebuffer)
        elif message_type == 2:
            continue
        elif message_type == 3:
            recv_exact(sock, 3)
            length = struct.unpack("!I", recv_exact(sock, 4))[0]
            recv_exact(sock, length)
        else:
            raise RuntimeError(f"unexpected server message type {message_type}")


def capture(sock: socket.socket, width: int, height: int, frame_count: int) -> bytes:
    sock.sendall(
        struct.pack(
            "!BxxxBBBBHHHBBBxxx",
            0,
            32,
            24,
            0,
            1,
            255,
            255,
            255,
            16,
            8,
            0,
        )
    )
    sock.sendall(struct.pack("!BBHi", 2, 0, 1, 0))
    framebuffer = b""
    for frame_number in range(1, frame_count + 1):
        if frame_number > 1:
            time.sleep(0.5)
        print(f"Requesting framebuffer {frame_number}/{frame_count}")
        sock.sendall(struct.pack("!BBHHHH", 3, 0, 0, 0, width, height))
        framebuffer = receive_frame(sock, width, height)
    return framebuffer


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--frames", type=int, default=3)
    args = parser.parse_args()

    try:
        with socket.create_connection((args.host, args.port), args.timeout) as sock:
            sock.settimeout(args.timeout)
            width, height, name = negotiate(sock)
            print(f"VNC ready: {name!r}, {width}x{height}, {args.host}:{args.port}")
            if args.output:
                framebuffer = capture(sock, width, height, max(1, args.frames))
                write_png(args.output, width, height, framebuffer)
                print(f"Screenshot saved: {args.output}")
    except (OSError, EOFError, RuntimeError) as exc:
        print(f"VNC probe failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
