#!/usr/bin/env bash
# Full system update for the qtile CheckUpdates widget (FreeBSD).
# The password is asked once up front; a keep-alive refreshes the sudo
# ticket so the later steps never prompt again (pkg can outrun sudo's
# 5-minute timestamp_timeout on a large upgrade).

set -u

# Window title via OSC 0. Deliberately not kitty's --title, which pins the
# title and ignores the app's own updates - here it should track the phase,
# so a bare password prompt always names what it is about to authorise.
title() { printf '\033]0;%s\007' "$1"; }
trap 'title "System Update"' EXIT

title 'System Update - password authorises pkg update + upgrade'
echo '================================================================'
echo ' SYSTEM UPDATE (FreeBSD / pkg)'
echo ' Your password authorises both steps, in this order:'
echo '   1/2  sudo pkg update      (refresh the repository catalogue)'
echo '   2/2  sudo pkg upgrade     (upgrade all installed packages)'
echo ' Nothing else will ask you again. Close this window to cancel.'
echo '================================================================'
echo
if ! sudo -v; then
    title 'System Update - ABORTED (no sudo)'
    echo 'No sudo privileges - aborting.'
    read -r _
    exit 1
fi

# Keep the sudo timestamp alive for as long as this script runs.
while true; do sudo -n true; sleep 50; done &
sudo_keepalive=$!
trap 'kill "$sudo_keepalive" 2>/dev/null; title "System Update"' EXIT

title 'System Update 1/2 - pkg update'
echo; echo '--- 1/2: Refreshing pkg repository catalogue ---'
sudo -n pkg update

title 'System Update 2/2 - pkg upgrade'
echo; echo '--- 2/2: Upgrading installed packages ---'
sudo -n pkg upgrade -y

title 'System Update - done, press Enter to close'
echo; echo '--- All updates complete. Press Enter to close. ---'
read -r _
