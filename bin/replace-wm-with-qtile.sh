#!/usr/bin/env bash
# give GNOME a moment to settle
sleep 2
# stop the current WM (gnome-shell)
killall gnome-shell
# start Qtile as the new WM
exec home/admin/.local/venvs/qtile/bin/qtile start
