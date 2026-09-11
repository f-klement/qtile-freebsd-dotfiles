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

# ── 3. Theming environment ────────────────────────────────────────────────
# Everything qtile spawns (rofi, keybindings, tray apps) inherits this, so this
# is THE place for toolkit env - not autostart_x11.sh (that only reaches the
# handful of apps it launches itself).
#   GTK   : themed via XSETTINGS (gsd-xsettings <- gsettings), see autostart_x11.sh.
#           Do NOT export GTK_THEME here: it hard-forces one theme, disables the
#           prefer-dark switch and makes libadwaita apps fall back to plain GTK4.
#   Qt5   : qt5ct (Fusion + ~/.config/qt5ct/colors/rose-pine.conf)
#   Cursor: BreezeX-RosePine (~/.icons), also set in gsettings for GTK apps
export QT_QPA_PLATFORMTHEME=qt5ct
export XCURSOR_THEME=BreezeX-RosePine-Linux
export XCURSOR_SIZE=24
# Keep Python bytecode out of the stowed config dirs: ~/.config/qtile and the
# ranger plugins are symlinks into ~/.dotfiles, so qtile compiling config.py
# would otherwise drop __pycache__ into the repo.
export PYTHONPYCACHEPREFIX="$HOME/.cache/python-pycache"
# make D-Bus-activated and systemd --user-launched apps (flatpak, portals) see the same
dbus-update-activation-environment --systemd QT_QPA_PLATFORMTHEME XCURSOR_THEME XCURSOR_SIZE PYTHONPYCACHEPREFIX

# ── 4. The Window Manager Handover ───────────────────────────────────────
# glibc allocator tuning. MALLOC_TRIM_THRESHOLD_ pins the trim threshold and
# disables glibc's dynamic auto-tuning, which otherwise drifts upward until the
# main arena is never trimmed -- that is what lets qtile's heap ratchet to
# hundreds of MB and then get swapped out. MALLOC_ARENA_MAX caps the per-thread
# arenas (qtile runs ~9 threads; default would allow 8*ncores of them).
export MALLOC_TRIM_THRESHOLD_=131072
export MALLOC_ARENA_MAX=2

# Start Qtile if available
if [[ -x "$VENV_QTILE" ]]; then
  echo "[$(date)] Starting Qtile from $VENV_QTILE" >> "$LOGFILE"
  exec "$VENV_QTILE" start
else
  echo "[$(date)] ERROR: Qtile binary not found at $VENV_QTILE" >> "$LOGFILE"
  exit 1
fi
