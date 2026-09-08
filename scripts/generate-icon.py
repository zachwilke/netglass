#!/usr/bin/env python3
"""Rasterize a calm glass-network macOS app icon. No third-party deps."""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "Netglass" / "Assets.xcassets" / "AppIcon.appiconset"


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix(c0: tuple[float, ...], c1: tuple[float, ...], t: float) -> tuple[float, ...]:
    return tuple(lerp(a, b, t) for a, b in zip(c0, c1))


def clamp(v: float) -> float:
    return 0.0 if v < 0 else 1.0 if v > 1 else v


def superellipse(nx: float, ny: float, n: float = 4.2) -> float:
    return abs(nx) ** n + abs(ny) ** n


def circle(px: float, py: float, cx: float, cy: float, r: float) -> float:
    return math.hypot(px - cx, py - cy) - r


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgba[y * width * 4 : (y + 1) * width * 4] for y in range(height))
    png = b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)),
            chunk(b"IDAT", zlib.compress(raw, 9)),
            chunk(b"IEND", b""),
        ]
    )
    path.write_bytes(png)


def sample(u: float, v: float) -> tuple[int, int, int, int]:
    nx = (u - 0.5) * 2
    ny = (v - 0.5) * 2
    d = superellipse(nx, ny)
    aa = 1.0 - smoothstep(0.92, 1.02, d)
    if aa <= 0:
        return (0, 0, 0, 0)

    ink = (0.07, 0.08, 0.10)
    slate = (0.14, 0.18, 0.22)
    glacier = (0.55, 0.72, 0.80)
    frost = (0.86, 0.90, 0.93)

    radial = clamp(1.15 - math.hypot(nx * 0.9, ny * 1.05))
    base = mix(ink, slate, radial)
    sheen = clamp(0.55 - (nx * 0.35 + ny * 0.75 + 0.15))
    color = mix(base, frost, sheen * 0.18)
    rim = smoothstep(0.78, 0.96, d)
    color = mix(color, glacier, rim * 0.28)

    nodes = [(0.34, 0.38, 0.055), (0.68, 0.32, 0.05), (0.58, 0.68, 0.06)]
    pairs = [(0, 1), (1, 2), (0, 2)]
    for a, b in pairs:
        x1, y1, _ = nodes[a]
        x2, y2, _ = nodes[b]
        vx, vy = x2 - x1, y2 - y1
        length = math.hypot(vx, vy) or 1
        t = clamp(((u - x1) * vx + (v - y1) * vy) / (length * length))
        px, py = x1 + vx * t, y1 + vy * t
        dist = math.hypot(u - px, v - py)
        line = 1.0 - smoothstep(0.0, 0.012, dist)
        color = mix(color, glacier, line * 0.55)

    for x, y, r in nodes:
        dist = circle(u, v, x, y, r)
        fill = 1.0 - smoothstep(-0.01, 0.01, dist)
        glow = 1.0 - smoothstep(-0.02, 0.05, dist)
        color = mix(color, glacier, glow * 0.25)
        color = mix(color, frost, fill * 0.85)
        highlight = 1.0 - smoothstep(0.0, r * 0.7, math.hypot(u - (x - r * 0.25), v - (y - r * 0.28)))
        color = mix(color, (1, 1, 1), fill * highlight * 0.35)

    r, g, b = (clamp(c) for c in color)
    return (int(r * 255), int(g * 255), int(b * 255), int(aa * 255))


def render(size: int, supersample: int = 3) -> bytes:
    hi = size * supersample
    acc = [[0, 0, 0, 0] for _ in range(size * size)]
    for y in range(hi):
        for x in range(hi):
            u = (x + 0.5) / hi
            v = (y + 0.5) / hi
            px, py, pz, pa = sample(u, v)
            ox, oy = x // supersample, y // supersample
            i = oy * size + ox
            acc[i][0] += px
            acc[i][1] += py
            acc[i][2] += pz
            acc[i][3] += pa
    div = supersample * supersample
    out = bytearray()
    for r, g, b, a in acc:
        out.extend((r // div, g // div, b // div, a // div))
    return bytes(out)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    cache: dict[int, bytes] = {}
    for name, size in sizes.items():
        if size not in cache:
            ss = 4 if size <= 64 else 3 if size <= 256 else 2
            cache[size] = render(size, supersample=ss)
        write_png(OUT / name, size, size, cache[size])
        print(f"wrote {name}")


if __name__ == "__main__":
    main()
