#!/usr/bin/env python3
"""Re-encode a PNG losslessly with per-row filter selection and zlib level 9 (stdlib + numpy, pixels via sips/BMP).
Usage: optimize_png.py file.png   (no-op, exit 0, if numpy or sips is unavailable)"""
import struct, subprocess, sys, tempfile, zlib, os

def main(path):
    try:
        import numpy as np
    except ImportError:
        return
    with tempfile.TemporaryDirectory() as d:
        bmp = os.path.join(d, "x.bmp")
        if subprocess.run(["sips", "-s", "format", "bmp", path, "--out", bmp], capture_output=True).returncode != 0:
            return
        raw = open(bmp, "rb").read()
    off = struct.unpack_from("<I", raw, 10)[0]
    w, h = struct.unpack_from("<ii", raw, 18)
    bpp = struct.unpack_from("<H", raw, 28)[0]
    top_down = h < 0
    h = abs(h)
    if bpp not in (24, 32):
        return
    ch = bpp // 8
    stride = (w * ch + 3) // 4 * 4
    a = np.frombuffer(raw, dtype=np.uint8, offset=off, count=stride * h).reshape(h, stride)[:, : w * ch]
    if not top_down:
        a = a[::-1]
    a = a.reshape(h, w, ch)[:, :, [2, 1, 0] + ([3] if ch == 4 else [])]  # BGR(A) -> RGB(A)
    if ch == 4 and (a[:, :, 3] == 255).all():
        a = a[:, :, :3]
        ch = 3
    a = np.ascontiguousarray(a).reshape(h, w * ch)
    bpx = ch
    zero = np.zeros((1, w * ch), dtype=np.uint8)
    up = (a.astype(np.int16) - np.vstack([zero, a[:-1]]).astype(np.int16)).astype(np.uint8)
    left = np.zeros_like(a)
    left[:, bpx:] = a[:, :-bpx]
    sub = (a.astype(np.int16) - left.astype(np.int16)).astype(np.uint8)
    def cost(x):
        s = x.astype(np.int16)
        s = np.where(s > 127, 256 - s, s)
        return s.sum(axis=1)
    costs = np.stack([cost(a), cost(sub), cost(up)])
    pick = costs.argmin(axis=0)
    out = bytearray()
    cand = [a, sub, up]
    for y in range(h):
        k = int(pick[y])
        out.append(k)
        out += cand[k][y].tobytes()
    def chunk(t, data):
        c = struct.pack(">I", len(data)) + t + data
        return c + struct.pack(">I", zlib.crc32(t + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2 if ch == 3 else 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(out), 9)) + chunk(b"IEND", b"")
    if len(png) < os.path.getsize(path):
        open(path, "wb").write(png)

if __name__ == "__main__":
    main(sys.argv[1])
