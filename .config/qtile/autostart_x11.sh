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
gsettings set org.gnome.desktop.interface gtk-theme Adwaita:dark
# ── Set Session Variables and Theming ────────────────────────────────────────────────

# Set XDG_CURRENT_DESKTOP
xprop -root -set _NET_WM_DESKTOP_ENVIRONMENT "Qtile"

# For GTK applications
export GTK_THEME=Adwaita:dark 
export XDG_CURRENT_DESKTOP=Qtile
export DESKTOP_SESSION=qtile
flatpak override --user --env=GTK_THEME=Adwaita:dark
export GTK_APPLICATION_PREFERENCES=prefer-dark-theme=1
# For Qt applications (Qt 5 and 6)
export QT_STYLE_OVERRIDE=adwaita-dark # 
export QT_QPA_PLATFORMTHEME=qt5ct #



# ── Tray apps ────────────────────────────────────────────────────────────
nm-applet &
#blueman-applet &              # requires: sudo dnf install blueman (not to be found on these corpo distros)

# screenshots
flatpak run org.flameshot.Flameshot &
# ── Clipboard manager ────────────────────────────────────────────────────
copyq &                       # dnf install copyq

# ── Cursor + View Settings ───────────────────────────────────
export GTK_THEME=Adwaita:dark
export QTILE_CHECK_SKIP_STUBS=1
export XCURSOR_THEME="Dracula"
export XCURSOR_SIZE="24"

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
