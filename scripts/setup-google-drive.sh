#!/usr/bin/env bash
set -euo pipefail

# 1. Warn if accidentally executed as root
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "============================================================="
  echo "[Warning] You are running setup-google-drive.sh as root (uid 0)."
  echo "Google Drive OAuth credentials should normally be stored in"
  echo "your regular user's home directory (~/.config/rclone/rclone.conf)."
  echo "============================================================="
  read -r -p "Do you wish to proceed as root? [y/N]: " PROCEED_ROOT
  if [[ ! "$PROCEED_ROOT" =~ ^[Yy]$ ]]; then
    echo "Aborted. Please run as your normal user:"
    echo "  ./scripts/setup-google-drive.sh"
    exit 1
  fi
fi

# 2. Check that rclone is installed
if ! command -v rclone >/dev/null 2>&1; then
  echo "[Error] 'rclone' is not installed or not available on PATH." >&2
  echo "Please run: sudo ./scripts/install.sh" >&2
  exit 1
fi

# 3. Source environment configuration if present
if [ -z "${ENV_FILE:-}" ]; then
  if [ -f "/etc/sashframe/sashframe.env" ]; then
    ENV_FILE="/etc/sashframe/sashframe.env"
  elif [ -f "/etc/home-calendar/home-calendar.env" ]; then
    ENV_FILE="/etc/home-calendar/home-calendar.env"
  else
    ENV_FILE="/etc/sashframe/sashframe.env"
  fi
fi

if [ -f "$ENV_FILE" ]; then
  # Source without failing if file has root permissions and user has read access
  if [ -r "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
  else
    echo "[Notice] Cannot read $ENV_FILE directly. Using default configuration."
  fi
fi

RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
RCLONE_PHOTO_PATH="${RCLONE_PHOTO_PATH:-Calendar Photos}"
PHOTO_INPUT_DIR="${PHOTO_INPUT_DIR:-/var/lib/sashframe/photos/incoming}"
RCLONE_CONFIG="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"

echo "============================================================="
echo " Sashframe - Google Drive Photo Sync Setup"
echo "============================================================="
echo "This helper will configure Google Drive access for your calendar photos."
echo ""
echo "Configuration:"
echo "  Remote Name:         ${RCLONE_REMOTE}"
echo "  Target Drive Folder: ${RCLONE_PHOTO_PATH}"
echo "  Local Incoming Dir:  ${PHOTO_INPUT_DIR}"
echo "  Rclone Config File:  ${RCLONE_CONFIG}"
echo ""
echo "Next, we will launch 'rclone config' for you to set up '${RCLONE_REMOTE}'."
echo ""
echo "Key steps in 'rclone config':"
echo "  1. Choose 'n' for 'New remote'"
echo "  2. Name: enter '${RCLONE_REMOTE}'"
echo "  3. Type: enter 'drive' (Google Drive)"
echo "  4. Leave client_id and client_secret blank unless you have custom credentials"
echo "  5. Scope: choose '1' (Full access) or 'read-only'"
echo "  6. Complete the OAuth web login in your browser"
echo "  7. Choose 'y' to keep the remote, then 'q' to quit config"
echo "============================================================="

# Ensure config directory exists
mkdir -p "$(dirname "$RCLONE_CONFIG")"

# 4. Check if remote already exists or launch rclone config
REMOTE_EXISTS=false
if rclone --config "$RCLONE_CONFIG" listremotes 2>/dev/null | grep -q "^${RCLONE_REMOTE}:"; then
  REMOTE_EXISTS=true
  echo "Existing remote '${RCLONE_REMOTE}:' found in ${RCLONE_CONFIG}."
  read -r -p "Do you want to re-run 'rclone config' to reconfigure credentials? [y/N]: " RERUN
  if [[ "$RERUN" =~ ^[Yy]$ ]]; then
    rclone config --config "$RCLONE_CONFIG"
  fi
else
  read -r -p "Press Enter to launch 'rclone config'..."
  rclone config --config "$RCLONE_CONFIG"
fi

# 5. Verify that remote exists in config
echo ""
echo "Verifying '${RCLONE_REMOTE}:' in rclone configuration..."
if ! rclone --config "$RCLONE_CONFIG" listremotes 2>/dev/null | grep -q "^${RCLONE_REMOTE}:"; then
  echo "[Error] Remote '${RCLONE_REMOTE}:' was not found in ${RCLONE_CONFIG}." >&2
  echo "Available remotes:"
  rclone --config "$RCLONE_CONFIG" listremotes 2>/dev/null || echo "  (none)"
  echo ""
  echo "Please run './scripts/setup-google-drive.sh' again and ensure the remote is named '${RCLONE_REMOTE}'." >&2
  exit 1
fi
echo "✓ Remote '${RCLONE_REMOTE}:' is configured."

# 6. Verify Google Drive access
echo "Verifying Google Drive root access..."
if ! rclone --config "$RCLONE_CONFIG" lsd "${RCLONE_REMOTE}:" >/dev/null 2>&1; then
  echo "[Error] Failed to connect to Google Drive using '${RCLONE_REMOTE}:'." >&2
  echo "Please verify your internet connection and authentication tokens in rclone." >&2
  exit 1
fi
echo "✓ Successfully connected to Google Drive."

# 7. Check for configured folder
echo "Checking for folder '${RCLONE_PHOTO_PATH}' on '${RCLONE_REMOTE}:'..."
FOLDER_EXISTS=false
if rclone --config "$RCLONE_CONFIG" lsd "${RCLONE_REMOTE}:${RCLONE_PHOTO_PATH}" >/dev/null 2>&1; then
  FOLDER_EXISTS=true
elif rclone --config "$RCLONE_CONFIG" lsf "${RCLONE_REMOTE}:${RCLONE_PHOTO_PATH}" >/dev/null 2>&1; then
  FOLDER_EXISTS=true
fi

if [ "$FOLDER_EXISTS" = false ]; then
  echo ""
  echo "[Notice] Folder '${RCLONE_PHOTO_PATH}' was not found on Google Drive."
  read -r -p "Would you like to create the folder '${RCLONE_PHOTO_PATH}' now in Google Drive? [Y/n]: " CREATE_DIR
  if [[ "$CREATE_DIR" =~ ^[Nn]$ ]]; then
    echo ""
    echo "Please create or share a folder named '${RCLONE_PHOTO_PATH}' in your Google Drive."
    echo "Once created, re-run this script to complete setup:"
    echo "  ./scripts/setup-google-drive.sh"
    exit 1
  else
    echo "Creating folder '${RCLONE_PHOTO_PATH}' in Google Drive..."
    if ! rclone --config "$RCLONE_CONFIG" mkdir "${RCLONE_REMOTE}:${RCLONE_PHOTO_PATH}"; then
      echo "[Error] Failed to create folder '${RCLONE_PHOTO_PATH}' in Google Drive." >&2
      exit 1
    fi
    echo "✓ Folder created successfully."
  fi
else
  echo "✓ Found folder '${RCLONE_PHOTO_PATH}' in Google Drive."
fi

# 8. Run test sync into local incoming directory
echo ""
echo "Running test photo sync into local incoming directory: ${PHOTO_INPUT_DIR}..."
if [ ! -d "$PHOTO_INPUT_DIR" ]; then
  if [ -w "$(dirname "$PHOTO_INPUT_DIR")" ]; then
    mkdir -p "$PHOTO_INPUT_DIR"
  else
    sudo mkdir -p "$PHOTO_INPUT_DIR"
    sudo chown -R "$(id -un):$(id -gn)" "$PHOTO_INPUT_DIR"
  fi
fi

if ! rclone --config "$RCLONE_CONFIG" sync "${RCLONE_REMOTE}:${RCLONE_PHOTO_PATH}" "${PHOTO_INPUT_DIR}"; then
  echo "[Error] Test photo sync failed." >&2
  echo "Please check directory permissions and rclone access." >&2
  exit 1
fi
echo "✓ Test sync succeeded."

# 9. Enable and start photo sync timer via sudo
echo ""
echo "Activating automated photo sync service and timer via systemctl..."
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl daemon-reload
  if [ -f "/etc/systemd/system/sashframe-photo-sync.timer" ]; then
    sudo systemctl enable --now sashframe-photo-sync.timer
    echo ""
    echo "============================================================="
    echo " Systemd Timer Status:"
    echo "============================================================="
    systemctl status sashframe-photo-sync.timer --no-pager || true
  else
    sudo systemctl enable --now home-calendar-photo-sync.timer
    echo ""
    echo "============================================================="
    echo " Systemd Timer Status:"
    echo "============================================================="
    systemctl status home-calendar-photo-sync.timer --no-pager || true
  fi
else
  echo "[Notice] systemctl not found (non-systemd environment). Skipping timer activation."
fi

echo ""
echo "============================================================="
echo " Google Drive Setup Complete!"
echo "============================================================="
echo " Photos will sync automatically from:"
echo "   Google Drive: '${RCLONE_REMOTE}:${RCLONE_PHOTO_PATH}'"
echo " to local incoming folder:"
echo "   '${PHOTO_INPUT_DIR}'"
echo ""
echo " Timer interval: Every 5 minutes (and 1 minute after system boot)."
echo " Manual sync command: bash scripts/sync-photos.sh"
echo "============================================================="
