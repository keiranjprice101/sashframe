"""
Image validation, EXIF normalization, resizing, and WebP conversion.
"""

from __future__ import annotations

import hashlib
import logging
import os
from pathlib import Path
from typing import Any, Optional, Tuple
from PIL import Image, ImageOps, UnidentifiedImageError

logger = logging.getLogger("photos.processing")

SUPPORTED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}

# TODO: Add .heic / .heif support using pillow-heif once system libraries are configured.
# Example:
#   import pillow_heif
#   pillow_heif.register_heif_opener()


def compute_file_hash(filepath: Path) -> str:
    """Compute SHA-256 hash of file content."""
    sha = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            sha.update(chunk)
    return sha.hexdigest()


def is_supported_file(filepath: Path) -> bool:
    """Check if file has a supported image extension and is not a hidden/temp file."""
    if filepath.name.startswith("."):
        return False
    return filepath.suffix.lower() in SUPPORTED_EXTENSIONS


def validate_image_readable(filepath: Path, log_warning: bool = True) -> bool:
    """
    Verify that the image file can be opened and its integrity verified by Pillow.
    Returns True if valid, False otherwise.
    """
    if not is_supported_file(filepath):
        return False
    try:
        with Image.open(filepath) as img:
            img.verify()
        return True
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError) as e:
        if log_warning:
            logger.warning("Unreadable or corrupt image file '%s': %s", filepath.name, e)
        return False


def process_image(
    source_path: Path,
    output_dir: Path,
    max_dimension: int = 1920,
    quality: int = 85,
) -> Optional[dict[str, Any]]:
    """
    Process source image:
    1. Validates image integrity.
    2. Corrects EXIF orientation.
    3. Normalizes color channels (RGBA/RGB).
    4. Resizes preserving aspect ratio (longest dimension <= 1920px, no upscaling).
    5. Converts to WebP with sensible quality (85) and stripped metadata.
    6. Writes output atomically to output_dir/<hash[:12]>.webp.

    Returns a dict with image metadata or None on failure.
    """
    if not source_path.exists() or not source_path.is_file():
        return None

    if not is_supported_file(source_path):
        logger.debug("Skipping unsupported file: %s", source_path.name)
        return None

    # Compute content hash
    try:
        content_hash = compute_file_hash(source_path)
    except Exception as e:
        logger.warning("Failed to compute hash for '%s': %s", source_path.name, e)
        return None

    file_id = content_hash[:12]
    target_filename = f"{file_id}.webp"
    target_path = output_dir / target_filename

    # If processed file already exists and is valid, return cached metadata (idempotent)
    if target_path.exists():
        try:
            with Image.open(target_path) as cached_img:
                width, height = cached_img.size
            return {
                "id": file_id,
                "src": f"/photos/{target_filename}",
                "filename": target_filename,
                "sourceName": source_path.name,
                "width": width,
                "height": height,
                "hash": content_hash,
            }
        except Exception:
            logger.warning("Existing processed file '%s' corrupted, regenerating...", target_filename)

    # Validate image before loading full data
    if not validate_image_readable(source_path):
        return None

    temp_path: Optional[Path] = None
    try:
        # Open and load image for editing
        with Image.open(source_path) as raw_img:
            # 1. EXIF orientation correction
            img = ImageOps.exif_transpose(raw_img)
            if img is None:
                img = raw_img.copy()

            # 2. Color mode handling
            if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
                img = img.convert("RGBA")
            elif img.mode != "RGB":
                img = img.convert("RGB")

            # 3. Resize: preserve aspect ratio, longest dimension <= max_dimension, no upscaling
            orig_w, orig_h = img.size
            if max(orig_w, orig_h) > max_dimension:
                img.thumbnail((max_dimension, max_dimension), Image.Resampling.LANCZOS)

            final_w, final_h = img.size

            # 4. Atomic write
            output_dir.mkdir(parents=True, exist_ok=True)
            temp_path = output_dir / f".tmp_{target_filename}"

            # Save to WebP (stripping EXIF metadata by omitting exif parameter)
            img.save(
                temp_path,
                format="WEBP",
                quality=quality,
                method=4,
            )

        # Atomic rename onto target path
        os.replace(temp_path, target_path)
        logger.info("Processed: %s -> %s (%dx%d)", source_path.name, target_filename, final_w, final_h)

        return {
            "id": file_id,
            "src": f"/photos/{target_filename}",
            "filename": target_filename,
            "sourceName": source_path.name,
            "width": final_w,
            "height": final_h,
            "hash": content_hash,
        }

    except Exception as e:
        logger.error("Error processing '%s': %s", source_path.name, e, exc_info=True)
        if temp_path and temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass
        return None
