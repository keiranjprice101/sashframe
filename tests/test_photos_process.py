"""
Automated test suite for batch photo processing and manifest reconciliation.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

from PIL import Image

from services.photos.manifest import reconcile_manifest, load_manifest
from services.photos.process import run_batch_process


class BatchPhotoProcessorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp(prefix="sashframe_photo_test_")
        self.incoming_dir = Path(self.test_dir) / "incoming"
        self.processed_dir = Path(self.test_dir) / "processed"
        self.manifest_path = Path(self.test_dir) / "manifest.json"

        self.incoming_dir.mkdir(parents=True, exist_ok=True)
        self.processed_dir.mkdir(parents=True, exist_ok=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _create_test_image(self, filename: str, size: tuple[int, int] = (100, 100), color: tuple[int, int, int] = (255, 0, 0)) -> Path:
        filepath = self.incoming_dir / filename
        img = Image.new("RGB", size, color=color)
        img.save(filepath, format="JPEG")
        return filepath

    def test_empty_incoming_directory(self) -> None:
        """Verify empty incoming directory produces empty manifest and no errors."""
        items = run_batch_process(
            incoming_dir=self.incoming_dir,
            processed_dir=self.processed_dir,
            manifest_path=self.manifest_path,
        )
        self.assertEqual(items, [])
        self.assertTrue(self.manifest_path.is_file())
        manifest = load_manifest(self.manifest_path)
        self.assertEqual(manifest, [])

    def test_one_valid_image(self) -> None:
        """Verify a single valid image is processed, converted to WebP, and recorded in manifest."""
        self._create_test_image("sample.jpg", size=(200, 150), color=(10, 20, 30))

        items = run_batch_process(
            incoming_dir=self.incoming_dir,
            processed_dir=self.processed_dir,
            manifest_path=self.manifest_path,
        )

        self.assertEqual(len(items), 1)
        item = items[0]
        self.assertEqual(item["sourceName"], "sample.jpg")
        self.assertEqual(item["width"], 200)
        self.assertEqual(item["height"], 150)
        self.assertTrue(item["src"].endswith(".webp"))

        webp_path = self.processed_dir / f"{item['id']}.webp"
        self.assertTrue(webp_path.is_file())

        # Verify output is valid WebP readable by Pillow
        with Image.open(webp_path) as out_img:
            self.assertEqual(out_img.format, "WEBP")
            self.assertEqual(out_img.size, (200, 150))

    def test_multiple_images(self) -> None:
        """Verify multiple images are all processed and sorted in manifest."""
        self._create_test_image("alpha.jpg", size=(80, 80), color=(255, 0, 0))
        self._create_test_image("beta.png", size=(120, 100), color=(0, 255, 0))
        self._create_test_image("gamma.jpeg", size=(90, 110), color=(0, 0, 255))

        items = run_batch_process(
            incoming_dir=self.incoming_dir,
            processed_dir=self.processed_dir,
            manifest_path=self.manifest_path,
        )

        self.assertEqual(len(items), 3)
        sources = {item["sourceName"] for item in items}
        self.assertEqual(sources, {"alpha.jpg", "beta.png", "gamma.jpeg"})

        manifest = load_manifest(self.manifest_path)
        self.assertEqual(len(manifest), 3)

    def test_corrupt_image_skipped_without_failing_batch(self) -> None:
        """Verify corrupt/invalid file is skipped with a warning while valid images succeed."""
        self._create_test_image("valid.jpg", size=(100, 100), color=(50, 50, 50))

        # Create a corrupt file with invalid image bytes
        corrupt_path = self.incoming_dir / "corrupt.jpg"
        with open(corrupt_path, "wb") as f:
            f.write(b"NOT_A_REAL_JPEG_IMAGE_HEADER_OR_DATA\x00\xff")

        items = run_batch_process(
            incoming_dir=self.incoming_dir,
            processed_dir=self.processed_dir,
            manifest_path=self.manifest_path,
        )

        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["sourceName"], "valid.jpg")

        manifest = load_manifest(self.manifest_path)
        self.assertEqual(len(manifest), 1)
        self.assertEqual(manifest[0]["sourceName"], "valid.jpg")

    def test_deletion_reconciliation(self) -> None:
        """Verify removing a source image cleans up its processed WebP and removes it from manifest."""
        img1 = self._create_test_image("img1.jpg", color=(100, 0, 0))
        self._create_test_image("img2.jpg", color=(0, 100, 0))

        run_batch_process(self.incoming_dir, self.processed_dir, self.manifest_path)
        self.assertEqual(len(load_manifest(self.manifest_path)), 2)

        # Remove img1
        img1.unlink()

        # Re-run batch processing
        items = run_batch_process(self.incoming_dir, self.processed_dir, self.manifest_path)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["sourceName"], "img2.jpg")

        # Processed directory should have only 1 webp file left
        webp_files = list(self.processed_dir.glob("*.webp"))
        self.assertEqual(len(webp_files), 1)

    def test_unchanged_inputs_idempotency(self) -> None:
        """Verify consecutive runs with unchanged inputs preserve updatedAt timestamps and files."""
        self._create_test_image("steady.jpg", color=(40, 80, 120))

        items1 = run_batch_process(self.incoming_dir, self.processed_dir, self.manifest_path)
        updated_at_1 = items1[0]["updatedAt"]

        items2 = run_batch_process(self.incoming_dir, self.processed_dir, self.manifest_path)
        updated_at_2 = items2[0]["updatedAt"]

        self.assertEqual(items1[0]["id"], items2[0]["id"])
        self.assertEqual(updated_at_1, updated_at_2)

    def test_changed_replaced_source_updates_output(self) -> None:
        """Verify modifying the content of a file updates hash and regenerates WebP."""
        path = self._create_test_image("photo.jpg", size=(100, 100), color=(1, 2, 3))
        items1 = run_batch_process(self.incoming_dir, self.processed_dir, self.manifest_path)
        id1 = items1[0]["id"]

        # Overwrite with completely new image
        new_img = Image.new("RGB", (250, 250), color=(200, 210, 220))
        new_img.save(path, format="JPEG")

        items2 = run_batch_process(self.incoming_dir, self.processed_dir, self.manifest_path)
        id2 = items2[0]["id"]

        self.assertNotEqual(id1, id2)
        self.assertEqual(items2[0]["width"], 250)
        self.assertFalse((self.processed_dir / f"{id1}.webp").exists())
        self.assertTrue((self.processed_dir / f"{id2}.webp").exists())

    def test_orphan_output_cleanup(self) -> None:
        """Verify arbitrary leftover/orphan WebP files in processed directory are removed."""
        self._create_test_image("active.jpg", color=(10, 10, 10))

        # Manually inject an orphan webp
        orphan_path = self.processed_dir / "deadbeef1234.webp"
        img = Image.new("RGB", (50, 50), color=(0, 0, 0))
        img.save(orphan_path, format="WEBP")
        self.assertTrue(orphan_path.exists())

        run_batch_process(self.incoming_dir, self.processed_dir, self.manifest_path)
        self.assertFalse(orphan_path.exists())

    def test_downscale_preserves_aspect_ratio_without_upscaling(self) -> None:
        """Verify image larger than max_dimension is downscaled without upscaling small images."""
        self._create_test_image("large.jpg", size=(3000, 1500), color=(50, 50, 50))
        self._create_test_image("small.jpg", size=(400, 300), color=(60, 60, 60))

        items = run_batch_process(
            incoming_dir=self.incoming_dir,
            processed_dir=self.processed_dir,
            manifest_path=self.manifest_path,
            max_dimension=1000,
        )

        by_name = {item["sourceName"]: item for item in items}
        # Large: 3000x1500 scaled down to max 1000 => 1000x500
        self.assertEqual(by_name["large.jpg"]["width"], 1000)
        self.assertEqual(by_name["large.jpg"]["height"], 500)

        # Small: 400x300 NOT upscaled
        self.assertEqual(by_name["small.jpg"]["width"], 400)
        self.assertEqual(by_name["small.jpg"]["height"], 300)


if __name__ == "__main__":
    unittest.main()
