#!/usr/bin/env bash 

export PATH="/usr/local/bin:$PATH"
#xrandr --output Virtual-1 --mode 1920x1200 --rate 60

# Start notification daemon
/usr/local/bin/dunst &  

# ── Keyring (run *before* any app that needs secrets) ────────────────────
# HANDLED IN SESSION AUTOSTART NOW
# eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg)"
# export SSH_AUTH_SOCK

# # Sync the variables to the global D-Bus and Systemd environment
# dbus-update-activation-environment --systemd GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
# # ── Policy-kit agent (package name: polkit-gnome) ────────────────────────
# KDE Polkit agent (works with Qtile)
if [ -x /usr/libexec/polkit-kde-authentication-agent-1 ]; then
    /usr/libexec/polkit-kde-authentication-agent-1 &
fi
# ── Theming (Rose Pine, dark) ─────────────────────────────────────────────
# gsd-xsettings survives the GNOME purge on purpose: it turns these gsettings
# into XSETTINGS, which every GTK2/GTK3/GTK4/Chromium/Electron app on the display
# reads - including apps launched later from rofi that never see this script's
# environment. gsettings persist in dconf, re-set here so a reset can't undo it.
# NOTE: the theme name must be a directory name (~/.themes/<name>). The
# "Adwaita:dark" form is GTK_THEME-env syntax only; via XSETTINGS it resolves to
# no theme at all and GTK silently falls back to LIGHT Adwaita - the old bug.
gsettings set org.gnome.desktop.interface gtk-theme        'rose-pine-gtk'
gsettings set org.gnome.desktop.interface icon-theme       'Papirus-Dark'
gsettings set org.gnome.desktop.interface cursor-theme     'BreezeX-RosePine-Linux'
gsettings set org.gnome.desktop.interface cursor-size      24
gsettings set org.gnome.desktop.interface font-name        'Cantarell 11'
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono Nerd Font 10'
# root-window cursor (apps not going through XSETTINGS/Xcursor env)
xsetroot -cursor_name left_ptr

# Toolkit env (QT_QPA_PLATFORMTHEME, XCURSOR_*) lives in bin/starting-qtile.sh so
# that everything qtile spawns inherits it, not just the apps started below.
xprop -root -set _NET_WM_DESKTOP_ENVIRONMENT "Qtile"
export XDG_CURRENT_DESKTOP=Qtile
export DESKTOP_SESSION=qtile

# ── Tray apps ────────────────────────────────────────────────────────────
nm-applet &
#blueman-applet &              # requires: sudo dnf install blueman (not to be found on these corpo distros)

# screenshots: NO resident flameshot daemon - it caches the screen geometry
# and xrdp changes it per connection. Print / Shift+Print in config.py run
# ~/bin/screenshot.sh, which always starts a fresh process.
# ── Clipboard manager ────────────────────────────────────────────────────
copyq &                       # dnf install copyq

# ── Cursor + View Settings ───────────────────────────────────
export QTILE_CHECK_SKIP_STUBS=1

# compositor for transparency/shadows (X11 sessions)
#picom -b --config ~/.config/picom/picom.conf &

# wallpaper service
# Enumerate the wallpaper list ONCE at startup. The previous version ran a full
# recursive find every 300s (288 directory walks/day), pulling dir entries and
# image data through the page cache and evicting something else each time.
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
mapfile -t WALLPAPERS < <(find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null)

feh_random() {
  (( ${#WALLPAPERS[@]} == 0 )) && return 0
  feh --bg-fill "${WALLPAPERS[RANDOM % ${#WALLPAPERS[@]}]}"
}

# initial wallpaper
feh_random

# every 300 seconds (5m), pick & set a new one
(
  while sleep 300; do
    feh_random
  done
) &

# screen-locker on suspend/idle (X11)
# ── blank after 5 min ─────────────────────────────────────────────────────
xset s 300 -dpms

# ── on suspend/idle, pick a random lock-image and run i3lock ──────────────
# blank after 5 min
xset s 300 -dpms
# lock using our script
# NOTE: previously wrapped in `dbus-run-session`, which started a SECOND session
# bus just for the locker -- xss-lock then sat on a different bus than the rest
# of the session, so idle/inhibit signalling between apps and the locker could
# not work. Run it on the session's existing bus.
xss-lock -- ~/.config/qtile/lock_with_random_bg_x11.sh &

# ── lauch user applications ──────────────
# flatpak
# Prefer native Brave (RPM) once installed; flatpak is the fallback.
if command -v brave-browser >/dev/null 2>&1; then brave-browser & else flatpak run com.brave.Browser & fi
flatpak run md.obsidian.Obsidian &

# native apps & snaps
codium &
nautilus &
