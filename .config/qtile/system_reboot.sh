#!/usr/bin/env bash
# Reboot action for the qtile power (⏻) widget.
# Exists as a file for the same reason system_update.sh does: the title
# escapes and error handling do not survive the quoting of an inline sh -c.

set -u

title() { printf '\033]0;%s\007' "$1"; }

title 'REBOOT - password will restart this machine now'
echo '================================================================'
echo ' REBOOT'
echo ' Your password runs: sudo reboot'
echo ' This machine restarts IMMEDIATELY - unsaved work will be lost.'
echo ' Close this window (or Ctrl-C) to cancel.'
echo '================================================================'
echo

if ! sudo -v; then
    title 'Reboot - ABORTED (no sudo)'
    echo 'No sudo privileges - reboot cancelled.'
    read -r _
    exit 1
fi

title 'REBOOT - rebooting now'
sudo -n reboot

# Only reached if reboot itself failed; otherwise the machine is going down.
title 'Reboot - FAILED'
echo
echo '--- Reboot command failed. Press Enter to close. ---'
read -r _
