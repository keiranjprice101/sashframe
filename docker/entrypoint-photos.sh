#!/usr/bin/env bash
set -e

# Target UID and GID (default 1000)
TARGET_UID="${PUID:-1000}"
TARGET_GID="${PGID:-1000}"

# If running as root, ensure directories exist, fix ownership, and drop privileges
if [ "$(id -u)" -eq 0 ]; then
  # Ensure appuser matches TARGET_UID / TARGET_GID
  CURRENT_UID="$(id -u appuser 2>/dev/null || echo "")"
  CURRENT_GID="$(id -g appuser 2>/dev/null || echo "")"

  if [ -n "$CURRENT_UID" ] && [ "$CURRENT_UID" != "$TARGET_UID" ]; then
    usermod -o -u "$TARGET_UID" appuser 2>/dev/null || true
  fi
  if [ -n "$CURRENT_GID" ] && [ "$CURRENT_GID" != "$TARGET_GID" ]; then
    groupmod -o -g "$TARGET_GID" appuser 2>/dev/null || true
  fi

  # Create photo directories if they don't exist yet
  IN_DIR="${PHOTO_INPUT_DIR:-/data/photos/incoming}"
  OUT_DIR="${PHOTO_OUTPUT_DIR:-/data/photos/processed}"
  MAN_DIR="$(dirname "${PHOTO_MANIFEST:-/data/photos/manifest.json}")"

  mkdir -p "$IN_DIR" "$OUT_DIR" "$MAN_DIR" 2>/dev/null || true

  # Ensure target user owns /data/photos and can write to it
  if [ -d "/data/photos" ]; then
    chown -R "$TARGET_UID:$TARGET_GID" /data/photos 2>/dev/null || true
    chmod -R u+rwX,g+rwX,o+rX /data/photos 2>/dev/null || true
  fi

  # Drop root privileges and execute command as appuser
  exec gosu "$TARGET_UID:$TARGET_GID" "$@"
else
  # Already running as unprivileged user
  mkdir -p "${PHOTO_INPUT_DIR:-/data/photos/incoming}" \
           "${PHOTO_OUTPUT_DIR:-/data/photos/processed}" \
           "$(dirname "${PHOTO_MANIFEST:-/data/photos/manifest.json}")" 2>/dev/null || true
  exec "$@"
fi
