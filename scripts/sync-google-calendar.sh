#!/usr/bin/env bash
# Run one Google Calendar refresh using the deployed worker image.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-/etc/sashframe/sashframe.env}"
if [ ! -f "$ENV_FILE" ] && [ -f "$ROOT_DIR/.env" ]; then
  ENV_FILE="$ROOT_DIR/.env"
fi
ENV_ARGS=()
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
  ENV_ARGS=(--env-file "$ENV_FILE")
fi
if [ "${SASHFRAME_CALENDAR_PROVIDER:-shifter}" != google ]; then
  echo "[Google Calendar] Calendar provider is not google; skipping."
  exit 0
fi
STATE_DIR="${SASHFRAME_STATE_DIR:-/var/lib/sashframe/state}"
DEPLOYED_SHA="$(cat "$STATE_DIR/deployed-sha" 2>/dev/null || git -C "$ROOT_DIR" rev-parse --short=8 HEAD 2>/dev/null || echo latest)"
export IMAGE_TAG="${IMAGE_TAG:-${DEPLOYED_SHA:0:8}}"
cd "$ROOT_DIR"
docker compose "${ENV_ARGS[@]}" run --pull never --rm --no-deps sashframe-calendar-sync
