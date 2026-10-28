"""Generate a nontransparent 1024px app icon using only the standard library."""
import json
import struct
import zlib
from pathlib import Path


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def generate(root: Path) -> None:
    icon = root / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    rows = bytearray()
    for y in range(1024):
        rows.append(0)
        for x in range(1024):
            field_line = (
                (abs(x - 180) < 6 or abs(x - 844) < 6) and 180 <= y <= 844
                or (abs(y - 180) < 6 or abs(y - 844) < 6) and 180 <= x <= 844
                or abs(y - 512) < 6 and 180 <= x <= 844
                or abs(((x - 512) ** 2 + (y - 512) ** 2) ** 0.5 - 110) < 6
            )
            player = (x - 400) ** 2 + (y - 680) ** 2 < 65 ** 2
            ball = (x - 650) ** 2 + (y - 350) ** 2 < 46 ** 2
            rows.extend((64, 225, 233) if player else (255, 255, 255) if field_line or ball else (13, 87, 59))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", 1024, 1024, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows)))
    png += chunk(b"IEND", b"")
    (icon / "AppIcon.png").write_bytes(png)
    (root / "Contents.json").write_text(json.dumps({"info": {"version": 1, "author": "xcode"}}))
    (icon / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"version": 1, "author": "xcode"},
    }))


if __name__ == "__main__":
    generate(Path(__file__).resolve().parents[1] / "App" / "Assets.xcassets")
