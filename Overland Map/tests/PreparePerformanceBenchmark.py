"""Capture runtime source identity and make the local-only 4000x2000 benchmark image."""
import argparse
import hashlib
import json
import struct
import subprocess
import zlib
from pathlib import Path


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", default="output/overland-performance")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    dest = root / args.output
    dest.mkdir(parents=True, exist_ok=True)
    files = {}
    for path in sorted((root / "Overland Map").glob("*.lua")):
        body = path.read_text(encoding="utf-8").replace("\r\n", "\n").encode("ascii")
        checksum = 5381
        for byte in body:
            checksum = (checksum * 33 + byte) % 4294967296
        files[path.stem] = {"sha256": hashlib.sha256(body).hexdigest(),
                            "length": len(body), "checksum": checksum}
    manifest = {"head": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(), "files": files}
    (dest / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    patch = subprocess.check_output(["git", "diff", "HEAD", "--", ":(glob)Overland Map/*.lua"], cwd=root)
    (dest / "runtime.patch").write_bytes(patch)

    width, height = 4000, 2000
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            grid = x % 400 < 3 or y % 200 < 3
            row.extend((70, 90, 80) if grid else (42, 57, 49))
        rows.append(bytes(row))
    image = b"\x89PNG\r\n\x1a\n"
    image += chunk(b"IHDR", struct.pack(">2I5B", width, height, 8, 2, 0, 0, 0))
    image += chunk(b"IDAT", zlib.compress(b"".join(rows), 6))
    image += chunk(b"IEND", b"")
    (dest / "fixture-4000x2000.png").write_bytes(image)
    print(json.dumps({"files": len(files), "head": manifest["head"], "pngBytes": len(image)}))


if __name__ == "__main__":
    main()
