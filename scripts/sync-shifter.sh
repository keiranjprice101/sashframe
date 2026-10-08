#!/usr/bin/env bash
set -euo pipefail

# Locate environment file
if [ -z "${ENV_FILE:-}" ]; then
  if [ -f "/etc/sashframe/sashframe.env" ]; then
    ENV_FILE="/etc/sashframe/sashframe.env"
  elif [ -f "/etc/home-calendar/home-calendar.env" ]; then
    ENV_FILE="/etc/home-calendar/home-calendar.env"
  elif [ -f "$(dirname "${BASH_SOURCE[0]}")/../.env" ]; then
    ENV_FILE="$(dirname "${BASH_SOURCE[0]}")/../.env"
  else
    ENV_FILE="/etc/sashframe/sashframe.env"
  fi
fi

# 1. Source environment file if present
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  set -a
  source "$ENV_FILE"
  set +a
else
  # In local standalone development without /etc/sashframe, continue with defaults
  echo "[Notice] Configuration file '$ENV_FILE' not found. Using defaults."
fi

# 2. Determine directories and targets
SHIFTER_INPUT_DIR="${SHIFTER_INPUT_DIR:-/var/lib/sashframe/calendar}"
if [ ! -d "$SHIFTER_INPUT_DIR" ] && [ -d "$(dirname "${BASH_SOURCE[0]}")/../data/shifter" ]; then
  SHIFTER_INPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../data/shifter" && pwd)"
fi

STAGING_DIR="${SHIFTER_INPUT_DIR}/incoming"
TARGET_FILE="${SHIFTER_FILE_PATH:-${SHIFTER_INPUT_DIR}/calendar.Shifter}"

RCLONE_REMOTE_NAME="${RCLONE_SHIFTER_REMOTE:-${RCLONE_REMOTE:-gdrive}}"
RCLONE_CONFIG_FILE="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"

# 3. Verify rclone binary
if ! command -v rclone >/dev/null 2>&1; then
  echo "[Error] rclone binary is not installed or not in PATH." >&2
  exit 1
fi

# 4. Prepare rclone arguments
RCLONE_ARGS=()
if [ -n "${RCLONE_CONFIG_FILE}" ] && [ -f "${RCLONE_CONFIG_FILE}" ]; then
  RCLONE_ARGS+=("--config" "$RCLONE_CONFIG_FILE")
fi

# If a specific Google Drive folder ID is set, override root folder to access it directly
if [ -n "${RCLONE_SHIFTER_FOLDER_ID:-}" ]; then
  RCLONE_ARGS+=("--drive-root-folder-id" "$RCLONE_SHIFTER_FOLDER_ID")
fi

# If using service account credentials override, or auto-detect in standard locations
if [ -z "${RCLONE_SHIFTER_SERVICE_ACCOUNT:-}" ]; then
  CANDIDATE_SAS=(
    "/etc/sashframe/service-account.json"
    "${INSTALL_HOME:-$HOME}/.config/rclone/service-account.json"
    "$(dirname "${BASH_SOURCE[0]}")/../service-account.json"
    "${HOME}/Downloads/"sashframe-*.json
  )
  for cand in "${CANDIDATE_SAS[@]}"; do
    if [ -f "$cand" ]; then
      RCLONE_SHIFTER_SERVICE_ACCOUNT="$cand"
      break
    fi
  done
fi

if [ -n "${RCLONE_SHIFTER_SERVICE_ACCOUNT:-}" ] && [ -f "${RCLONE_SHIFTER_SERVICE_ACCOUNT}" ]; then
  RCLONE_ARGS+=("--drive-service-account-file" "$RCLONE_SHIFTER_SERVICE_ACCOUNT")
fi

# Filter only .Shifter files
RCLONE_ARGS+=(
  "--include" "*.Shifter"
  "--include" "*.shifter"
  "--update"
)

# 5. Determine remote target path
if [ -n "${RCLONE_SHIFTER_PATH:-}" ]; then
  REMOTE_TARGET="${RCLONE_REMOTE_NAME}:${RCLONE_SHIFTER_PATH}"
else
  REMOTE_TARGET="${RCLONE_REMOTE_NAME}:"
fi

mkdir -p "$STAGING_DIR"
mkdir -p "$SHIFTER_INPUT_DIR"

echo "[Sync] Checking for Shifter calendar files from '${REMOTE_TARGET}'..."

# 6. Execute rclone copy into staging directory
if ! rclone copy "${RCLONE_ARGS[@]}" "${REMOTE_TARGET}" "${STAGING_DIR}"; then
  echo "[Error] rclone copy failed from '${REMOTE_TARGET}'." >&2
  exit 1
fi

# 7. Atomically publish any discovered Shifter file to active location
FOUND_COUNT=0
NEWEST_FILE=""
NEWEST_TIME=0

for file in "$STAGING_DIR"/*; do
  [ -f "$file" ] || continue
  case "$(echo "$file" | tr '[:upper:]' '[:lower:]')" in
    *.shifter)
      FOUND_COUNT=$((FOUND_COUNT + 1))
      BASENAME="$(basename "$file")"

      # Atomically copy with original filename into calendar directory
      cp -f "$file" "${SHIFTER_INPUT_DIR}/${BASENAME}.tmp"
      mv -f "${SHIFTER_INPUT_DIR}/${BASENAME}.tmp" "${SHIFTER_INPUT_DIR}/${BASENAME}"
      chmod 644 "${SHIFTER_INPUT_DIR}/${BASENAME}" 2>/dev/null || true

      # Track the most recent file
      FILE_TIME="$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0)"
      if [ "$FILE_TIME" -ge "$NEWEST_TIME" ]; then
        NEWEST_TIME="$FILE_TIME"
        NEWEST_FILE="$file"
      fi
      ;;
  esac
done

if [ -n "$NEWEST_FILE" ] && [ -f "$NEWEST_FILE" ]; then
  # Atomically update canonical calendar.Shifter file
  cp -f "$NEWEST_FILE" "${TARGET_FILE}.tmp"
  mv -f "${TARGET_FILE}.tmp" "${TARGET_FILE}"
  chmod 644 "${TARGET_FILE}" 2>/dev/null || true
  chmod 755 "${SHIFTER_INPUT_DIR}" 2>/dev/null || true
  echo "[Sync] Successfully published ${FOUND_COUNT} Shifter file(s). Active target set to '${TARGET_FILE}' (from '$(basename "$NEWEST_FILE")')."
else
  echo "[Sync] No .Shifter files found in remote target '${REMOTE_TARGET}'."
fi

echo "[Sync] Shifter sync completed at $(date -u '+%Y-%m-%d %H:%M:%SZ')."
