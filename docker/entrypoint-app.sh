#!/usr/bin/env bash
set -e

TARGET_UID="${PUID:-1000}"
TARGET_GID="${PGID:-1000}"

if [ "$(id -u)" -eq 0 ]; then
  CURRENT_UID="$(id -u node 2>/dev/null || echo "")"
  CURRENT_GID="$(id -g node 2>/dev/null || echo "")"

  if [ -n "$CURRENT_UID" ] && [ "$CURRENT_UID" != "$TARGET_UID" ]; then
    usermod -o -u "$TARGET_UID" node 2>/dev/null || true
  fi
  if [ -n "$CURRENT_GID" ] && [ "$CURRENT_GID" != "$TARGET_GID" ]; then
    groupmod -o -g "$TARGET_GID" node 2>/dev/null || true
  fi

  exec gosu "$TARGET_UID:$TARGET_GID" "$@"
else
  exec "$@"
fi
