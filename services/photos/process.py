"""
Deterministic batch photo processing and manifest reconciliation.
"""

from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path
import sys
from typing import Any

# Support running directly as a script or as a module
if __package__ is None or __package__ == "":
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
    from services.photos.manifest import reconcile_manifest
else:
    from .manifest import reconcile_manifest

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [Photos] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("photos.process")


def load_env_file(path: Path) -> None:
    """Load key-value environment variables from file if present and not already set."""
    if not path.is_file():
        return
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip("'\"")
                if k not in os.environ:
                    os.environ[k] = v
    except Exception:
        pass


def run_batch_process(
    incoming_dir: Path,
    processed_dir: Path,
    manifest_path: Path,
    max_dimension: int = 1920,
    quality: int = 85,
) -> list[dict[str, Any]]:
    """
    Execute deterministic one-shot batch photo reconciliation.
    """
    logger.info("Starting deterministic batch photo reconciliation:")
    logger.info("  Incoming:  %s", incoming_dir)
    logger.info("  Processed: %s", processed_dir)
    logger.info("  Manifest:  %s", manifest_path)
    logger.info("  Max size:  %dpx | Quality: %d", max_dimension, quality)

    try:
        incoming_dir.mkdir(parents=True, exist_ok=True)
        processed_dir.mkdir(parents=True, exist_ok=True)
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
    except PermissionError as e:
        logger.warning(
            "Could not create directories via mkdir (%s). Checking if they already exist...", e
        )
        if not (incoming_dir.is_dir() and processed_dir.is_dir()):
            logger.error(
                "Required photo directories do not exist and could not be created: incoming=%s, processed=%s. "
                "Ensure parent directory '%s' has appropriate write permissions for UID %s.",
                incoming_dir,
                processed_dir,
                incoming_dir.parent,
                os.getuid(),
            )
            raise

    items = reconcile_manifest(
        incoming_dir=incoming_dir,
        processed_dir=processed_dir,
        manifest_path=manifest_path,
        max_dimension=max_dimension,
        quality=quality,
    )

    logger.info("Batch processing complete: %d active photo(s) in manifest.", len(items))
    return items


def main() -> None:
    # Load canonical environment file if present on host
    load_env_file(Path("/etc/sashframe/sashframe.env"))

    repo_root = Path(__file__).resolve().parent.parent.parent

    default_incoming = Path(os.environ.get("PHOTO_INPUT_DIR", repo_root / "data" / "photos" / "incoming"))
    default_processed = Path(os.environ.get("PHOTO_OUTPUT_DIR", repo_root / "data" / "photos" / "processed"))
    default_manifest = Path(os.environ.get("PHOTO_MANIFEST", repo_root / "data" / "photos" / "manifest.json"))
    default_max_size = int(os.environ.get("PHOTO_MAX_SIZE", "1920"))
    default_quality = int(os.environ.get("PHOTO_QUALITY", "85"))

    parser = argparse.ArgumentParser(description="Deterministic batch photo ingestion and manifest generator.")
    parser.add_argument(
        "--incoming",
        type=Path,
        default=default_incoming,
        help="Directory containing source images",
    )
    parser.add_argument(
        "--processed",
        type=Path,
        default=default_processed,
        help="Directory for output WebP images",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=default_manifest,
        help="Path to manifest JSON output",
    )
    parser.add_argument(
        "--max-size",
        type=int,
        default=default_max_size,
        help="Maximum width or height of processed image",
    )
    parser.add_argument(
        "--quality",
        type=int,
        default=default_quality,
        help="WebP quality (0-100)",
    )

    args = parser.parse_args()

    try:
        run_batch_process(
            incoming_dir=args.incoming.resolve(),
            processed_dir=args.processed.resolve(),
            manifest_path=args.manifest.resolve(),
            max_dimension=args.max_size,
            quality=args.quality,
        )
    except Exception as e:
        logger.error("Fatal error during batch photo processing: %s", e, exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
