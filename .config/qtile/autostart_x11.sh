#!/usr/bin/env bash 

export PATH="/usr/local/bin:$PATH"

# NOTE: no xrandr mode-setting here. Under the scfb driver the resolution is the
# fixed EFI framebuffer mode (set at the loader via efi_max_resolution) and xrandr
# cannot change it. 16:10 therefore depends on the VM's EFI GOP offering 1920x1200.

# Start notification daemon
/usr/local/bin/dunst &  

# ── Keyring (run *before* any app that needs secrets) ────────────────────
# HANDLED IN SESSION AUTOSTART NOW
# eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg)"
# export SSH_AUTH_SOCK

# # Sync the variables to the global D-Bus and Systemd environment
# dbus-update-activation-environment --systemd GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
# # ── Policy-kit agent (package name: polkit-gnome) ────────────────────────
# KDE Polkit agent (works with Qtile). On FreeBSD ports install under
# /usr/local/libexec; the Linux path is kept as a fallback for portability.
for _polkit in \
    /usr/local/libexec/polkit-kde-authentication-agent-1 \
    /usr/local/libexec/polkit-gnome-authentication-agent-1 \
    /usr/libexec/polkit-kde-authentication-agent-1; do
    if [ -x "$_polkit" ]; then
        "$_polkit" &
        break
    fi
done
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
# root-window cursor. `-cursor_name left_ptr` loads the ugly white CORE-X arrow;
# `-xcf` loads the themed Rosé Pine (BreezeX) pointer instead. Also export the
# Xcursor env so apps this script launches inherit the themed cursor even when the
# session wasn't started through the qtile-session launcher.
export XCURSOR_THEME=BreezeX-RosePine-Linux
export XCURSOR_SIZE=24
xsetroot -xcf "$HOME/.icons/BreezeX-RosePine-Linux/cursors/left_ptr" 24

# Toolkit env (QT_QPA_PLATFORMTHEME, XCURSOR_*) lives in bin/starting-qtile.sh so
# that everything qtile spawns inherits it, not just the apps started below.
xprop -root -set _NET_WM_DESKTOP_ENVIRONMENT "Qtile"
export XDG_CURRENT_DESKTOP=Qtile
export DESKTOP_SESSION=qtile

# ── Tray apps ────────────────────────────────────────────────────────────
# FreeBSD has no NetworkManager; nm-applet is not packaged. Networking is
# handled by rc.conf / netif, so only start the applet if it somehow exists.
command -v nm-applet >/dev/null 2>&1 && nm-applet &
#blueman-applet &              # requires: pkg install blueman

# screenshots: NO resident flameshot daemon - it caches the screen geometry
# and xrdp changes it per connection. Print / Shift+Print in config.py run
# ~/bin/screenshot.sh, which always starts a fresh process.
# ── Clipboard manager ────────────────────────────────────────────────────
copyq &                       # pkg install copyq

# ── Cursor + View Settings ───────────────────────────────────
export QTILE_CHECK_SKIP_STUBS=1

# German keyboard layout. On EL8 gsd-keyboard set this; with no GNOME here it has
# to be asserted explicitly (the xorg.conf.d keymap covers the SDDM greeter, this
# covers the running qtile session).
setxkbmap de &

# compositor for transparency/shadows (X11 sessions). Enables the bar's 0.70
# opacity to composite cleanly and removes tearing once the accelerated
# virtio-gpu/modesetting driver is active (xrender backend works on scfb too).
picom -b --config ~/.config/picom/picom.conf &

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

# ── launch user applications ──────────────
# FreeBSD has no flatpak; everything is a native pkg. LibreWolf is the browser
# here (no Brave port); launch whichever is installed so a missing app is a
# silent no-op, not an error.
for _browser in librewolf firefox chromium; do
    if command -v "$_browser" >/dev/null 2>&1; then "$_browser" & break; fi
done

# native apps & snaps
codium &
nautilus &
