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
if [ -z "$INSTALL_USER" ] || [ "$INSTALL_USER" = "root" ]; then
  REGULAR_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd 2>/dev/null || true)"
  if [ -n "$REGULAR_USER" ]; then
    INSTALL_USER="$REGULAR_USER"
  else
    INSTALL_USER="$(id -un 2>/dev/null || whoami 2>/dev/null || echo "pi")"
  fi
fi

INSTALL_UID="$(id -u "$INSTALL_USER" 2>/dev/null || echo 1000)"
INSTALL_GID="$(id -g "$INSTALL_USER" 2>/dev/null || echo 1000)"

INSTALL_HOME="$(getent passwd "$INSTALL_USER" 2>/dev/null | cut -d: -f6 || true)"
if [ -z "$INSTALL_HOME" ] || [ ! -d "$INSTALL_HOME" ]; then
  INSTALL_HOME="${HOME:-/home/$INSTALL_USER}"
fi

echo "Application user: $INSTALL_USER (UID: $INSTALL_UID, GID: $INSTALL_GID)"
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

# Parse arguments
DEV_MODE=false
for arg in "$@"; do
  case "$arg" in
    --dev)
      DEV_MODE=true
      ;;
  esac
done

# 2. System dependencies
if [ "$DEV_MODE" = true ]; then
  echo "[1/6] Checking developer system packages (rclone, curl, python3, npm)..."
else
  echo "[1/5] Checking production system packages (rclone, curl, docker)..."
fi

if command -v apt-get >/dev/null 2>&1; then
  PACKAGES=()
  if ! command -v rclone >/dev/null 2>&1; then
    PACKAGES+=("rclone")
  fi
  if ! command -v curl >/dev/null 2>&1; then
    PACKAGES+=("curl")
  fi
  if [ "$DEV_MODE" = true ]; then
    if ! command -v python3 >/dev/null 2>&1; then
      PACKAGES+=("python3" "python3-venv" "python3-pip")
    fi
    if ! command -v npm >/dev/null 2>&1; then
      PACKAGES+=("npm")
    fi
  else
    if ! command -v docker >/dev/null 2>&1; then
      PACKAGES+=("docker.io" "docker-compose-plugin")
    fi
    if ! command -v cage >/dev/null 2>&1; then
      PACKAGES+=("cage")
    fi
    if ! command -v chromium-browser >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1; then
      if apt-cache show chromium-browser >/dev/null 2>&1; then
        PACKAGES+=("chromium-browser")
      elif apt-cache show chromium >/dev/null 2>&1; then
        PACKAGES+=("chromium")
      fi
    fi
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

# Ensure user is in required groups (docker, video, render, input) for kiosk display
for grp in docker video render input; do
  if getent group "$grp" >/dev/null 2>&1; then
    if ! id -nG "$INSTALL_USER" 2>/dev/null | grep -qw "$grp"; then
      echo "  Adding user '$INSTALL_USER' to $grp group..."
      run_as_root usermod -aG "$grp" "$INSTALL_USER" 2>/dev/null || true
    fi
  fi
done

# Ensure Docker daemon is enabled and running
if command -v systemctl >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
  run_as_root systemctl enable --now docker 2>/dev/null || true
fi

# If in DEV mode, set up Python venv and Node modules on host
if [ "$DEV_MODE" = true ]; then
  echo "[2/6] Setting up host Python virtual environment (.venv)..."
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

  echo "[3/6] Installing Python dependencies from requirements.txt..."
  if [ -f ".venv/bin/pip" ]; then
    run_as_user .venv/bin/pip install --quiet --upgrade pip 2>/dev/null || true
    run_as_user .venv/bin/pip install -r requirements.txt
  fi

  echo "[4/6] Installing Node dependencies via npm install..."
  if command -v npm >/dev/null 2>&1; then
    run_as_user npm install
  fi

  if [ "${EUID:-$(id -u)}" -eq 0 ] && [ "$INSTALL_USER" != "root" ]; then
    chown -R "$INSTALL_USER:$INSTALL_USER" "$ROOT_DIR/.venv" "$ROOT_DIR/node_modules" 2>/dev/null || true
  fi

  # Ensure repo-local development directories exist
  mkdir -p "$ROOT_DIR/data/photos/incoming" "$ROOT_DIR/data/photos/processed"

  echo ""
  echo "=========================================="
  echo " Developer setup complete!"
  echo " Run 'npm run dev' to start development."
  echo "=========================================="
  exit 0
fi

# 3. Runtime directories
echo "[2/5] Setting up runtime directories (/var/lib/sashframe)..."
RUNTIME_DIRS=(
  "/var/lib/sashframe"
  "/var/lib/sashframe/photos"
  "/var/lib/sashframe/photos/incoming"
  "/var/lib/sashframe/photos/processed"
  "/var/lib/sashframe/calendar"
  "/var/lib/sashframe/state"
  "/var/lib/sashframe/database"
)

for dir in "${RUNTIME_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    echo "  Creating directory: $dir"
    run_as_root mkdir -p "$dir"
  fi
done

# Migration: copy existing photos from legacy path /var/lib/home-calendar if present
if [ -d "/var/lib/home-calendar/photos" ] && [ ! -f "/var/lib/sashframe/photos/manifest.json" ]; then
  if [ -f "/var/lib/home-calendar/photos/manifest.json" ]; then
    echo "  Migrating legacy photos from /var/lib/home-calendar to /var/lib/sashframe..."
    run_as_root cp -rn /var/lib/home-calendar/photos/* /var/lib/sashframe/photos/ 2>/dev/null || true
  fi
fi

run_as_root chown -R "$INSTALL_USER:$INSTALL_USER" "/var/lib/sashframe"
run_as_root chmod 755 "/var/lib/sashframe" "/var/lib/sashframe/photos" "/var/lib/sashframe/photos/incoming" "/var/lib/sashframe/photos/processed" "/var/lib/sashframe/calendar" "/var/lib/sashframe/state" "/var/lib/sashframe/database"

# 4. Central environment file
echo "[3/5] Configuring central environment file (/etc/sashframe/sashframe.env)..."
run_as_root mkdir -p "/etc/sashframe"
run_as_root chmod 755 "/etc/sashframe"

ENV_FILE="/etc/sashframe/sashframe.env"
LEGACY_ENV="/etc/home-calendar/home-calendar.env"

if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$LEGACY_ENV" ]; then
    echo "  Migrating existing configuration from $LEGACY_ENV to $ENV_FILE..."
    run_as_root sed -e 's|/var/lib/home-calendar|/var/lib/sashframe|g' "$LEGACY_ENV" > "/tmp/sashframe.env"
    run_as_root mv "/tmp/sashframe.env" "$ENV_FILE"
  else
    echo "  Creating $ENV_FILE with default production settings..."
    run_as_root bash -c "cat << EOF > '$ENV_FILE'
# Sashframe Environment Configuration
PUID=${INSTALL_UID}
PGID=${INSTALL_GID}

PHOTO_INPUT_DIR=/var/lib/sashframe/photos/incoming
PHOTO_OUTPUT_DIR=/var/lib/sashframe/photos/processed
PHOTO_MANIFEST=/var/lib/sashframe/photos/manifest.json
PHOTO_MAX_SIZE=1920
PHOTO_QUALITY=85

RCLONE_REMOTE=gdrive
RCLONE_PHOTO_PATH=\"Calendar Photos\"

RCLONE_CONFIG=${INSTALL_HOME}/.config/rclone/rclone.conf
EOF"
  fi
  run_as_root chown "$INSTALL_USER:$INSTALL_USER" "$ENV_FILE"
  run_as_root chmod 644 "$ENV_FILE"
else
  echo "  Existing $ENV_FILE found. Preserving user configuration."
fi

# Ensure helper scripts are executable
chmod +x "$ROOT_DIR/scripts/start.sh" 2>/dev/null || true
chmod +x "$ROOT_DIR/scripts/sync-photos.sh" 2>/dev/null || true
chmod +x "$ROOT_DIR/scripts/setup-google-drive.sh" 2>/dev/null || true
chmod +x "$ROOT_DIR/scripts/update.sh" 2>/dev/null || true

# Set up transparent cursor theme on host to suppress cursor in Cage and Chromium
echo "  Configuring transparent cursor theme for kiosk display..."
CURSOR_BASE="/usr/share/icons/sashframe-transparent"
CURSOR_DIR="${CURSOR_BASE}/cursors"
run_as_root mkdir -p "${CURSOR_DIR}"
echo "WGN1chAAAAABAAAAAQAAAAIA/f8gAAAAHAAAACQAAAACAP3/IAAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAA=" | \
  base64 -d | run_as_root tee "${CURSOR_DIR}/default" >/dev/null
for c in left_ptr right_ptr top_left_arrow arrow pointer hand hand1 hand2 \
         grab grabbing wait watch progress xterm text ibeam crosshair cross \
         move size_all help question_arrow dnd-none dnd-move dnd-copy dnd-link \
         0000816000000681000040808001010c 08e631cbe3823404b201215b04232244; do
  run_as_root ln -sf default "${CURSOR_DIR}/${c}" 2>/dev/null || true
done
run_as_root bash -c "cat << 'EOF' > '${CURSOR_BASE}/index.theme'
[Icon Theme]
Name=sashframe-transparent
Comment=Transparent invisible cursor theme for Sashframe kiosk display
EOF"

if [ -n "$INSTALL_HOME" ] && [ -d "$INSTALL_HOME" ]; then
  USER_ICONS="${INSTALL_HOME}/.icons/default"
  run_as_root mkdir -p "${USER_ICONS}"
  run_as_root bash -c "cat << 'EOF' > '${USER_ICONS}/index.theme'
[Icon Theme]
Name=default
Inherits=sashframe-transparent
EOF"
  run_as_root chown -R "$INSTALL_USER:$INSTALL_USER" "${INSTALL_HOME}/.icons" 2>/dev/null || true
fi

# 5. Install systemd units
echo "[4/5] Installing host systemd units..."
SYSTEMD_DIR="/etc/systemd/system"
if [ -d "$SYSTEMD_DIR" ]; then
  install_unit() {
    local src="$1"
    local dest="$2"
    if [ -f "$src" ]; then
      run_as_root sed -e "s|@INSTALL_USER@|$INSTALL_USER|g" -e "s|@REPO_ROOT@|$ROOT_DIR|g" "$src" > "/tmp/$(basename "$dest")"
      run_as_root mv "/tmp/$(basename "$dest")" "$dest"
      run_as_root chmod 644 "$dest"
    fi
  }

  install_unit "$ROOT_DIR/systemd/sashframe-kiosk.service" "$SYSTEMD_DIR/sashframe-kiosk.service"
  install_unit "$ROOT_DIR/systemd/sashframe-photo-sync.service" "$SYSTEMD_DIR/sashframe-photo-sync.service"
  install_unit "$ROOT_DIR/systemd/sashframe-photo-sync.timer" "$SYSTEMD_DIR/sashframe-photo-sync.timer"
  install_unit "$ROOT_DIR/systemd/sashframe-updater.service" "$SYSTEMD_DIR/sashframe-updater.service"
  install_unit "$ROOT_DIR/systemd/sashframe-updater.timer" "$SYSTEMD_DIR/sashframe-updater.timer"

  # Maintain legacy units for compatibility
  install_unit "$ROOT_DIR/systemd/home-calendar-photo-sync.service" "$SYSTEMD_DIR/home-calendar-photo-sync.service"
  install_unit "$ROOT_DIR/systemd/home-calendar-photo-sync.timer" "$SYSTEMD_DIR/home-calendar-photo-sync.timer"

  if command -v systemctl >/dev/null 2>&1; then
    run_as_root systemctl daemon-reload
    # Enable updater timer by default
    run_as_root systemctl enable --now sashframe-updater.timer 2>/dev/null || true
    # Enable kiosk service on boot by default (starts Cage/Chromium on tty1)
    run_as_root systemctl enable sashframe-kiosk.service 2>/dev/null || true
  fi
fi

# 6. Build Docker images & start Compose stack
echo "[5/5] Building and starting Docker Compose services..."
COMPOSE_CMD=()
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
elif command -v podman-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(podman-compose)
elif [ -x "$ROOT_DIR/.venv/bin/podman-compose" ]; then
  COMPOSE_CMD=("$ROOT_DIR/.venv/bin/podman-compose")
fi

if [ ${#COMPOSE_CMD[@]} -gt 0 ]; then
  GIT_SHA="$(git rev-parse --short=8 HEAD 2>/dev/null || echo "latest")"
  echo "  Building Docker images tagged '${GIT_SHA}'..."
  IMAGE_TAG="$GIT_SHA" run_as_user "${COMPOSE_CMD[@]}" build

  echo "  Starting Sashframe production containers..."
  IMAGE_TAG="$GIT_SHA" run_as_user "${COMPOSE_CMD[@]}" up -d

  # Record initially deployed SHA
  run_as_root mkdir -p /var/lib/sashframe/state
  run_as_root chown -R "$INSTALL_USER:$INSTALL_USER" /var/lib/sashframe/state
  echo "$GIT_SHA" | run_as_user tee /var/lib/sashframe/state/deployed-sha >/dev/null || true
  echo "  Docker Compose stack is running."
else
  echo "  [Warning] Docker Compose not found. Skipping initial container launch."
fi

# 10. Check Google Drive rclone configuration
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
    run_as_root systemctl enable --now sashframe-photo-sync.timer 2>/dev/null || true
  fi
  echo ""
  echo "=========================================="
  echo " Setup complete!"
  echo " Docker application services are RUNNING."
  echo " Google Drive photo sync is ACTIVE."
  echo " Auto-updater timer is ACTIVE."
  echo " Kiosk display service is ENABLED on boot."
  echo ""
  echo " To start the kiosk manually or check status:"
  echo "   ./scripts/start.sh"
  echo "   ./scripts/start.sh --status"
  echo "=========================================="
else
  echo "Google Drive remote '${REMOTE_NAME}:' is not configured yet."
  echo ""
  echo "=========================================="
  echo " Setup complete!"
  echo " Docker application services are RUNNING."
  echo " Auto-updater timer is ACTIVE."
  echo " Kiosk display service is ENABLED on boot."
  echo ""
  echo " NEXT STEPS:"
  echo " 1. Configure Google Drive photo sync as '$INSTALL_USER':"
  echo "    ./scripts/setup-google-drive.sh"
  echo " 2. Start the kiosk display or check status:"
  echo "    ./scripts/start.sh"
  echo "=========================================="
fi
