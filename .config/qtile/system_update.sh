#!/usr/bin/env bash
# Full system update for the qtile CheckUpdates widget.
# The password is asked once up front; a keep-alive refreshes the sudo
# ticket so the later package managers never prompt again (dnf easily
# outruns sudo's 5-minute timestamp_timeout).

set -u

export DEBIAN_FRONTEND=noninteractive
export HOMEBREW_NO_ENV_HINTS=1   # keeps the output readable in the popup terminal

# Window title via OSC 0. Deliberately not kitty's --title, which pins the
# title and ignores the app's own updates - here it should track the phase,
# so a bare password prompt always names what it is about to authorise.
title() { printf '\033]0;%s\007' "$1"; }
trap 'title "System Update"' EXIT

title 'System Update - password authorises dnf + flatpak + snap + brew'
echo '================================================================'
echo ' SYSTEM UPDATE'
echo ' Your password authorises all four steps, in this order:'
echo '   1/4  sudo dnf update -y'
echo '   2/4  sudo flatpak update -y'
echo '   3/4  sudo snap refresh'
echo '   4/4  brew update && brew upgrade --yes   (unprivileged)'
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

title 'System Update 1/4 - dnf update'
echo; echo '--- 1/4: Updating DNF packages ---'
sudo -n dnf update -y

title 'System Update 2/4 - flatpak update'
echo; echo '--- 2/4: Updating Flatpak packages ---'
sudo -n flatpak update -y --noninteractive

title 'System Update 3/4 - snap refresh'
echo; echo '--- 3/4: Updating Snap packages ---'
sudo -n snap refresh

# Homebrew refuses to run as root, so this one stays unprivileged.
# --yes: brew 6 asks for confirmation whenever an upgrade pulls in
# dependencies that were not named on the command line (install.rb, ask_prompt_needed?).
title 'System Update 4/4 - brew upgrade'
echo; echo '--- 4/4: Updating Homebrew packages ---'
/home/linuxbrew/.linuxbrew/bin/brew update
/home/linuxbrew/.linuxbrew/bin/brew upgrade --yes

title 'System Update - done, press Enter to close'
echo; echo '--- All updates complete. Press Enter to close. ---'
read -r _
