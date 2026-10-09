#!/usr/bin/env bash
# ==============================================================================
# Sashframe - Power-On Docker Build & Launch
#
# Executed by systemd (sashframe-boot-build.service) on every system power-on.
# Builds Docker images from local Dockerfiles/code, launches containers,
# and verifies health before kiosk display starts.
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Source environment configuration if present
if [ -f "/etc/sashframe/sashframe.env" ]; then
  # shellcheck source=/dev/null
  source "/etc/sashframe/sashframe.env"
fi

# Determine Compose command
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
elif command -v podman-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(podman-compose)
elif [ -x "$ROOT_DIR/.venv/bin/podman-compose" ]; then
  COMPOSE_CMD=("$ROOT_DIR/.venv/bin/podman-compose")
else
  echo "[Boot-Build] Error: Neither docker compose nor podman-compose found." >&2
  exit 1
fi

log() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%SZ')] [Boot-Build] $*"
}

log "Power-on startup detected. Preparing application containers..."

# 1. Optionally check for remote updates if network is online
if [ "${BOOT_CHECK_GIT:-true}" = "true" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REMOTE="${GIT_REMOTE:-origin}"
  BRANCH="${GIT_BRANCH:-main}"
  log "Checking remote '$REMOTE/$BRANCH' for updates on power-on..."
  if git fetch "$REMOTE" "$BRANCH" --quiet 2>/dev/null; then
    LOCAL_SHA="$(git rev-parse HEAD 2>/dev/null || echo "")"
    REMOTE_SHA="$(git rev-parse "$REMOTE/$BRANCH" 2>/dev/null || echo "")"
    if [ -n "$REMOTE_SHA" ] && [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
      log "Newer commit found on $REMOTE/$BRANCH (${LOCAL_SHA:0:8} -> ${REMOTE_SHA:0:8}). Updating working tree..."
      git checkout -f "$REMOTE_SHA" --quiet || git pull --ff-only 2>/dev/null || true
    fi
  else
    log "Remote check skipped (network not ready yet). Building current local source."
  fi
fi

# Setup Compose environment file argument
COMPOSE_ENV_ARGS=()
if [ -f "/etc/sashframe/sashframe.env" ]; then
  COMPOSE_ENV_ARGS=(--env-file "/etc/sashframe/sashframe.env")
fi

# 2. Build Docker images from current code
GIT_SHA="$(git rev-parse --short=8 HEAD 2>/dev/null || echo "latest")"
log "Building Docker images tagged '${GIT_SHA}'..."
IMAGE_TAG="$GIT_SHA" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" --profile tools build

# 3. Start containers with the freshly built images
log "Starting application containers with freshly built images..."
IMAGE_TAG="$GIT_SHA" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" up -d --remove-orphans

# 4. Record deployed SHA
STATE_DIR="${SASHFRAME_STATE_DIR:-/var/lib/sashframe/state}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
echo "$GIT_SHA" > "$STATE_DIR/deployed-sha" 2>/dev/null || true

# Mark boot build complete in /run (tmpfs, cleared on reboot)
touch /run/sashframe-boot-built 2>/dev/null || true

log "Power-on Docker build completed successfully for tag '${GIT_SHA}'."
