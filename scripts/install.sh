#!/usr/bin/env bash
set -e

# Change to repository root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=========================================="
echo " Setting up Sashframe Environment"
echo "=========================================="

# 1. Detect application user and home directory
INSTALL_USER="${SUDO_USER:-$USER}"
if [ -z "$INSTALL_USER" ]; then
  INSTALL_USER="$(id -un 2>/dev/null || whoami 2>/dev/null || echo "pi")"
fi

INSTALL_HOME="$(getent passwd "$INSTALL_USER" 2>/dev/null | cut -d: -f6 || true)"
if [ -z "$INSTALL_HOME" ] || [ ! -d "$INSTALL_HOME" ]; then
  INSTALL_HOME="${HOME:-/home/$INSTALL_USER}"
fi

echo "Application user: $INSTALL_USER"
echo "User home:        $INSTALL_HOME"

# Execution helpers for root vs non-root context
run_as_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "[Error] Root privileges required for: $*" >&2
    exit 1
  fi
}

run_as_user() {
  if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    sudo -u "$INSTALL_USER" "$@"
  else
    "$@"
  fi
}

# 2. System dependencies (rclone, python3, npm)
echo "[1/6] Checking system packages..."
if command -v apt-get >/dev/null 2>&1; then
  PACKAGES=()
  if ! command -v rclone >/dev/null 2>&1; then
    PACKAGES+=("rclone")
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    PACKAGES+=("python3" "python3-venv" "python3-pip")
  fi
  if ! command -v npm >/dev/null 2>&1; then
    PACKAGES+=("npm")
  fi

  if [ ${#PACKAGES[@]} -gt 0 ]; then
    echo "  Installing system packages: ${PACKAGES[*]}..."
    run_as_root apt-get update -qq
    run_as_root apt-get install -y --no-install-recommends "${PACKAGES[@]}"
  else
    echo "  Required system packages already installed."
  fi
elif ! command -v rclone >/dev/null 2>&1; then
  echo "  [Warning] rclone is not installed. Please install rclone manually." >&2
fi

# Verify Python 3
if ! command -v python3 >/dev/null 2>&1; then
  echo "[Error] python3 is required but was not found on PATH." >&2
  exit 1
fi

# 3. Set up Python virtual environment
echo "[2/6] Setting up Python virtual environment (.venv)..."
if [ ! -d ".venv" ] || [ ! -f ".venv/bin/activate" ]; then
  if run_as_user python3 -m venv .venv 2>/dev/null; then
    echo "  Created virtual environment using python3 -m venv."
  else
    VENV_CMD=""
    if command -v virtualenv >/dev/null 2>&1; then
      VENV_CMD="virtualenv"
    elif [ -x "$INSTALL_HOME/.local/bin/virtualenv" ]; then
      VENV_CMD="$INSTALL_HOME/.local/bin/virtualenv"
    fi

    if [ -n "$VENV_CMD" ]; then
      echo "  Falling back to $VENV_CMD..."
      run_as_user "$VENV_CMD" .venv
    else
      echo "  Attempting to install virtualenv in user space..."
      run_as_user python3 -m pip install --user --break-system-packages virtualenv 2>/dev/null || true
      if [ -x "$INSTALL_HOME/.local/bin/virtualenv" ]; then
        run_as_user "$INSTALL_HOME/.local/bin/virtualenv" .venv
      else
        echo "[Error] Failed to create .venv. Please install python3-venv or virtualenv." >&2
        exit 1
      fi
    fi
  fi
else
  echo "  Existing .venv found."
fi

# 4. Install Python dependencies
echo "[3/6] Installing Python dependencies from requirements.txt..."
if [ -f ".venv/bin/pip" ]; then
  run_as_user .venv/bin/pip install --quiet --upgrade pip 2>/dev/null || true
  run_as_user .venv/bin/pip install -r requirements.txt
else
  echo "[Error] .venv/bin/pip not found." >&2
  exit 1
fi

# 5. Install Node dependencies
echo "[4/6] Installing Node dependencies via npm install..."
if ! command -v npm >/dev/null 2>&1; then
  echo "[Error] npm is required but was not found on PATH." >&2
  exit 1
fi
run_as_user npm install

# Fix repo ownership if run as root
if [ "${EUID:-$(id -u)}" -eq 0 ] && [ "$INSTALL_USER" != "root" ]; then
  chown -R "$INSTALL_USER:$INSTALL_USER" "$ROOT_DIR/.venv" "$ROOT_DIR/node_modules" 2>/dev/null || true
fi

# 6. Runtime directories
echo "[5/6] Setting up runtime directories..."
RUNTIME_DIRS=(
  "/var/lib/home-calendar"
  "/var/lib/home-calendar/photos"
  "/var/lib/home-calendar/photos/incoming"
  "/var/lib/home-calendar/photos/processed"
)

for dir in "${RUNTIME_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    echo "  Creating directory: $dir"
    run_as_root mkdir -p "$dir"
  fi
done

run_as_root chown -R "$INSTALL_USER:$INSTALL_USER" "/var/lib/home-calendar"
run_as_root chmod 750 "/var/lib/home-calendar" "/var/lib/home-calendar/photos" "/var/lib/home-calendar/photos/incoming" "/var/lib/home-calendar/photos/processed"

# 7. Central environment file
echo "[6/6] Configuring central environment file..."
run_as_root mkdir -p "/etc/home-calendar"
run_as_root chmod 755 "/etc/home-calendar"

ENV_FILE="/etc/home-calendar/home-calendar.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "  Creating $ENV_FILE with default settings..."
  run_as_root bash -c "cat << EOF > '$ENV_FILE'
# Sashframe Environment Configuration
PHOTO_INPUT_DIR=/var/lib/home-calendar/photos/incoming
PHOTO_OUTPUT_DIR=/var/lib/home-calendar/photos/processed
PHOTO_MANIFEST=/var/lib/home-calendar/photos/manifest.json
PHOTO_MAX_SIZE=1920
PHOTO_QUALITY=85

RCLONE_REMOTE=gdrive
RCLONE_PHOTO_PATH=\"Calendar Photos\"

RCLONE_CONFIG=${INSTALL_HOME}/.config/rclone/rclone.conf
EOF"
  run_as_root chown "$INSTALL_USER:$INSTALL_USER" "$ENV_FILE"
  run_as_root chmod 640 "$ENV_FILE"
else
  echo "  Existing $ENV_FILE found. Preserving user configuration."
fi

# 8. Install systemd units
SYSTEMD_DIR="/etc/systemd/system"
if [ -d "$SYSTEMD_DIR" ]; then
  echo "  Registering systemd units..."
  SERVICE_SRC="$ROOT_DIR/systemd/home-calendar-photo-sync.service"
  SERVICE_DEST="$SYSTEMD_DIR/home-calendar-photo-sync.service"
  if [ -f "$SERVICE_SRC" ]; then
    run_as_root sed -e "s|@INSTALL_USER@|$INSTALL_USER|g" -e "s|@REPO_ROOT@|$ROOT_DIR|g" "$SERVICE_SRC" > "/tmp/home-calendar-photo-sync.service"
    run_as_root mv "/tmp/home-calendar-photo-sync.service" "$SERVICE_DEST"
    run_as_root chmod 644 "$SERVICE_DEST"
  fi

  TIMER_SRC="$ROOT_DIR/systemd/home-calendar-photo-sync.timer"
  TIMER_DEST="$SYSTEMD_DIR/home-calendar-photo-sync.timer"
  if [ -f "$TIMER_SRC" ]; then
    run_as_root cp "$TIMER_SRC" "$TIMER_DEST"
    run_as_root chmod 644 "$TIMER_DEST"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    run_as_root systemctl daemon-reload
  fi
fi

# Ensure helper scripts are executable
chmod +x "$ROOT_DIR/scripts/sync-photos.sh" 2>/dev/null || true
chmod +x "$ROOT_DIR/scripts/setup-google-drive.sh" 2>/dev/null || true

# 9. Check Google Drive rclone configuration
echo ""
echo "=========================================="
echo " Checking Google Drive Photo Sync Status"
echo "=========================================="

RCLONE_CONF_FILE="$INSTALL_HOME/.config/rclone/rclone.conf"
REMOTE_NAME="gdrive"
if [ -f "$ENV_FILE" ]; then
  CONF_REMOTE="$(grep -E '^RCLONE_REMOTE=' "$ENV_FILE" | cut -d= -f2 | tr -d '\"'\'' ' || true)"
  if [ -n "$CONF_REMOTE" ]; then
    REMOTE_NAME="$CONF_REMOTE"
  fi
fi

GDRIVE_READY=false
if command -v rclone >/dev/null 2>&1; then
  REMOTES_OUTPUT="$(run_as_user rclone --config "$RCLONE_CONF_FILE" listremotes 2>/dev/null || true)"
  if echo "$REMOTES_OUTPUT" | grep -q "^${REMOTE_NAME}:"; then
    echo "Remote '${REMOTE_NAME}:' found in $RCLONE_CONF_FILE."
    echo "Testing connection to Google Drive..."
    if run_as_user rclone --config "$RCLONE_CONF_FILE" lsd "${REMOTE_NAME}:" >/dev/null 2>&1; then
      GDRIVE_READY=true
      echo "Google Drive connection verified successfully."
    else
      echo "[Warning] Connection check failed for '${REMOTE_NAME}:'."
    fi
  fi
fi

if [ "$GDRIVE_READY" = true ]; then
  if command -v systemctl >/dev/null 2>&1; then
    echo "Enabling and starting Google Drive photo sync timer..."
    run_as_root systemctl enable --now home-calendar-photo-sync.timer 2>/dev/null || true
  fi
  echo ""
  echo "=========================================="
  echo " Setup complete!"
  echo " Google Drive photo sync is ACTIVE."
  echo "=========================================="
else
  echo "Google Drive remote '${REMOTE_NAME}:' is not configured yet."
  echo ""
  echo "=========================================="
  echo " Setup complete!"
  echo ""
  echo " NEXT STEP: Configure Google Drive photo sync"
  echo " Run the setup helper script as '$INSTALL_USER':"
  echo "   ./scripts/setup-google-drive.sh"
  echo "=========================================="
fi
