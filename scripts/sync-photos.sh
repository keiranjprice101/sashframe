#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/home-calendar/home-calendar.env}"

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

# 2. Validate required variables
MISSING_VARS=()
if [ -z "${PHOTO_INPUT_DIR:-}" ]; then
  MISSING_VARS+=("PHOTO_INPUT_DIR")
fi
if [ -z "${RCLONE_REMOTE:-}" ]; then
  MISSING_VARS+=("RCLONE_REMOTE")
fi
if [ -z "${RCLONE_PHOTO_PATH:-}" ]; then
  MISSING_VARS+=("RCLONE_PHOTO_PATH")
fi

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  echo "[Error] Missing required environment variables in $ENV_FILE:" >&2
  for var in "${MISSING_VARS[@]}"; do
    echo "  - $var" >&2
  done
  exit 1
fi

# 3. Verify rclone binary
if ! command -v rclone >/dev/null 2>&1; then
  echo "[Error] rclone binary is not installed or not in PATH." >&2
  exit 1
fi

# 4. Prepare rclone arguments
RCLONE_ARGS=()
if [ -n "${RCLONE_CONFIG:-}" ]; then
  if [ ! -f "$RCLONE_CONFIG" ]; then
    echo "[Error] Configured RCLONE_CONFIG file does not exist: $RCLONE_CONFIG" >&2
    echo "Please run ./scripts/setup-google-drive.sh to configure Google Drive access." >&2
    exit 1
  fi
  RCLONE_ARGS+=("--config" "$RCLONE_CONFIG")
fi

# 5. Ensure local incoming directory exists
mkdir -p "$PHOTO_INPUT_DIR"

REMOTE_TARGET="${RCLONE_REMOTE}:${RCLONE_PHOTO_PATH}"
echo "[Sync] Starting photo sync from '${REMOTE_TARGET}' into '${PHOTO_INPUT_DIR}'..."

# 6. Execute rclone sync
rclone sync "${RCLONE_ARGS[@]}" "${REMOTE_TARGET}" "${PHOTO_INPUT_DIR}"

echo "[Sync] Photo sync completed successfully at $(date -u '+%Y-%m-%d %H:%M:%SZ')."
