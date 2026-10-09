#!/usr/bin/env bash
# ==============================================================================
# Sashframe - Power-On & On-Demand Photo Ingestion
#
# Pipeline:
#   rclone sync (from Google Drive into canonical host incoming/)
#     ↓
#   deterministic batch photo processor (validate, EXIF rotate, resize, WebP, manifest)
#     ↓
#   manifest.json ready for application display
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-/etc/sashframe/sashframe.env}"

# 1. Source canonical environment file if present
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  set -a
  source "$ENV_FILE"
  set +a
elif [ -f "$ROOT_DIR/.env" ]; then
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

# 2. Derive canonical host photo directories
SASHFRAME_PHOTOS_DIR="${SASHFRAME_PHOTOS_DIR:-/var/lib/sashframe/photos}"
if [ ! -d "$SASHFRAME_PHOTOS_DIR" ] && [ -d "$ROOT_DIR/data/photos" ]; then
  SASHFRAME_PHOTOS_DIR="$ROOT_DIR/data/photos"
fi

PHOTO_INCOMING_DIR="${SASHFRAME_PHOTOS_DIR}/incoming"
PHOTO_PROCESSED_DIR="${SASHFRAME_PHOTOS_DIR}/processed"
PHOTO_MANIFEST="${SASHFRAME_PHOTOS_DIR}/manifest.json"

mkdir -p "$PHOTO_INCOMING_DIR" "$PHOTO_PROCESSED_DIR" "$(dirname "$PHOTO_MANIFEST")"

# 3. Step 1: Google Drive sync via rclone (if configured)
RCLONE_CONFIG_FILE="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
RCLONE_REMOTE_NAME="${RCLONE_REMOTE:-gdrive}"

if [ -n "${RCLONE_REMOTE:-}" ] && command -v rclone >/dev/null 2>&1; then
  RCLONE_ARGS=()
  if [ -f "$RCLONE_CONFIG_FILE" ]; then
    RCLONE_ARGS+=("--config" "$RCLONE_CONFIG_FILE")
  fi

  if [ -n "${RCLONE_PHOTO_PATH:-}" ]; then
    REMOTE_TARGET="${RCLONE_REMOTE_NAME}:${RCLONE_PHOTO_PATH}"
  else
    REMOTE_TARGET="${RCLONE_REMOTE_NAME}:"
  fi

  echo "[Sync] Step 1/2: Syncing incoming photos from '${REMOTE_TARGET}'..."
  # Resilient sync: handle network unavailability gracefully so local batch processing continues
  if rclone sync "${RCLONE_ARGS[@]}" "${REMOTE_TARGET}" "${PHOTO_INCOMING_DIR}"; then
    echo "[Sync] Step 1/2: Google Drive download completed successfully."
  else
    echo "[Sync] Warning: rclone sync encountered an error or network was unavailable. Proceeding with existing local photos." >&2
  fi
else
  echo "[Sync] Step 1/2: Remote sync skipped (RCLONE_REMOTE not set or rclone not installed). Using local incoming photos."
fi

# 4. Step 2: Deterministic batch photo processing
echo "[Sync] Step 2/2: Executing batch photo reconciliation..."
if [ -f "$ROOT_DIR/.venv/bin/python3" ]; then
  "$ROOT_DIR/.venv/bin/python3" -m services.photos.process \
    --incoming "$PHOTO_INCOMING_DIR" \
    --processed "$PHOTO_PROCESSED_DIR" \
    --manifest "$PHOTO_MANIFEST"
elif command -v python3 >/dev/null 2>&1; then
  python3 -m services.photos.process \
    --incoming "$PHOTO_INCOMING_DIR" \
    --processed "$PHOTO_PROCESSED_DIR" \
    --manifest "$PHOTO_MANIFEST"
elif command -v docker >/dev/null 2>&1; then
  (cd "$ROOT_DIR" && docker compose --env-file /etc/sashframe/sashframe.env run --rm sashframe-photo-processor)
else
  echo "[Sync] Error: Neither Python 3 nor Docker found to execute photo processing." >&2
  exit 1
fi

# 5. Confirm manifest ready
if [ -f "$PHOTO_MANIFEST" ]; then
  echo "[Sync] ✓ Photo ingestion pipeline complete. Manifest is ready at '${PHOTO_MANIFEST}'."
else
  echo "[Sync] Warning: Manifest file was not created at '${PHOTO_MANIFEST}'." >&2
fi
