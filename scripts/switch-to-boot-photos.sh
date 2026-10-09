#!/usr/bin/env bash
# ==============================================================================
# Sashframe - Switch Photo Ingestion to Boot-Only
# ==============================================================================
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "[Error] Please run this script with sudo:" >&2
  echo "  sudo $0" >&2
  exit 1
fi

echo "1. Stopping and disabling legacy photo sync timer..."
systemctl stop sashframe-photo-sync.timer 2>/dev/null || true
systemctl disable sashframe-photo-sync.timer 2>/dev/null || true
rm -f /etc/systemd/system/sashframe-photo-sync.timer
rm -f /etc/systemd/system/timers.target.wants/sashframe-photo-sync.timer

echo "2. Enabling oneshot boot photo ingestion service..."
systemctl enable sashframe-photo-sync.service 2>/dev/null || true

echo "3. Reloading systemd..."
systemctl daemon-reload

echo ""
echo "✓ Successfully switched photo ingestion to boot-only!"
echo "  - Legacy timer removed: /etc/systemd/system/sashframe-photo-sync.timer"
echo "  - Service enabled: sashframe-photo-sync.service ($(systemctl is-enabled sashframe-photo-sync.service 2>/dev/null || echo 'unknown'))"
