#!/usr/bin/env bash
# ==============================================================================
# Sashframe - Production Startup & Kiosk Manager
#
# Starts application containers, ensures systemd sync/update timers are active,
# waits for frontend readiness, and launches Chromium in fullscreen kiosk mode.
#
# Designed specifically for Raspberry Pi OS Lite (via Cage Wayland compositor)
# as well as desktop graphical sessions.
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 1. Load central configuration
if [ -f "/etc/sashframe/sashframe.env" ]; then
  # shellcheck source=/dev/null
  source "/etc/sashframe/sashframe.env"
elif [ -f "/etc/home-calendar/home-calendar.env" ]; then
  # shellcheck source=/dev/null
  source "/etc/home-calendar/home-calendar.env"
fi

PORT="${PORT:-4321}"
HOST="${HOST:-127.0.0.1}"
KIOSK_URL="${KIOSK_URL:-http://127.0.0.1:${PORT}}"
HEALTH_URL="${APP_HEALTH_URL:-http://127.0.0.1:${PORT}/health}"

# Execution helper for root actions if required
run_as_root() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

# Determine Compose command
get_compose_cmd() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  elif command -v podman-compose >/dev/null 2>&1; then
    echo "podman-compose"
  elif [ -x "$ROOT_DIR/.venv/bin/podman-compose" ]; then
    echo "$ROOT_DIR/.venv/bin/podman-compose"
  else
    echo ""
  fi
}

# Ensure user belongs to essential groups on Raspberry Pi
ensure_user_groups() {
  local target_user="${SUDO_USER:-$USER}"
  if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
    target_user="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd 2>/dev/null || echo "pi")"
  fi

  for grp in docker video render input; do
    if getent group "$grp" >/dev/null 2>&1; then
      if ! id -nG "$target_user" 2>/dev/null | grep -qw "$grp"; then
        echo "[Setup] Adding user '$target_user' to group '$grp'..."
        run_as_root usermod -aG "$grp" "$target_user" 2>/dev/null || true
      fi
    fi
  done
}

# Ensure systemd units are installed
ensure_systemd_units_installed() {
  local systemd_dir="/etc/systemd/system"
  if [ ! -d "$systemd_dir" ]; then
    return 0
  fi

  local target_user="${SUDO_USER:-$USER}"
  if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
    target_user="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd 2>/dev/null || echo "pi")"
  fi

  install_unit_if_missing() {
    local unit_name="$1"
    local src="$ROOT_DIR/systemd/$unit_name"
    local dest="$systemd_dir/$unit_name"
    if [ -f "$src" ] && [ ! -f "$dest" ]; then
      echo "[Setup] Installing $unit_name..."
      run_as_root sed -e "s|@INSTALL_USER@|$target_user|g" -e "s|@REPO_ROOT@|$ROOT_DIR|g" "$src" > "/tmp/$unit_name"
      run_as_root mv "/tmp/$unit_name" "$dest"
      run_as_root chmod 644 "$dest"
      run_as_root systemctl daemon-reload 2>/dev/null || true
    fi
  }

  install_unit_if_missing "sashframe-boot-build.service"
  install_unit_if_missing "sashframe-kiosk.service"
  install_unit_if_missing "sashframe-photo-sync.service"
  install_unit_if_missing "sashframe-photo-sync.timer"
  install_unit_if_missing "sashframe-shifter-sync.service"
  install_unit_if_missing "sashframe-shifter-sync.timer"
  install_unit_if_missing "sashframe-updater.service"
  install_unit_if_missing "sashframe-updater.timer"
}

# Setup and enable all boot autostart components
setup_boot_autostart() {
  echo "=========================================="
  echo " Configuring Sashframe Power-On Autostart"
  echo "=========================================="

  ensure_user_groups
  ensure_systemd_units_installed

  if ! command -v systemctl >/dev/null 2>&1; then
    echo "[Warning] systemctl is not available on this system."
    return 1
  fi

  echo "Enabling Docker service..."
  run_as_root systemctl enable docker 2>/dev/null || true
  run_as_root systemctl start docker 2>/dev/null || true

  echo "Enabling power-on Docker build service..."
  run_as_root systemctl enable sashframe-boot-build.service 2>/dev/null || true

  echo "Enabling auto-updater timer..."
  run_as_root systemctl enable --now sashframe-updater.timer 2>/dev/null || true

  echo "Enabling photo sync timer..."
  run_as_root systemctl enable --now sashframe-photo-sync.timer 2>/dev/null || true

  echo "Enabling shifter calendar sync timer..."
  run_as_root systemctl enable --now sashframe-shifter-sync.timer 2>/dev/null || true

  echo "Enabling kiosk display service..."
  run_as_root systemctl enable sashframe-kiosk.service 2>/dev/null || true

  echo ""
  echo "✓ Sashframe is now configured to start automatically on power-on:"
  echo "  - Docker daemon (application containers)"
  echo "  - Power-on Docker build (sashframe-boot-build.service)"
  echo "  - Photo sync timer (sashframe-photo-sync.timer)"
  echo "  - Shifter calendar sync timer (sashframe-shifter-sync.timer)"
  echo "  - Auto-updater timer (sashframe-updater.timer)"
  echo "  - Kiosk display on tty1 (sashframe-kiosk.service)"
  echo "=========================================="
}

# Start Docker containers
start_docker_stack() {
  local compose_str
  compose_str="$(get_compose_cmd)"

  if [ -z "$compose_str" ]; then
    echo "[Error] Neither docker compose nor podman-compose found." >&2
    return 1
  fi

  # Split compose command into array
  read -r -a COMPOSE_CMD <<< "$compose_str"

  # Ensure docker daemon is active if systemctl exists
  if command -v systemctl >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
    if ! systemctl is-active --quiet docker 2>/dev/null; then
      echo "[Docker] Starting Docker daemon..."
      run_as_root systemctl start docker 2>/dev/null || true
    fi
  fi

  GIT_SHA="$(git rev-parse --short=8 HEAD 2>/dev/null || echo "latest")"

  # Build Docker images on startup if not already built during this boot session
  if [ ! -f "/run/sashframe-boot-built" ]; then
    echo "[Docker] Building Sashframe application images for tag '${GIT_SHA}'..."
    IMAGE_TAG="$GIT_SHA" "${COMPOSE_CMD[@]}" build
    touch "/run/sashframe-boot-built" 2>/dev/null || true
  fi

  echo "[Docker] Ensuring Sashframe application containers are running (${GIT_SHA})..."
  IMAGE_TAG="$GIT_SHA" "${COMPOSE_CMD[@]}" up -d --remove-orphans
}

# Ensure background timers are active
start_background_timers() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi

  # 1. Updater timer
  if systemctl list-unit-files sashframe-updater.timer >/dev/null 2>&1; then
    if ! systemctl is-active --quiet sashframe-updater.timer 2>/dev/null; then
      echo "[Systemd] Starting auto-updater timer..."
      run_as_root systemctl start sashframe-updater.timer 2>/dev/null || true
    fi
    if ! systemctl is-enabled --quiet sashframe-updater.timer 2>/dev/null; then
      run_as_root systemctl enable sashframe-updater.timer 2>/dev/null || true
    fi
  fi

  # 2. Photo sync timer
  if systemctl list-unit-files sashframe-photo-sync.timer >/dev/null 2>&1; then
    if ! systemctl is-active --quiet sashframe-photo-sync.timer 2>/dev/null; then
      echo "[Systemd] Starting photo sync timer..."
      run_as_root systemctl start sashframe-photo-sync.timer 2>/dev/null || true
    fi
    if ! systemctl is-enabled --quiet sashframe-photo-sync.timer 2>/dev/null; then
      run_as_root systemctl enable sashframe-photo-sync.timer 2>/dev/null || true
    fi
  fi
}

# Wait for frontend health endpoint
wait_for_health() {
  echo "[Health] Waiting for Sashframe app to become ready (${HEALTH_URL})..."
  local max_wait=45
  local count=0

  until curl -fsS "$HEALTH_URL" >/dev/null 2>&1; do
    sleep 1
    count=$((count + 1))
    if [ "$count" -ge "$max_wait" ]; then
      echo "[Health] Warning: Healthcheck timed out after ${max_wait}s. Launching browser anyway..."
      return 0
    fi
  done

  echo "[Health] Sashframe app is healthy and responding!"
}

# Clean Chromium crash states and locks
clean_browser_state() {
  # Prevent "Restore pages? Chromium didn't shut down correctly" banner
  for pref in \
    "$HOME/.config/chromium/Default/Preferences" \
    "$HOME/.config/chromium-browser/Default/Preferences" \
    "$HOME/.config/google-chrome/Default/Preferences"; do
    if [ -f "$pref" ]; then
      sed -i -E 's/"exited_cleanly"[[:space:]]*:[[:space:]]*false/"exited_cleanly":true/g' "$pref" 2>/dev/null || true
      sed -i -E 's/"exit_type"[[:space:]]*:[[:space:]]*"Crashed"/"exit_type":"Normal"/g' "$pref" 2>/dev/null || true
    fi
  done

  # Remove singleton lock files
  rm -f "$HOME/.config/chromium/SingletonLock" \
        "$HOME/.config/chromium/SingletonCookie" \
        "$HOME/.config/chromium/SingletonSocket" \
        "$HOME/.config/chromium-browser/SingletonLock" \
        "$HOME/.config/chromium-browser/SingletonCookie" \
        "$HOME/.config/chromium-browser/SingletonSocket" 2>/dev/null || true
}

# Setup transparent cursor theme to completely suppress cursor in Cage and Wayland/X11
ensure_transparent_cursor_theme() {
  local target_home="${HOME}"
  local icon_dir="${target_home}/.icons/sashframe-transparent"
  local cursors_dir="${icon_dir}/cursors"
  local default_icon_dir="${target_home}/.icons/default"

  if [ ! -f "${cursors_dir}/default" ]; then
    mkdir -p "${cursors_dir}" "${default_icon_dir}" 2>/dev/null || true

    # Decode 68-byte 1x1 transparent Xcursor binary
    echo "WGN1chAAAAABAAAAAQAAAAIA/f8gAAAAHAAAACQAAAACAP3/IAAAAAEAAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAA=" | \
      base64 -d > "${cursors_dir}/default" 2>/dev/null || true

    if [ -f "${cursors_dir}/default" ]; then
      for c in left_ptr right_ptr top_left_arrow arrow pointer hand hand1 hand2 \
               grab grabbing wait watch progress xterm text ibeam crosshair cross \
               move size_all help question_arrow dnd-none dnd-move dnd-copy dnd-link \
               0000816000000681000040808001010c 08e631cbe3823404b201215b04232244; do
        ln -sf default "${cursors_dir}/${c}" 2>/dev/null || true
      done

      cat << 'EOF' > "${icon_dir}/index.theme"
[Icon Theme]
Name=sashframe-transparent
Comment=Transparent invisible cursor theme for Sashframe kiosk display
EOF

      cat << 'EOF' > "${default_icon_dir}/index.theme"
[Icon Theme]
Name=default
Inherits=sashframe-transparent
EOF
    fi
  fi

  export XCURSOR_THEME="sashframe-transparent"
  export XCURSOR_SIZE=1
}

# Locate browser binary
find_browser_bin() {
  for bin in chromium-browser chromium google-chrome; do
    if command -v "$bin" >/dev/null 2>&1; then
      echo "$bin"
      return 0
    fi
  done
  echo ""
}

# Launch Chromium in kiosk mode
launch_kiosk() {
  local browser_bin
  browser_bin="$(find_browser_bin)"

  if [ -z "$browser_bin" ]; then
    echo "[Error] No supported browser found (chromium-browser / chromium)!" >&2
    echo "Please install it with: sudo apt update && sudo apt install -y chromium-browser" >&2
    exit 1
  fi

  clean_browser_state
  ensure_transparent_cursor_theme

  local chromium_flags=(
    --kiosk
    --noerrdialogs
    --disable-infobars
    --no-first-run
    --fast
    --fast-start
    --disable-pinch
    --overscroll-history-navigation=0
    --disable-session-crashed-bubble
    --check-for-update-interval=31536000
    --password-store=basic
    --touch-events=enabled
    --autoplay-policy=no-user-gesture-required
    --disable-features=Translate,OptimizationHints,MediaRouter
    --simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT'
    --enable-gpu-rasterization
  )

  # Check if running in a remote SSH session without local display
  if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ] && { [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; }; then
    if [ "${KIOSK_ONLY_MODE:-false}" = "true" ]; then
      echo "[Error] --kiosk-only called in SSH without display session." >&2
      exit 1
    fi

    echo "[Kiosk] Remote SSH session detected without an active display."
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files sashframe-kiosk.service >/dev/null 2>&1; then
      echo "[Kiosk] Starting kiosk display on physical screen via sashframe-kiosk.service..."
      run_as_root systemctl restart sashframe-kiosk.service 2>/dev/null || true
      echo ""
      echo "✓ Kiosk display is running on physical screen (tty1)."
      echo "✓ Live logs: journalctl -fu sashframe-kiosk.service"
      return 0
    else
      echo "[Kiosk] Installing and starting sashframe-kiosk.service..."
      ensure_systemd_units_installed
      run_as_root systemctl restart sashframe-kiosk.service 2>/dev/null || true
      return 0
    fi
  fi

  # Case 1: Active Wayland session
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    echo "[Kiosk] Launching Chromium in active Wayland session..."
    exec "$browser_bin" "${chromium_flags[@]}" --ozone-platform=wayland "$KIOSK_URL"
  fi

  # Case 2: Active X11 session
  if [ -n "${DISPLAY:-}" ]; then
    echo "[Kiosk] Launching Chromium in active X11 session..."
    if command -v xset >/dev/null 2>&1; then
      xset s off -dpms s noblank 2>/dev/null || true
    fi
    if command -v unclutter >/dev/null 2>&1; then
      unclutter -idle 0.5 -root & 2>/dev/null || true
    fi
    exec "$browser_bin" "${chromium_flags[@]}" "$KIOSK_URL"
  fi

  # Case 3: Console / TTY (Raspberry Pi OS Lite)
  if command -v cage >/dev/null 2>&1; then
    echo "[Kiosk] Launching Cage Wayland kiosk compositor on console..."

    # Ensure runtime dir exists
    if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "${XDG_RUNTIME_DIR:-}" ]; then
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
      chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
    fi
    export WLR_LIBINPUT_NO_DEVICES=1

    exec cage -s -- "$browser_bin" "${chromium_flags[@]}" --ozone-platform=wayland "$KIOSK_URL"
  elif command -v xinit >/dev/null 2>&1; then
    echo "[Kiosk] Launching Chromium via xinit..."
    exec xinit "$browser_bin" "${chromium_flags[@]}" "$KIOSK_URL" -- -nocursor
  else
    echo "[Error] No display server or Wayland kiosk compositor found!" >&2
    echo "On Raspberry Pi OS Lite, install Cage and Chromium:" >&2
    echo "  sudo apt update && sudo apt install -y cage chromium-browser" >&2
    exit 1
  fi
}

# Print status of all components
print_status() {
  echo "=========================================="
  echo " Sashframe - System Status"
  echo "=========================================="

  # 1. Docker Compose status
  local compose_str
  compose_str="$(get_compose_cmd)"
  if [ -n "$compose_str" ]; then
    read -r -a COMPOSE_CMD <<< "$compose_str"
    echo "--- Docker Containers ---"
    "${COMPOSE_CMD[@]}" ps || true
  else
    echo "--- Docker Containers ---"
    echo "Docker Compose not available."
  fi
  echo ""

  # 2. Health check status
  echo "--- HTTP Health ---"
  if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    echo "App Health ($HEALTH_URL): UP ●"
  else
    echo "App Health ($HEALTH_URL): DOWN ○"
  fi
  echo ""

  # 3. Systemd units status
  if command -v systemctl >/dev/null 2>&1; then
    echo "--- Systemd Services & Timers ---"
    for unit in sashframe-kiosk.service sashframe-photo-sync.timer sashframe-updater.timer docker.service; do
      if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        local active_status enabled_status
        active_status="$(systemctl is-active "$unit" 2>/dev/null || echo "inactive")"
        enabled_status="$(systemctl is-enabled "$unit" 2>/dev/null || echo "disabled")"
        printf " %-28s active: %-10s enabled: %s\n" "$unit" "$active_status" "$enabled_status"
      else
        printf " %-28s [not installed]\n" "$unit"
      fi
    done
  fi
  echo "=========================================="
}

# Stop stack and kiosk
stop_all() {
  echo "[Shutdown] Stopping Sashframe..."
  if command -v systemctl >/dev/null 2>&1; then
    run_as_root systemctl stop sashframe-kiosk.service 2>/dev/null || true
  fi

  local compose_str
  compose_str="$(get_compose_cmd)"
  if [ -n "$compose_str" ]; then
    read -r -a COMPOSE_CMD <<< "$compose_str"
    "${COMPOSE_CMD[@]}" down
  fi
  echo "[Shutdown] Sashframe stopped."
}

# ----------------------------------------------------------------------
# CLI Arguments
# ----------------------------------------------------------------------
MODE="full"
KIOSK_ONLY_MODE="false"

for arg in "$@"; do
  case "$arg" in
    --setup-boot|--enable-boot|--install-boot)
      setup_boot_autostart
      exit 0
      ;;
    --stack-only|--no-kiosk)
      MODE="stack_only"
      ;;
    --kiosk-only)
      MODE="kiosk_only"
      KIOSK_ONLY_MODE="true"
      ;;
    --status)
      print_status
      exit 0
      ;;
    --stop|stop)
      stop_all
      exit 0
      ;;
    --help|-h)
      echo "Usage: ./scripts/start.sh [options]"
      echo ""
      echo "Options:"
      echo "  (no args)           Start containers, activate timers, wait for health, and launch kiosk"
      echo "  --setup-boot        Enable automatic startup on Pi power-on (containers, timers, kiosk)"
      echo "  --stack-only        Start Docker containers and background timers without launching browser"
      echo "  --kiosk-only        Launch kiosk mode directly (used by systemd sashframe-kiosk.service)"
      echo "  --status            Display status of Docker containers, healthcheck, timers, and kiosk"
      echo "  --stop              Stop Docker containers and kiosk service"
      echo "  --help, -h          Show this help message"
      exit 0
      ;;
  esac
done

# Main Execution Flow
case "$MODE" in
  kiosk_only)
    start_docker_stack
    start_background_timers
    wait_for_health
    launch_kiosk
    ;;
  stack_only)
    start_docker_stack
    start_background_timers
    wait_for_health
    echo "✓ Sashframe application stack is running."
    ;;
  full)
    # Ensure boot units are installed and user has groups
    ensure_user_groups
    ensure_systemd_units_installed

    start_docker_stack
    start_background_timers
    wait_for_health
    launch_kiosk
    ;;
esac
