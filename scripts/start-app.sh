#!/usr/bin/env bash
# ==============================================================================
# Sashframe - Power-On Application Startup (Known-Good Image Launch)
#
# Executed by systemd (sashframe-app.service) on system power-on.
# Responsibilities:
# 1. Read last-known-good deployed SHA from /var/lib/sashframe/state/deployed-sha.
# 2. Verify corresponding Docker image exists locally (fallback safely if missing).
# 3. Start container with explicit IMAGE_TAG (if not already running and healthy).
# 4. Verify HTTP /health endpoint is 200 OK.
# 5. Exit 0 so downstream services (sashframe-kiosk.service) can start immediately.
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Source environment configuration if present
if [ -f "/etc/sashframe/sashframe.env" ]; then
  # shellcheck source=/dev/null
  source "/etc/sashframe/sashframe.env"
fi

STATE_DIR="${SASHFRAME_STATE_DIR:-/var/lib/sashframe/state}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
DEPLOYED_SHA_FILE="$STATE_DIR/deployed-sha"

PORT="${PORT:-4321}"
APP_HEALTH_URL="${APP_HEALTH_URL:-http://127.0.0.1:${PORT}/health}"
HEALTH_TIMEOUT_SECS=45
HEALTH_INTERVAL_SECS=1

log() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%SZ')] [App-Start] $*"
}

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
  log "Error: Neither docker compose nor podman-compose found." >&2
  exit 1
fi

COMPOSE_ENV_ARGS=()
if [ -f "/etc/sashframe/sashframe.env" ]; then
  COMPOSE_ENV_ARGS=(--env-file "/etc/sashframe/sashframe.env")
fi

# 1. Read deployed SHA from state file
DEPLOYED_SHA=""
if [ -f "$DEPLOYED_SHA_FILE" ]; then
  DEPLOYED_SHA="$(cat "$DEPLOYED_SHA_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
fi

TARGET_TAG=""
if [ -n "$DEPLOYED_SHA" ]; then
  TARGET_TAG="${DEPLOYED_SHA:0:8}"
  log "Known-good release recorded: ${TARGET_TAG} (${DEPLOYED_SHA})"
else
  # Fallback for initial installation or missing state file
  if [ -d "$ROOT_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    LOCAL_GIT_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
    if [ -n "$LOCAL_GIT_SHA" ]; then
      TARGET_TAG="${LOCAL_GIT_SHA:0:8}"
      log "State file missing; defaulting to local Git commit: ${TARGET_TAG}"
      echo "$LOCAL_GIT_SHA" > "$DEPLOYED_SHA_FILE" 2>/dev/null || true
    fi
  fi
fi

# 2. Verify target image exists locally
IMAGE_EXISTS=false
if [ -n "$TARGET_TAG" ] && docker image inspect "sashframe-app:$TARGET_TAG" >/dev/null 2>&1; then
  IMAGE_EXISTS=true
fi

if [ "$IMAGE_EXISTS" = false ]; then
  log "Warning: Docker image 'sashframe-app:${TARGET_TAG:-none}' not found locally."
  # Check if sashframe-app:latest exists
  if docker image inspect "sashframe-app:latest" >/dev/null 2>&1; then
    log "Using 'sashframe-app:latest' as safest available fallback."
    TARGET_TAG="latest"
  else
    # Find any existing sashframe-app image
    ANY_TAG="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^sashframe-app:' | grep -v '<none>' | head -n1 | cut -d: -f2 || true)"
    if [ -n "$ANY_TAG" ]; then
      log "Using existing image 'sashframe-app:${ANY_TAG}' as fallback."
      TARGET_TAG="$ANY_TAG"
    else
      # Pristine initial install: no images exist yet. Build initial image.
      log "No existing Sashframe images found. Building initial image..."
      TARGET_TAG="${TARGET_TAG:-latest}"
      IMAGE_TAG="$TARGET_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" --profile tools build
      docker tag "sashframe-app:$TARGET_TAG" "sashframe-app:latest" 2>/dev/null || true
      docker tag "sashframe-photo-processor:$TARGET_TAG" "sashframe-photo-processor:latest" 2>/dev/null || true
    fi
  fi
fi

# 3. Check health helper
check_health() {
  local elapsed=0
  while [ "$elapsed" -lt "$HEALTH_TIMEOUT_SECS" ]; do
    if curl -fsS "$APP_HEALTH_URL" 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
      return 0
    fi
    sleep "$HEALTH_INTERVAL_SECS"
    elapsed=$((elapsed + HEALTH_INTERVAL_SECS))
  done
  return 1
}

# 4. Check if container is already running and healthy with the target image
IS_RUNNING=false
if docker inspect --format '{{.State.Running}}' sashframe-app 2>/dev/null | grep -q "true"; then
  IS_RUNNING=true
fi

if [ "$IS_RUNNING" = true ]; then
  # If already running, check if it responds to healthcheck
  if curl -fsS "$APP_HEALTH_URL" 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    log "Sashframe application is already running and healthy (${TARGET_TAG})."
    exit 0
  fi
fi

# 5. Start container with explicit IMAGE_TAG
log "Starting Sashframe application container with image tag '${TARGET_TAG}'..."
IMAGE_TAG="$TARGET_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" up -d --remove-orphans sashframe-app

# 6. Wait for health endpoint
log "Verifying application readiness at ${APP_HEALTH_URL} (timeout ${HEALTH_TIMEOUT_SECS}s)..."
if check_health; then
  log "Sashframe application is healthy and ready!"
  exit 0
else
  log "Error: Sashframe application failed to report healthy within ${HEALTH_TIMEOUT_SECS}s." >&2
  exit 1
fi
