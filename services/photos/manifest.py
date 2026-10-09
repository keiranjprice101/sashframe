"""
Manifest generation and maintenance for processed photos.
"""

from __future__ import annotations

from datetime import datetime, timezone
import json
import logging
import os
from pathlib import Path
from typing import Any, Optional

from .processing import is_supported_file, process_image

logger = logging.getLogger("photos.manifest")
REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def load_manifest(manifest_path: Path) -> list[dict[str, Any]]:
    """Load existing manifest.json, or return an empty list if missing or invalid."""
    if not manifest_path.exists() or not manifest_path.is_file():
        return []
    try:
        with open(manifest_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                return data
    except Exception as e:
        logger.warning("Failed to parse manifest at %s: %s", manifest_path, e)
    return []


def save_manifest(manifest_path: Path, items: list[dict[str, Any]]) -> None:
    """Atomically write manifest items to JSON, and sync to dist/ if present."""
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = manifest_path.parent / f".tmp_{manifest_path.name}"

    try:
        with open(temp_path, "w", encoding="utf-8") as f:
            json.dump(items, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(temp_path, manifest_path)
    except Exception as e:
        logger.error("Failed to save manifest to %s: %s", manifest_path, e)
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass

    # If production build dist/ directory exists, sync manifest there too
    dist_manifest = REPO_ROOT / "dist" / "api" / "photos"
    if dist_manifest.parent.exists() and dist_manifest.parent.is_dir():
        try:
            temp_dist = dist_manifest.parent / f".tmp_{dist_manifest.name}"
            with open(temp_dist, "w", encoding="utf-8") as f:
                json.dump(items, f, indent=2, ensure_ascii=False)
                f.write("\n")
            os.replace(temp_dist, dist_manifest)
        except Exception as e:
            logger.warning("Could not sync manifest to %s: %s", dist_manifest, e)


def reconcile_manifest(
    incoming_dir: Path,
    processed_dir: Path,
    manifest_path: Path,
    max_dimension: int = 1920,
    quality: int = 85,
) -> list[dict[str, Any]]:
    """
    Scan incoming directory, process any new or modified images, remove deleted entries,
    clean up orphaned processed files, and atomically update manifest.json.
    """
    incoming_dir.mkdir(parents=True, exist_ok=True)
    processed_dir.mkdir(parents=True, exist_ok=True)

    # 1. Load existing manifest to preserve existing timestamps when possible
    existing_items = load_manifest(manifest_path)
    existing_by_source: dict[str, dict[str, Any]] = {
        item.get("sourceName", ""): item for item in existing_items if "sourceName" in item
    }

    # 2. Find and process all incoming images
    active_items: list[dict[str, Any]] = []
    active_filenames: set[str] = set()

    incoming_files = sorted(
        [p for p in incoming_dir.iterdir() if p.is_file() and is_supported_file(p)],
        key=lambda p: p.name.lower(),
    )

    now_iso = datetime.now(timezone.utc).isoformat()

    seen_ids: set[str] = set()

    for file_path in incoming_files:
        meta = process_image(file_path, processed_dir, max_dimension=max_dimension, quality=quality)
        if meta is None:
            # Skip invalid or corrupt images without failing the whole batch
            continue

        if meta["id"] in seen_ids:
            logger.debug("Skipping duplicate content for '%s' (hash matches %s)", meta["sourceName"], meta["id"])
            continue
        seen_ids.add(meta["id"])

        source_name = meta["sourceName"]
        prev_entry = existing_by_source.get(source_name)

        # Retain previous updatedAt if the image content hash hasn't changed
        if prev_entry and prev_entry.get("id") == meta["id"] and "updatedAt" in prev_entry:
            updated_at = prev_entry["updatedAt"]
        else:
            updated_at = now_iso

        item = {
            "id": meta["id"],
            "src": meta["src"],
            "sourceName": source_name,
            "width": meta["width"],
            "height": meta["height"],
            "updatedAt": updated_at,
        }
        active_items.append(item)
        active_filenames.add(meta["filename"])

    # 3. Clean up orphaned processed files (e.g. source image removed or replaced)
    for p in processed_dir.iterdir():
        if p.is_file() and not p.name.startswith("."):
            if p.suffix.lower() == ".webp" and p.name not in active_filenames:
                try:
                    p.unlink()
                    logger.info("Removed orphaned processed photo: %s", p.name)
                except OSError as e:
                    logger.warning("Could not delete orphan '%s': %s", p.name, e)

    # 4. Sync processed webp images into dist/photos/ if dist/ exists
    dist_photos_dir = REPO_ROOT / "dist" / "photos"
    if dist_photos_dir.exists() and dist_photos_dir.is_dir():
        import shutil
        for fn in active_filenames:
            src = processed_dir / fn
            dst = dist_photos_dir / fn
            if src.exists() and not dst.exists():
                try:
                    shutil.copy2(src, dst)
                    logger.info("Synced photo to production dist: %s", fn)
                except Exception as e:
                    logger.warning("Could not sync photo to %s: %s", dst, e)

        for p in dist_photos_dir.iterdir():
            if p.is_file() and p.suffix.lower() == ".webp" and p.name not in active_filenames:
                try:
                    p.unlink()
                    logger.info("Removed orphaned photo from production dist: %s", p.name)
                except OSError as e:
                    logger.warning("Could not delete orphan from dist '%s': %s", p.name, e)

    # 5. Save updated manifest
    save_manifest(manifest_path, active_items)
    logger.info("Manifest reconciled: %d active photos", len(active_items))

    return active_items
