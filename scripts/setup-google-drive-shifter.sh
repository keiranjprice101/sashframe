#!/usr/bin/env bash
set -euo pipefail

# 1. Warn if accidentally executed as root
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "============================================================="
  echo "[Warning] You are running setup-google-drive-shifter.sh as root."
  echo "Google Drive rclone credentials should normally reside in"
  echo "your user home directory (~/.config/rclone/rclone.conf)."
  echo "============================================================="
  read -r -p "Do you wish to proceed as root? [y/N]: " PROCEED_ROOT
  if [[ ! "$PROCEED_ROOT" =~ ^[Yy]$ ]]; then
    echo "Aborted. Please run as your normal user:"
    echo "  ./scripts/setup-google-drive-shifter.sh"
    exit 1
  fi
fi

# 2. Check that rclone is installed
if ! command -v rclone >/dev/null 2>&1; then
  echo "[Error] 'rclone' is not installed or not available on PATH." >&2
  echo "Please install rclone or run: sudo ./scripts/install.sh" >&2
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
  if [ -r "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
  fi
fi

RCLONE_CONFIG="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
RCLONE_SHIFTER_REMOTE="${RCLONE_SHIFTER_REMOTE:-$RCLONE_REMOTE}"
RCLONE_SHIFTER_FOLDER_ID="${RCLONE_SHIFTER_FOLDER_ID:-}"
SHIFTER_INPUT_DIR="${SHIFTER_INPUT_DIR:-/var/lib/sashframe/calendar}"
SHIFTER_FILE_PATH="${SHIFTER_FILE_PATH:-$SHIFTER_INPUT_DIR/calendar.Shifter}"

echo "============================================================="
echo " Sashframe - Google Drive Shifter Calendar Sync Setup"
echo "============================================================="
echo "This helper configures automated Google Drive synchronization for"
echo "your .Shifter calendar file using existing service account credentials."
echo ""
echo "Current Settings:"
echo "  Rclone Config File:  ${RCLONE_CONFIG}"
echo "  Base Remote Name:    ${RCLONE_REMOTE}"
echo "  Shifter Remote Name: ${RCLONE_SHIFTER_REMOTE}"
echo "  Shifter Folder ID:   ${RCLONE_SHIFTER_FOLDER_ID:-<not set>}"
echo "  Local Calendar Dir:  ${SHIFTER_INPUT_DIR}"
echo "  Active Shifter File: ${SHIFTER_FILE_PATH}"
echo "============================================================="
echo ""

# 4. Check for existing service account file in common locations
DETECTED_SA=""
CANDIDATE_SAS=(
  "$HOME/.config/rclone/service-account.json"
  "$HOME/Downloads/"*.json
  "/etc/sashframe/service-account.json"
)
for cand in "${CANDIDATE_SAS[@]}"; do
  if [ -f "$cand" ]; then
    if grep -q '"type": *"service_account"' "$cand" 2>/dev/null; then
      DETECTED_SA="$cand"
      break
    fi
  fi
done

# Check if existing rclone.conf already has a service_account_file configured
if [ -f "$RCLONE_CONFIG" ] && [ -z "$DETECTED_SA" ]; then
  CONF_SA="$(grep -E '^\s*service_account_file\s*=' "$RCLONE_CONFIG" | head -n 1 | cut -d= -f2- | tr -d ' ' || true)"
  if [ -n "$CONF_SA" ] && [ -f "$CONF_SA" ]; then
    DETECTED_SA="$CONF_SA"
  fi
fi

# 5. Prompt for Google Drive folder ID
echo "Google Drive Folder ID:"
echo "Open the Google Drive folder containing your .Shifter file in a browser."
echo "The Folder ID is the last segment of the URL (e.g. drive.google.com/drive/folders/<FOLDER_ID>)."
echo ""
read -r -p "Enter Google Drive Shifter Folder ID [${RCLONE_SHIFTER_FOLDER_ID}]: " INPUT_FOLDER_ID
FOLDER_ID="${INPUT_FOLDER_ID:-$RCLONE_SHIFTER_FOLDER_ID}"

while [ -z "$FOLDER_ID" ]; do
  echo "[Error] Folder ID is required." >&2
  read -r -p "Enter Google Drive Shifter Folder ID: " FOLDER_ID
done

# 6. Configure remote to use
AVAILABLE_REMOTES="$(rclone --config "$RCLONE_CONFIG" listremotes 2>/dev/null || true)"
REMOTE_TO_USE="$RCLONE_SHIFTER_REMOTE"

if [ -n "$DETECTED_SA" ]; then
  echo "Found Google Service Account file: $DETECTED_SA"
  read -r -p "Use this service account for Shifter calendar sync? [Y/n]: " USE_SA
  if [[ ! "$USE_SA" =~ ^[Nn]$ ]]; then
    REMOTE_TO_USE="gdrive-shifter"
    mkdir -p "$(dirname "$RCLONE_CONFIG")"
    
    # Copy SA key to standard location if not already there
    TARGET_SA="$HOME/.config/rclone/service-account.json"
    if [ "$DETECTED_SA" != "$TARGET_SA" ] && [ ! -f "$TARGET_SA" ]; then
      cp -f "$DETECTED_SA" "$TARGET_SA"
      chmod 600 "$TARGET_SA"
      DETECTED_SA="$TARGET_SA"
    fi

    # Update or append gdrive-shifter section in rclone.conf
    if grep -q '^\[gdrive-shifter\]' "$RCLONE_CONFIG" 2>/dev/null; then
      echo "Updating existing '[gdrive-shifter]' remote in $RCLONE_CONFIG..."
      sed -i "/^\[gdrive-shifter\]/,/^\[/ s|^root_folder_id = .*|root_folder_id = ${FOLDER_ID}|" "$RCLONE_CONFIG" 2>/dev/null || true
      sed -i "/^\[gdrive-shifter\]/,/^\[/ s|^service_account_file = .*|service_account_file = ${DETECTED_SA}|" "$RCLONE_CONFIG" 2>/dev/null || true
    else
      cat << EOF >> "$RCLONE_CONFIG"

[gdrive-shifter]
type = drive
scope = drive.readonly
service_account_file = ${DETECTED_SA}
root_folder_id = ${FOLDER_ID}
EOF
      echo "Created '[gdrive-shifter]' remote in $RCLONE_CONFIG."
    fi
  elif echo "$AVAILABLE_REMOTES" | grep -q "^${RCLONE_REMOTE}:"; then
    echo "Reusing existing remote '${RCLONE_REMOTE}:'."
    REMOTE_TO_USE="$RCLONE_REMOTE"
  fi
elif echo "$AVAILABLE_REMOTES" | grep -q "^${RCLONE_REMOTE}:"; then
  echo "Reusing credentials from existing remote '${RCLONE_REMOTE}:'."
  REMOTE_TO_USE="$RCLONE_REMOTE"
else
  echo "Available rclone remotes:"
  echo "$AVAILABLE_REMOTES"
  read -r -p "Enter remote name to use [${RCLONE_REMOTE}]: " INPUT_REMOTE
  REMOTE_TO_USE="${INPUT_REMOTE:-$RCLONE_REMOTE}"
fi

# 7. Test connection to the folder
echo ""
echo "Testing connection to folder ID '${FOLDER_ID}' via '${REMOTE_TO_USE}:'..."
TEST_ARGS=(
  "--config" "$RCLONE_CONFIG"
  "--drive-root-folder-id" "$FOLDER_ID"
)

if rclone lsf "${TEST_ARGS[@]}" "${REMOTE_TO_USE}:" >/dev/null 2>&1; then
  echo "Connection successful! Files in remote folder:"
  rclone lsf "${TEST_ARGS[@]}" "${REMOTE_TO_USE}:" || true
else
  echo "[Warning] Could not list folder contents. Please verify:" >&2
  echo "  1. The Google Drive folder is shared with your Service Account email." >&2
  echo "  2. The Folder ID is correct." >&2
  read -r -p "Do you still wish to save this configuration? [y/N]: " SAVE_ANYWAY
  if [[ ! "$SAVE_ANYWAY" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# 8. Update /etc/sashframe/sashframe.env if accessible
if [ -f "$ENV_FILE" ]; then
  echo ""
  echo "Updating environment file $ENV_FILE..."
  
  update_or_add_var() {
    local key="$1"
    local val="$2"
    local file="$3"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
      sed -i "s|^${key}=.*|${key}=${val}|" "$file" 2>/dev/null || \
        sudo sed -i "s|^${key}=.*|${key}=${val}|" "$file" 2>/dev/null || true
    else
      echo "${key}=${val}" | sudo tee -a "$file" >/dev/null || true
    fi
  }

  update_or_add_var "RCLONE_SHIFTER_REMOTE" "$REMOTE_TO_USE" "$ENV_FILE"
  update_or_add_var "RCLONE_SHIFTER_FOLDER_ID" "$FOLDER_ID" "$ENV_FILE"
  update_or_add_var "SHIFTER_INPUT_DIR" "$SHIFTER_INPUT_DIR" "$ENV_FILE"
  update_or_add_var "SHIFTER_FILE_PATH" "$SHIFTER_FILE_PATH" "$ENV_FILE"
  echo "Configuration saved to $ENV_FILE."
fi

# 9. Test run sync-shifter.sh
echo ""
read -r -p "Run sync test now? [Y/n]: " RUN_TEST
if [[ ! "$RUN_TEST" =~ ^[Nn]$ ]]; then
  RCLONE_SHIFTER_REMOTE="$REMOTE_TO_USE" \
  RCLONE_SHIFTER_FOLDER_ID="$FOLDER_ID" \
  SHIFTER_INPUT_DIR="$SHIFTER_INPUT_DIR" \
  RCLONE_CONFIG="$RCLONE_CONFIG" \
  "$(dirname "${BASH_SOURCE[0]}")/sync-shifter.sh" || true
fi

# 10. Enable systemd timer if on host
if command -v systemctl >/dev/null 2>&1 && [ -f "/etc/systemd/system/sashframe-shifter-sync.timer" ]; then
  echo ""
  echo "Enabling 5-minute systemd timer (sashframe-shifter-sync.timer)..."
  sudo systemctl daemon-reload 2>/dev/null || true
  sudo systemctl enable --now sashframe-shifter-sync.timer 2>/dev/null || true
  echo "Timer active: runs every 5 minutes."
fi

echo ""
echo "============================================================="
echo " Shifter Google Drive sync setup completed successfully!"
echo "============================================================="
