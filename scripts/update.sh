#!/usr/bin/env bash
# ==============================================================================
# Sashframe - Power-On Software Auto-Updater
#
# Executed by systemd (sashframe-updater.service) once on system power-on,
# ordered after the known-good application is already running and healthy.
#
# Flow:
# 1. Fetch remote tracking branch (origin/main) with a bounded network timeout.
# 2. Check if remote commit SHA differs from /var/lib/sashframe/state/deployed-sha.
# 3. If no change: exit 0 immediately (no Docker build or restart).
# 4. If changed:
#    - Checkout target commit source cleanly.
#    - Build candidate Docker image(s) tagged with candidate Git SHA while the
#      existing application remains running.
#    - If candidate build fails: log error, leave current deployment running, exit.
#    - Deploy candidate container with candidate IMAGE_TAG.
#    - Poll GET /health endpoint for readiness within a bounded timeout.
#    - On health success: atomically persist new deployed SHA, prune dangling
#      intermediate layers, refresh kiosk display, and exit 0.
#    - On health failure: initiate automatic rollback to previous known-good
#      image and commit, verify rollback health, and exit 1.
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
PORT="${PORT:-4321}"
APP_HEALTH_URL="${APP_HEALTH_URL:-http://127.0.0.1:${PORT}/health}"
HEALTH_TIMEOUT_SECS=45
HEALTH_INTERVAL_SECS=2
FETCH_TIMEOUT_SECS=25

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

# Source Compose environment file argument
COMPOSE_ENV_ARGS=()
if [ -f "/etc/sashframe/sashframe.env" ]; then
  COMPOSE_ENV_ARGS=(--env-file "/etc/sashframe/sashframe.env")
fi

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

# 1. Read currently deployed SHA
CURRENT_SHA=""
if [ -f "$DEPLOYED_SHA_FILE" ]; then
  CURRENT_SHA="$(cat "$DEPLOYED_SHA_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
fi
CURRENT_TAG="${CURRENT_SHA:0:8}"
log "Current deployed release: ${CURRENT_TAG:-none} (${CURRENT_SHA:-none})"

# 2. Bounded fetch of tracked Git remote
REMOTE="${GIT_REMOTE:-origin}"
BRANCH="${GIT_BRANCH:-main}"

log "Checking remote '$REMOTE/$BRANCH' for updates (timeout ${FETCH_TIMEOUT_SECS}s)..."
if ! timeout "$FETCH_TIMEOUT_SECS" git fetch "$REMOTE" "$BRANCH" --quiet 2>/dev/null; then
  log "Network or remote repository unavailable (git fetch timed out or failed). Skipping power-on update."
  exit 0
fi

# 3. Determine target commit SHA and compare
TARGET_SHA="$(git rev-parse "$REMOTE/$BRANCH" 2>/dev/null || true)"
if [ -z "$TARGET_SHA" ]; then
  log "Warning: Unable to resolve ref '$REMOTE/$BRANCH'. Skipping update."
  exit 0
fi
TARGET_TAG="${TARGET_SHA:0:8}"
log "Target remote release: ${TARGET_TAG} (${TARGET_SHA})"

if [ -n "$CURRENT_SHA" ] && [ "$TARGET_SHA" = "$CURRENT_SHA" ]; then
  log "No update available. Current release ${CURRENT_TAG} is up to date."
  exit 0
fi

log "Update detected: ${CURRENT_TAG:-none} -> ${TARGET_TAG}"
PREV_HEAD="$(git rev-parse HEAD 2>/dev/null || echo "")"

# 4. Checkout source cleanly
log "Updating working tree to candidate ${TARGET_TAG}..."
if ! git checkout -f "$TARGET_SHA" --quiet; then
  log "Error: Failed to checkout candidate commit ${TARGET_TAG}."
  exit 0
fi

# 5. Build candidate Docker images while current app remains running
log "Starting candidate image build for tag ${TARGET_TAG}..."
if ! IMAGE_TAG="$TARGET_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" --profile tools build; then
  log "Error: Candidate image build failed for ${TARGET_TAG}. Leaving current deployment ${CURRENT_TAG} running."
  if [ -n "$PREV_HEAD" ]; then
    git checkout -f "$PREV_HEAD" --quiet || true
  fi
  exit 0
fi
log "Candidate image build succeeded for ${TARGET_TAG}."

# Tag latest so one-shot utility executions resolve candidate build
docker tag "sashframe-app:$TARGET_TAG" "sashframe-app:latest" 2>/dev/null || true
docker tag "sashframe-photo-processor:$TARGET_TAG" "sashframe-photo-processor:latest" 2>/dev/null || true

# 6. Deploy candidate application container
log "Starting candidate deployment for tag ${TARGET_TAG}..."
if ! IMAGE_TAG="$TARGET_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" up -d --remove-orphans sashframe-app; then
  log "Error: Failed to launch candidate container for ${TARGET_TAG}. Initiating automatic rollback..."
  if [ -n "$PREV_HEAD" ]; then
    git checkout -f "$PREV_HEAD" --quiet || true
  fi
  if [ -n "$CURRENT_TAG" ]; then
    IMAGE_TAG="$CURRENT_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" up -d --remove-orphans sashframe-app || true
  fi
  exit 1
fi

# 7. Verify healthcheck with bounded timeout
log "Verifying candidate application health at ${APP_HEALTH_URL} (timeout ${HEALTH_TIMEOUT_SECS}s)..."
# Brief pause to allow previous container termination and new process bind
sleep 2

if check_health; then
  log "Healthcheck succeeded for candidate ${TARGET_TAG}. Candidate accepted as new known-good release."

  # Atomically record new deployed SHA
  TEMP_SHA_FILE="$DEPLOYED_SHA_FILE.tmp.$$"
  echo "$TARGET_SHA" > "$TEMP_SHA_FILE" 2>/dev/null || sudo bash -c "echo '$TARGET_SHA' > '$TEMP_SHA_FILE'"
  mv -f "$TEMP_SHA_FILE" "$DEPLOYED_SHA_FILE" 2>/dev/null || sudo mv -f "$TEMP_SHA_FILE" "$DEPLOYED_SHA_FILE"
  log "Deployment of ${TARGET_TAG} complete and recorded in ${DEPLOYED_SHA_FILE}."

  # Conservative image cleanup: prune only untagged intermediate layers (retains previous named tags)
  if command -v docker >/dev/null 2>&1; then
    docker image prune -f >/dev/null 2>&1 || true
  elif command -v podman >/dev/null 2>&1; then
    podman image prune -f >/dev/null 2>&1 || true
  fi

  # Refresh kiosk display if active
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet sashframe-kiosk.service 2>/dev/null; then
    log "Restarting sashframe-kiosk.service to display updated interface..."
    sudo systemctl restart sashframe-kiosk.service 2>/dev/null || true
  fi

  exit 0
else
  log "Error: Healthcheck failed for candidate ${TARGET_TAG}. Candidate rejected."
  log "Initiating automatic rollback to previous release ${CURRENT_TAG:-none}..."

  # Stop failed candidate container
  docker stop sashframe-app >/dev/null 2>&1 || true

  if [ -n "$PREV_HEAD" ]; then
    git checkout -f "$PREV_HEAD" --quiet || true
  fi

  if [ -n "$CURRENT_TAG" ]; then
    docker tag "sashframe-app:$CURRENT_TAG" "sashframe-app:latest" 2>/dev/null || true
    docker tag "sashframe-photo-processor:$CURRENT_TAG" "sashframe-photo-processor:latest" 2>/dev/null || true
    IMAGE_TAG="$CURRENT_TAG" "${COMPOSE_CMD[@]}" "${COMPOSE_ENV_ARGS[@]}" up -d --remove-orphans sashframe-app || true

    if check_health; then
      log "Rollback to ${CURRENT_TAG} succeeded. Application is healthy."
    else
      log "Critical: Rollback to ${CURRENT_TAG} failed to become healthy."
    fi
  else
    log "Warning: No previous deployed SHA on record to roll back to."
  fi

  exit 1
fi
