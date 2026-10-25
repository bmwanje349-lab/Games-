#!/usr/bin/env python3
"""Download verified 1K CC0 PBR textures from Poly Haven for the mobile racer."""
from __future__ import annotations
import hashlib
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets" / "environment"
BASE = "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/{slug}/{filename}"
MAPS = {
    "asphalt_track_diff_1k.jpg": ("asphalt_track", "asphalt_track_diff_1k.jpg"),
    "asphalt_track_nor_gl_1k.jpg": ("asphalt_track", "asphalt_track_nor_gl_1k.jpg"),
    "asphalt_track_rough_1k.jpg": ("asphalt_track", "asphalt_track_rough_1k.jpg"),
    "gravel_road_diff_1k.jpg": ("gravel_road", "gravel_road_diff_1k.jpg"),
    "gravel_road_nor_gl_1k.jpg": ("gravel_road", "gravel_road_nor_gl_1k.jpg"),
    "gravel_road_rough_1k.jpg": ("gravel_road", "gravel_road_rough_1k.jpg"),
    "forrest_ground_01_diff_1k.jpg": ("forrest_ground_01", "forrest_ground_01_diff_1k.jpg"),
    "forrest_ground_01_nor_gl_1k.jpg": ("forrest_ground_01", "forrest_ground_01_nor_gl_1k.jpg"),
    "forrest_ground_01_rough_1k.jpg": ("forrest_ground_01", "forrest_ground_01_rough_1k.jpg"),
}


def fetch(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "TurboTrailsMobile/1.0"})
    with urlopen(request, timeout=60) as response:
        if response.status != 200:
            raise RuntimeError(f"Texture download failed ({response.status}): {url}")
        data = response.read()
    if len(data) < 10_000 or not data.startswith(b"\xff\xd8\xff"):
        raise RuntimeError(f"Invalid JPEG texture payload: {url} ({len(data)} bytes)")
    return data


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    for output_name, (slug, filename) in MAPS.items():
        path = DEST / output_name
        url = BASE.format(slug=slug, filename=filename)
        data = fetch(url)
        path.write_bytes(data)
        print(f"{output_name}: {len(data):,} bytes sha256={hashlib.sha256(data).hexdigest()}")
    print(f"Downloaded and validated {len(MAPS)} Poly Haven CC0 PBR texture maps.")


if __name__ == "__main__":
    main()
