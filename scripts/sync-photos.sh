#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/sashframe/sashframe.env}"

# 1. Source environment file if present, or fail clearly
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "[Error] Configuration file '$ENV_FILE' not found." >&2
  echo "Please run sudo ./scripts/install.sh to create the environment file." >&2
  exit 1
fi

# 2. Derive canonical host photo incoming directory
SASHFRAME_PHOTOS_DIR="${SASHFRAME_PHOTOS_DIR:-/var/lib/sashframe/photos}"
PHOTO_INCOMING_DIR="${SASHFRAME_PHOTOS_DIR}/incoming"

# 3. Validate required variables
MISSING_VARS=()
if [ -z "${RCLONE_REMOTE:-}" ]; then
  MISSING_VARS+=("RCLONE_REMOTE")
fi

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  echo "[Error] Missing required environment variables in $ENV_FILE:" >&2
  for var in "${MISSING_VARS[@]}"; do
    echo "  - $var" >&2
  done
  exit 1
fi

# 4. Verify rclone binary
if ! command -v rclone >/dev/null 2>&1; then
  echo "[Error] rclone binary is not installed or not in PATH." >&2
  exit 1
fi

# 5. Prepare rclone arguments
RCLONE_ARGS=()
if [ -n "${RCLONE_CONFIG:-}" ]; then
  if [ ! -f "$RCLONE_CONFIG" ]; then
    echo "[Error] Configured RCLONE_CONFIG file does not exist: $RCLONE_CONFIG" >&2
    echo "Please run ./scripts/setup-google-drive.sh to configure Google Drive access." >&2
    exit 1
  fi
  RCLONE_ARGS+=("--config" "$RCLONE_CONFIG")
fi

# 6. Ensure local incoming directory exists
mkdir -p "$PHOTO_INCOMING_DIR"

if [ -n "${RCLONE_PHOTO_PATH:-}" ]; then
  REMOTE_TARGET="${RCLONE_REMOTE}:${RCLONE_PHOTO_PATH}"
else
  REMOTE_TARGET="${RCLONE_REMOTE}:"
fi
echo "[Sync] Starting photo sync from '${REMOTE_TARGET}' into '${PHOTO_INCOMING_DIR}'..."

# 7. Execute rclone sync
rclone sync "${RCLONE_ARGS[@]}" "${REMOTE_TARGET}" "${PHOTO_INCOMING_DIR}"

echo "[Sync] Photo sync completed successfully at $(date -u '+%Y-%m-%d %H:%M:%SZ')."
