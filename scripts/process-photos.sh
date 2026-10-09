#!/usr/bin/env bash
# ==============================================================================
# Sashframe - One-Shot Batch Photo Processor
#
# Runs the containerized batch photo reconciliation pipeline:
# - Mounts host photo directory (/var/lib/sashframe/photos)
# - Validates incoming photos, applies EXIF rotation, resizes, converts to WebP
# - Reconciles deleted photos, atomically updates manifest.json
# - Exits 0 and removes the temporary container (--rm)
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-/etc/sashframe/sashframe.env}"

if [ -f "$ENV_FILE" ]; then
  ENV_ARGS=(--env-file "$ENV_FILE")
elif [ -f "$ROOT_DIR/.env" ]; then
  ENV_ARGS=(--env-file "$ROOT_DIR/.env")
else
  ENV_ARGS=()
fi

STATE_DIR="${SASHFRAME_STATE_DIR:-/var/lib/sashframe/state}"
DEPLOYED_SHA="$(cat "$STATE_DIR/deployed-sha" 2>/dev/null || git -C "$ROOT_DIR" rev-parse --short=8 HEAD 2>/dev/null || echo "latest")"
export IMAGE_TAG="${IMAGE_TAG:-$DEPLOYED_SHA}"

cd "$ROOT_DIR"
docker compose "${ENV_ARGS[@]}" run --rm sashframe-photo-processor
