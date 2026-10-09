#!/usr/bin/env bash
# ==============================================================================
# Sashframe - Host Auto-Update Deployment Script
#
# Periodically executed on the host (e.g. by systemd timer).
# Flow:
# 1. Fetch remote tracking branch (origin/main).
# 2. Check if remote commit SHA differs from /var/lib/sashframe/state/deployed-sha.
# 3. If changed:
#    - Pull/checkout new source cleanly.
#    - Build new Docker images tagged with target Git SHA.
#    - Do NOT stop current containers if the build fails.
#    - Start new containers with new IMAGE_TAG.
#    - Poll GET /health endpoint for readiness.
#    - On success: persist new deployed SHA and conservatively prune dangling images.
#    - On failure: roll back to previous SHA and containers.
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
if [ ! -d "$STATE_DIR" ] && [ -w "$ROOT_DIR/data" ]; then
  STATE_DIR="$ROOT_DIR/data/state"
fi
mkdir -p "$STATE_DIR" 2>/dev/null || true

DEPLOYED_SHA_FILE="$STATE_DIR/deployed-sha"
APP_HEALTH_URL="${APP_HEALTH_URL:-http://127.0.0.1:4321/health}"
HEALTH_TIMEOUT_SECS=45
HEALTH_INTERVAL_SECS=2

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
  echo "[Update] Error: Neither docker compose nor podman-compose found." >&2
  exit 1
fi

log() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%SZ')] [Update] $*"
}

# 1. Fetch tracked Git remote
REMOTE="${GIT_REMOTE:-origin}"
BRANCH="${GIT_BRANCH:-main}"

log "Checking remote '$REMOTE/$BRANCH' for updates..."
if ! git fetch "$REMOTE" "$BRANCH" --quiet 2>/dev/null; then
  log "Warning: Unable to fetch from remote '$REMOTE/$BRANCH'. Network might be unavailable. Skipping."
  exit 0
fi

# 2. Determine target commit SHA and currently deployed SHA
TARGET_SHA="$(git rev-parse "$REMOTE/$BRANCH")"
TARGET_TAG="${TARGET_SHA:0:8}"

CURRENT_SHA=""
if [ -f "$DEPLOYED_SHA_FILE" ]; then
  CURRENT_SHA="$(cat "$DEPLOYED_SHA_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
fi
CURRENT_TAG="${CURRENT_SHA:0:8}"

if [ -n "$CURRENT_SHA" ] && [ "$TARGET_SHA" = "$CURRENT_SHA" ]; then
  log "Already up to date at commit ${TARGET_TAG}. Nothing to do."
  exit 0
fi

log "Update detected: ${CURRENT_TAG:-none} -> ${TARGET_TAG}"
PREV_HEAD="$(git rev-parse HEAD)"

# Function to check health endpoint
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

# 3. Checkout source cleanly
log "Updating working tree to ${TARGET_TAG}..."
if ! git checkout -f "$TARGET_SHA" --quiet; then
  log "Error: Failed to checkout commit $TARGET_SHA."
  exit 1
fi

# Setup Compose environment file argument
COMPOSE_ENV_ARGS=()
if [ -f "/etc/sashframe/sashframe.env" ]; then
  COMPOSE_ENV_ARGS=(--env-file "/etc/sashframe/sashframe.env")
fi

# 4. Build new Docker images tagged with TARGET_TAG
log "Building Docker images for tag: ${TARGET_TAG}..."
if ! IMAGE_TAG="$TARGET_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" build; then
  log "Error: Docker image build failed for ${TARGET_TAG}. Leaving current deployment running."
  git checkout -f "$PREV_HEAD" --quiet || true
  exit 1
fi

# 5. Deploy the newly built version
log "Deploying version ${TARGET_TAG} with Docker Compose..."
if ! IMAGE_TAG="$TARGET_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" up -d; then
  log "Error: Failed to launch containers for ${TARGET_TAG}. Rolling back..."
  if [ -n "$CURRENT_TAG" ]; then
    IMAGE_TAG="$CURRENT_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" up -d || true
  fi
  git checkout -f "$PREV_HEAD" --quiet || true
  exit 1
fi

# 6. Wait for health check
log "Verifying application health at ${APP_HEALTH_URL} (timeout ${HEALTH_TIMEOUT_SECS}s)..."
if check_health; then
  log "Healthcheck verified successfully for ${TARGET_TAG}!"
  # Record the deployed SHA
  echo "$TARGET_SHA" > "$DEPLOYED_SHA_FILE" 2>/dev/null || sudo bash -c "echo '$TARGET_SHA' > '$DEPLOYED_SHA_FILE'"
  log "Deployment of ${TARGET_TAG} complete and recorded in ${DEPLOYED_SHA_FILE}."

  # Conservative image cleanup (only dangling / untagged layers)
  if command -v docker >/dev/null 2>&1; then
    docker image prune -f >/dev/null 2>&1 || true
  elif command -v podman >/dev/null 2>&1; then
    podman image prune -f >/dev/null 2>&1 || true
  fi

  # Refresh kiosk display if running
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet sashframe-kiosk.service 2>/dev/null; then
    log "Restarting sashframe-kiosk.service to display updated interface..."
    sudo systemctl restart sashframe-kiosk.service 2>/dev/null || true
  fi

  exit 0
else
  log "Error: Health check failed for ${TARGET_TAG}! Initiating automatic rollback..."
  if [ -n "$CURRENT_TAG" ]; then
    log "Restoring previous working deployment (${CURRENT_TAG})..."
    git checkout -f "$PREV_HEAD" --quiet || true
    IMAGE_TAG="$CURRENT_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" up -d || true
    if check_health; then
      log "Rollback to ${CURRENT_TAG} succeeded."
    else
      log "Critical: Rollback failed to report healthy."
    fi
  else
    log "No previous deployed SHA on record to roll back to."
    git checkout -f "$PREV_HEAD" --quiet || true
  fi
  exit 1
fi
