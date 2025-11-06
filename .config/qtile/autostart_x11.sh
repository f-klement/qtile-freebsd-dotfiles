#!/usr/bin/env bash 

export PATH="/usr/local/bin:$PATH"
#xrandr --output Virtual-1 --mode 1920x1200 --rate 60

# Start notification daemon
/usr/local/bin/dunst &  

# ── Keyring (run *before* any app that needs secrets) ────────────────────
eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg)"
export SSH_AUTH_SOCK

# ── Policy-kit agent (package name: polkit-gnome) ────────────────────────
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
feh_random() {
  # directory containing your wallpapers (and subfolders)
  local dir=~/Pictures/wallpapers

  # find all .jpg/.png files, pick one at random
  local file
  file=$(find "$dir" -type f \( -iname '*.jpg' -o -iname '*.png' \) | shuf -n1)

  # set it as your background (fill mode)
  feh --bg-fill "$file"
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
exec dbus-run-session --exit-with-session xss-lock -- ~/.config/qtile/lock_with_random_bg_x11.sh &

# ── lauch user applications ──────────────
# flatpak
flatpak run com.brave.Browser &
flatpak run md.obsidian.Obsidian &

# native apps & snaps
codium &
nautilus &
slack &
