#!/usr/bin/env python3
"""Fetch pinned CC-BY vehicle models and preserve their original attribution."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "assets-lock.json"
ASSET_DIR = ROOT / "assets" / "cars"
RAW_BASE = "https://raw.githubusercontent.com/supercar3d/supercar_3D_asssets/main/"


def fetch(url: str) -> bytes:
    req = Request(url, headers={"User-Agent": "TurboTrailsAssetImporter/1.0"})
    with urlopen(req, timeout=45) as response:
        if response.status != 200:
            raise RuntimeError(f"Download failed ({response.status}): {url}")
        return response.read()


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def main() -> None:
    spec = json.loads(LOCK.read_text(encoding="utf-8"))
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    lic_dir = ASSET_DIR / "licenses"
    lic_dir.mkdir(parents=True, exist_ok=True)
    manifest = {"source_repository": spec["source_repository"], "license": spec["license"], "models": []}
    credits = [
        "# Third-party vehicle asset credits",
        "",
        "These models are sourced from the upstream community collection and are identified there as Creative Commons Attribution 4.0 International (CC BY 4.0). Original licence notices are retained under assets/cars/licenses.",
        "",
        "Upstream collection: " + spec["source_repository"],
        "Licence text: https://creativecommons.org/licenses/by/4.0/",
        "",
        "The car meshes may contain manufacturer marks. Vehicle trademarks and other third-party rights remain with their respective owners.",
        "",
    ]
    for item in spec["models"]:
        mesh = fetch(RAW_BASE + item["source_path"])
        actual_git_sha = git_blob_sha(mesh)
        if actual_git_sha.lower() != item["source_git_blob_sha"].lower():
            raise RuntimeError(f"Pinned source changed for {item['game_name']}: expected {item['source_git_blob_sha']}, got {actual_git_sha}")
        if len(mesh) < 10_000 or not mesh.startswith(b"glTF"):
            raise RuntimeError(f"Invalid GLB payload for {item['game_name']}")
        (ASSET_DIR / item["file"]).write_bytes(mesh)
        license_text = fetch(RAW_BASE + item["license_path"]).decode("utf-8", "replace").strip() + "\n"
        (lic_dir / (Path(item["file"]).stem + ".txt")).write_text(license_text, encoding="utf-8")
        mesh_sha256 = hashlib.sha256(mesh).hexdigest()
        manifest["models"].append({
            "game_name": item["game_name"], "file": item["file"],
            "source_path": item["source_path"], "source_git_blob_sha": actual_git_sha,
            "sha256": mesh_sha256, "size_bytes": len(mesh),
            "original_title": item["original_title"], "creator": item["creator"],
            "source_url": item["source_url"], "license": spec["license"],
        })
        credits.append(
            f"## {item['game_name']} — {item['original_title']}\n"
            f"- Creator: {item['creator']}\n"
            f"- Original model: {item['source_url']}\n"
            f"- Licence: CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/\n"
            f"- Upstream file: {item['source_path']}\n"
            f"- Upstream source SHA-256: {mesh_sha256}\n"
        )
        print(f"Verified {item['game_name']}: {len(mesh):,} bytes; Git blob SHA matches the pin")
    (ASSET_DIR / "asset-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (ROOT / "ASSET_CREDITS.md").write_text("\n".join(credits) + "\n", encoding="utf-8")
    print(f"Imported {len(manifest['models'])} models; manifest and attribution written.")


if __name__ == "__main__":
    main()
