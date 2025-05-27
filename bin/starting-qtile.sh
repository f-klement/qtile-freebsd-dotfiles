#!/usr/bin/env bash
set -euo pipefail

LOGFILE="${HOME}/.local/share/qtile-startup.log"
VENV_QTILE="${HOME}/.local/venvs/qtile/bin/qtile"

echo "[$(date)] Starting custom Qtile session" >> "$LOGFILE"

# Wait for GNOME to initialize
sleep 5

# Try killing known GNOME session processes if they exist
for PROC in \
  gnome-shell \
  gnome-software \
  gnome-shell-calendar-server \
  evolution-calendar-factory-subprocess \
  evolution-addressbook-factory-subprocess; do
  if pgrep -x "$PROC" > /dev/null; then
    echo "[$(date)] Killing $PROC" >> "$LOGFILE"
    pkill -x "$PROC" || echo "[$(date)] Warning: Failed to kill $PROC" >> "$LOGFILE"
  fi
done

# Start Qtile if available
if [[ -x "$VENV_QTILE" ]]; then
  echo "[$(date)] Starting Qtile from $VENV_QTILE" >> "$LOGFILE"
  "$VENV_QTILE" start &
else
  echo "[$(date)] ERROR: Qtile binary not found at $VENV_QTILE" >> "$LOGFILE"
fi
