#!/bin/bash
# Clear the stale Raspberry Pi hardware cursor by releasing/reacquiring tty1.
set -euo pipefail
kiosk_pid="${1:?Expected kiosk main PID}"

# Type=simple starts before Cage has launched its browser. Wait for that child.
ready=false
for ((attempt = 0; attempt < 30; attempt++)); do
    if ! kill -0 "$kiosk_pid" 2>/dev/null; then
        echo '[Cursor] Kiosk exited before cursor reset.' >&2
        exit 1
    fi
    if pgrep -P "$kiosk_pid" -f chromium >/dev/null; then
        ready=true
        break
    fi
    sleep 1
done
if [ "$ready" != true ]; then
    echo '[Cursor] Browser did not start; skipping cursor reset.' >&2
    exit 0
fi
sleep 3

# Do not take the console back if someone switched away from the kiosk.
if [ "$(fgconsole)" != 1 ]; then
    echo '[Cursor] tty1 is not active; skipping cursor reset.'
    exit 0
fi
trap 'chvt 1' EXIT
chvt 2
sleep 2
chvt 1
trap - EXIT
echo '[Cursor] Refreshed tty1 to clear the stale hardware cursor.'
