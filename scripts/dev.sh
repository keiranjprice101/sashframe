#!/usr/bin/env bash
set -e

# Change to repository root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Determine Python binary (.venv preferred, fallback to system python3)
if [ -f "$ROOT_DIR/.venv/bin/python3" ]; then
  PYTHON_BIN="$ROOT_DIR/.venv/bin/python3"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
else
  echo "[dev.sh] Error: python3 not found. Please install Python 3."
  exit 1
fi

echo "=========================================="
echo " Starting Sashframe Development Env"
echo " - Astro dev server"
echo " - Photo ingestion processor"
echo "=========================================="

PIDS=()

cleanup() {
  echo ""
  echo "[dev.sh] Shutting down development processes..."
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  wait 2>/dev/null || true
  echo "[dev.sh] Shutdown complete."
}

trap cleanup SIGINT SIGTERM EXIT

# 1. Start Python photo processor in background
echo "[dev.sh] Starting photo watcher service..."
"$PYTHON_BIN" services/photos/processor.py &
PIDS+=($!)

# 2. Start Astro development server
echo "[dev.sh] Starting Astro development server..."
npx astro dev --ignore-lock "$@" &
PIDS+=($!)

# Wait for any process to terminate
wait -n "${PIDS[@]}" 2>/dev/null || true
