#!/usr/bin/env python3
"""Draws App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png.

Standard library only. The curve is OJAD's word curve for a 中高 pattern
([0,1,0], taken from the OJADKit golden fixture); opaque RGB because App Store
icons must not have an alpha channel.
"""
import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOLDEN = ROOT / "Packages/OJADKit/Tests/OJADKitTests/Fixtures/fujisaki-golden.json"
OUT = ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

SIZE = 1024
TOP, BOTTOM = (0x4B, 0x3F, 0xC9), (0x1E, 0x1A, 0x5C)
CURVE, NUCLEUS = (0xFF, 0xFF, 0xFF), (0xFF, 0x5A, 0x5F)


def catmull_rom(points, steps=40):
    out = []
    padded = [points[0]] + points + [points[-1]]
    for i in range(1, len(padded) - 2):
        p0, p1, p2, p3 = padded[i - 1 : i + 3]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                       + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
                for k in range(2)
            ))
    out.append(points[-1])
    return out


def stamp(coverage, cx, cy, radius):
    r = radius + 1
    for y in range(max(0, int(cy - r)), min(SIZE, int(cy + r) + 1)):
        row = y * SIZE
        dy = y + 0.5 - cy
        for x in range(max(0, int(cx - r)), min(SIZE, int(cx + r) + 1)):
            d = math.hypot(x + 0.5 - cx, dy)
            c = min(1.0, max(0.0, radius + 0.5 - d))
            if c > coverage[row + x]:
                coverage[row + x] = c


def main():
    samples = json.loads(GOLDEN.read_text())["word_nakadaka_010"]
    xs = [p[0] for p in samples]
    ys = [p[1] for p in samples]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    points = [
        (180 + (x - x0) / (x1 - x0) * 664, 700 - (y - y0) / (y1 - y0) * 380)
        for x, y in samples[::2] + [samples[-1]]
    ]

    curve = [0.0] * (SIZE * SIZE)
    for x, y in catmull_rom(points):
        stamp(curve, x, y, 30)

    # Red drop after the nucleus (end of the 2nd mora), as OJAD marks it.
    nucleus = [0.0] * (SIZE * SIZE)
    nx = 180 + (2 - x0) / (x1 - x0) * 664
    for i in range(48):
        stamp(nucleus, nx, 200 + i * 2.5, 16)

    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        t = y / (SIZE - 1)
        bg = [TOP[k] + (BOTTOM[k] - TOP[k]) * t for k in range(3)]
        for x in range(SIZE):
            c = curve[y * SIZE + x]
            n = nucleus[y * SIZE + x]
            px = [bg[k] * (1 - c) + CURVE[k] * c for k in range(3)]
            px = [px[k] * (1 - n) + NUCLEUS[k] * n for k in range(3)]
            rows.extend(int(round(v)) for v in px)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(png)} bytes)")


if __name__ == "__main__":
    main()
