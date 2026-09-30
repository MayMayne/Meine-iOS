#!/usr/bin/env python3
"""Generate a 1024 Meine icon and AppIcon Contents.json."""
import struct, zlib
from pathlib import Path

def png(w, h, rgba_fn):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(rgba_fn(x, y))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")

def icon(x, y, n=1024):
    # snow field
    r, g, b = 250, 252, 254
    cx, cy = n * 0.5, n * 0.46
    # soft blue disc
    dx, dy = (x - cx) / n, (y - cy) / n
    d = (dx * dx + dy * dy) ** 0.5
    if d < 0.30:
        t = 1 - d / 0.30
        r = int(142 + (33 - 142) * (1 - t) * 0.15)
        g = int(202 + (158 - 202) * 0.2)
        b = int(230)
        # inner mark: open book via two quads
        bx, by = x / n, y / n
        if 0.34 < bx < 0.66 and 0.34 < by < 0.60:
            # spine
            if abs(bx - 0.5) < 0.012:
                return (30, 30, 30, 255)
            # pages
            page = 0.36 < by < 0.58 and (0.36 < bx < 0.49 or 0.51 < bx < 0.64)
            if page:
                return (255, 255, 255, 255)
            # cover edge
            if 0.345 < bx < 0.655 and 0.345 < by < 0.595:
                return (33, 158, 188, 255)
        return (int(142 * t + 250 * (1 - t)), int(202 * t + 252 * (1 - t)), int(230 * t + 254 * (1 - t)), 255)
    # corner radius mask handled by iOS; keep full square
    # faint active arc
    if 0.34 < d < 0.36 and y > n * 0.42:
        return (33, 158, 188, 255)
    return (r, g, b, 255)

root = Path("/var/minis/workspace/Meine-iOS/Meine/Assets.xcassets/AppIcon.appiconset")
root.mkdir(parents=True, exist_ok=True)
(root / "AppIcon-1024.png").write_bytes(png(1024, 1024, icon))
(root / "Contents.json").write_text("""{
  "images": [
    {"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
  ],
  "info": {"author": "xcode", "version": 1}
}
""")
print("icon", (root / "AppIcon-1024.png").stat().st_size)
