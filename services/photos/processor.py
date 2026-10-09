"""
Watchdog filesystem event watcher for the photo ingestion pipeline.
"""

from __future__ import annotations

import argparse
import logging
import os
from pathlib import Path
import signal
import sys
import threading
import time
from typing import Optional

from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

# Support running directly as a script or as a module
if __package__ is None or __package__ == "":
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))
    from services.photos.manifest import reconcile_manifest
    from services.photos.processing import is_supported_file, validate_image_readable
else:
    from .manifest import reconcile_manifest
    from .processing import is_supported_file, validate_image_readable

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [Photos] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("photos.watcher")


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


load_env_file(Path("/etc/sashframe/sashframe.env"))


class PhotoDebounceHandler(FileSystemEventHandler):
    """
    Debounced event handler that waits for writes to complete before reconciling.
    """

    def __init__(
        self,
        incoming_dir: Path,
        processed_dir: Path,
        manifest_path: Path,
        debounce_seconds: float = 0.8,
        max_dimension: int = 1920,
        quality: int = 85,
    ) -> None:
        super().__init__()
        self.incoming_dir = incoming_dir
        self.processed_dir = processed_dir
        self.manifest_path = manifest_path
        self.debounce_seconds = debounce_seconds
        self.max_dimension = max_dimension
        self.quality = quality

        self._lock = threading.Lock()
        self._timer: Optional[threading.Timer] = None

    def _handle_relevant_event(self, event: FileSystemEvent) -> None:
        if event.is_directory:
            return

        src_path = Path(event.src_path)
        dest_path = Path(getattr(event, "dest_path", "")) if hasattr(event, "dest_path") else None

        relevant = False
        if is_supported_file(src_path):
            relevant = True
        elif dest_path and is_supported_file(dest_path):
            relevant = True
        elif event.event_type == "deleted":
            relevant = True

        if not relevant:
            return

        logger.info("Filesystem change detected: %s on %s", event.event_type, src_path.name)
        self._trigger_debounced_reconcile()

    def on_created(self, event: FileSystemEvent) -> None:
        self._handle_relevant_event(event)

    def on_modified(self, event: FileSystemEvent) -> None:
        self._handle_relevant_event(event)

    def on_deleted(self, event: FileSystemEvent) -> None:
        self._handle_relevant_event(event)

    def on_moved(self, event: FileSystemEvent) -> None:
        self._handle_relevant_event(event)

    def on_closed(self, event: FileSystemEvent) -> None:
        # IN_CLOSE_WRITE indicates file write completed
        if getattr(event, "event_type", "") == "closed":
            self._handle_relevant_event(event)

    def _trigger_debounced_reconcile(self) -> None:
        with self._lock:
            if self._timer is not None:
                self._timer.cancel()
            self._timer = threading.Timer(self.debounce_seconds, self._safe_reconcile)
            self._timer.daemon = True
            self._timer.start()

    def _wait_for_file_settled(self, file_path: Path, max_retries: int = 5, check_interval: float = 0.3) -> bool:
        """
        Ensure file has finished writing by checking size stability and readability.
        """
        if not file_path.exists():
            return False

        last_size = -1
        for attempt in range(max_retries):
            try:
                current_size = file_path.stat().st_size
                if current_size > 0 and current_size == last_size:
                    # Size is stable, verify with Pillow (silently during settling)
                    if validate_image_readable(file_path, log_warning=False):
                        return True
                last_size = current_size
            except OSError:
                pass
            time.sleep(check_interval)

        return validate_image_readable(file_path, log_warning=False)

    def _safe_reconcile(self) -> None:
        with self._lock:
            self._timer = None

        logger.info("Reconciling photos directory...")
        # Check files currently in incoming to make sure incoming transfers are complete
        try:
            for p in self.incoming_dir.iterdir():
                if p.is_file() and is_supported_file(p):
                    self._wait_for_file_settled(p)

            items = reconcile_manifest(
                self.incoming_dir,
                self.processed_dir,
                self.manifest_path,
                max_dimension=self.max_dimension,
                quality=self.quality,
            )
            logger.info("Photo ingestion updated: %d active photos in manifest.", len(items))
        except Exception as e:
            logger.error("Error during photo reconciliation: %s", e, exc_info=True)


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent.parent

    default_incoming = Path(os.environ.get("PHOTO_INPUT_DIR", repo_root / "data" / "photos" / "incoming"))
    default_processed = Path(os.environ.get("PHOTO_OUTPUT_DIR", repo_root / "data" / "photos" / "processed"))
    default_manifest = Path(os.environ.get("PHOTO_MANIFEST", repo_root / "data" / "photos" / "manifest.json"))
    default_max_size = int(os.environ.get("PHOTO_MAX_SIZE", "1920"))
    default_quality = int(os.environ.get("PHOTO_QUALITY", "85"))

    parser = argparse.ArgumentParser(description="Watch incoming directory and ingest photos.")
    parser.add_argument(
        "--incoming",
        type=Path,
        default=default_incoming,
        help="Directory to watch for incoming images",
    )
    parser.add_argument(
        "--processed",
        type=Path,
        default=default_processed,
        help="Directory for processed WebP images",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=default_manifest,
        help="Path to photo manifest JSON",
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

    incoming_dir: Path = args.incoming.resolve()
    processed_dir: Path = args.processed.resolve()
    manifest_path: Path = args.manifest.resolve()
    max_dimension: int = args.max_size
    quality: int = args.quality

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

    logger.info("Starting Photo Ingestion Watcher")
    logger.info("  Incoming:  %s", incoming_dir)
    logger.info("  Processed: %s", processed_dir)
    logger.info("  Manifest:  %s", manifest_path)
    logger.info("  Max size:  %dpx | Quality: %d", max_dimension, quality)

    # Initial scan to ensure any existing photos are ingested
    logger.info("Running initial reconciliation scan...")
    try:
        initial_items = reconcile_manifest(
            incoming_dir,
            processed_dir,
            manifest_path,
            max_dimension=max_dimension,
            quality=quality,
        )
        logger.info("Initial scan complete: %d photos loaded.", len(initial_items))
    except Exception as e:
        logger.error("Failed during initial scan: %s", e, exc_info=True)

    event_handler = PhotoDebounceHandler(
        incoming_dir=incoming_dir,
        processed_dir=processed_dir,
        manifest_path=manifest_path,
        max_dimension=max_dimension,
        quality=quality,
    )

    observer = Observer()
    observer.schedule(event_handler, str(incoming_dir), recursive=False)
    observer.start()

    stop_event = threading.Event()

    def handle_shutdown(signum, frame):
        logger.info("Shutdown signal received (%s). Stopping watcher...", signum)
        stop_event.set()

    signal.signal(signal.SIGINT, handle_shutdown)
    signal.signal(signal.SIGTERM, handle_shutdown)

    logger.info("Watcher active. Drop images into data/photos/incoming/ to process.")

    try:
        while not stop_event.is_set():
            time.sleep(0.5)
    finally:
        observer.stop()
        observer.join()
        logger.info("Photo ingestion watcher stopped cleanly.")


if __name__ == "__main__":
    main()
