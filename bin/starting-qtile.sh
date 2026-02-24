#!/usr/bin/env bash
set -euo pipefail

LOGFILE="${HOME}/.local/share/qtile-startup.log"
VENV_QTILE="${HOME}/.local/venvs/qtile/bin/qtile"

echo "[$(date)] Starting custom Qtile session" >> "$LOGFILE"

# Wait for GNOME to initialize
sleep 5
# ── 1. The Purge ─────────────────────────────────────────────────────────
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

# ── 2. The Environment Bridge ────────────────────────────────────────────
# Connect to the PAM-unlocked daemon and inject the socket paths 
# into this bash environment BEFORE Qtile launches.
eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg)"
export SSH_AUTH_SOCK GNOME_KEYRING_CONTROL

# Sync the variables to the global systemd/D-Bus user session just to be safe
dbus-update-activation-environment --systemd GNOME_KEYRING_CONTROL SSH_AUTH_SOCK

# ── 3. The Window Manager Handover ───────────────────────────────────────
# Start Qtile if available
if [[ -x "$VENV_QTILE" ]]; then
  echo "[$(date)] Starting Qtile from $VENV_QTILE" >> "$LOGFILE"
  exec "$VENV_QTILE" start
else
  echo "[$(date)] ERROR: Qtile binary not found at $VENV_QTILE" >> "$LOGFILE"
  exit 1
fi
