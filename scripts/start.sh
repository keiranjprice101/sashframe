#!/usr/bin/env bash
# ==============================================================================
# Sashframe - Kiosk Display & Application Runtime Manager
#
# Launches Chromium in fullscreen kiosk mode under Cage Wayland compositor
# (Raspberry Pi OS Lite) or active graphical session.
# Provides status reporting and graceful shutdown controls.
#
# Note: Host system packages, user groups, credentials, and systemd units
# are provisioned declaratively via Ansible.
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 1. Load central environment configuration
if [ -f "/etc/sashframe/sashframe.env" ]; then
  # shellcheck source=/dev/null
  source "/etc/sashframe/sashframe.env"
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
  else
    echo ""
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
    echo "[Error] No supported browser found (chromium / chromium-browser)!" >&2
    exit 1
  fi

  clean_browser_state

  export XCURSOR_THEME="${XCURSOR_THEME:-sashframe-transparent}"
  export XCURSOR_SIZE="${XCURSOR_SIZE:-1}"

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

    echo "[Kiosk] Remote SSH session detected. Managing physical screen on tty1 via systemd..."
    run_as_root systemctl restart sashframe-kiosk.service 2>/dev/null || true
    echo "✓ Kiosk display is running on physical screen (tty1)."
    echo "✓ Live logs: journalctl -fu sashframe-kiosk.service"
    return 0
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
    exec "$browser_bin" "${chromium_flags[@]}" "$KIOSK_URL"
  fi

  # Case 3: Console / TTY (Raspberry Pi OS Lite under Cage)
  if command -v cage >/dev/null 2>&1; then
    echo "[Kiosk] Launching Cage Wayland kiosk compositor on console..."

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
    read -r -a compose_cmd <<< "$compose_str"
    local compose_env_args=()
    if [ -f "/etc/sashframe/sashframe.env" ]; then
      compose_env_args=(--env-file "/etc/sashframe/sashframe.env")
    fi
    echo "--- Docker Containers ---"
    "${compose_cmd[@]}" "${compose_env_args[@]}" ps || true
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
    for unit in sashframe-app.service sashframe-kiosk.service sashframe-photo-sync.service sashframe-updater.service sashframe-shifter-sync.timer docker.service; do
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
    read -r -a compose_cmd <<< "$compose_str"
    local compose_env_args=()
    if [ -f "/etc/sashframe/sashframe.env" ]; then
      compose_env_args=(--env-file "/etc/sashframe/sashframe.env")
    fi
    "${compose_cmd[@]}" "${compose_env_args[@]}" down
  fi
  echo "[Shutdown] Sashframe stopped."
}

MODE="full"
KIOSK_ONLY_MODE="false"

for arg in "$@"; do
  case "$arg" in
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
      echo "  (no args)           Start containers, wait for health, and launch kiosk"
      echo "  --kiosk-only        Launch kiosk mode directly (used by systemd sashframe-kiosk.service)"
      echo "  --stack-only        Start Docker containers without launching browser"
      echo "  --status            Display status of Docker containers, healthcheck, timers, and kiosk"
      echo "  --stop              Stop Docker containers and kiosk service"
      echo "  --help, -h          Show this help message"
      exit 0
      ;;
  esac
done

case "$MODE" in
  kiosk_only)
    launch_kiosk
    ;;
  stack_only)
    "$ROOT_DIR/scripts/start-app.sh"
    wait_for_health
    echo "✓ Sashframe application stack is running."
    ;;
  full)
    "$ROOT_DIR/scripts/start-app.sh"
    wait_for_health
    launch_kiosk
    ;;
esac
