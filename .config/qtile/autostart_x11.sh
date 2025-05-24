#!/usr/bin/env bash 

export PATH="/usr/local/bin:$PATH"
#xrandr --output Virtual-1 --mode 1920x1200 --rate 60

# Start notification daemon
/usr/local/bin/dunst &  

# ── Keyring (run *before* any app that needs secrets) ────────────────────
eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg)"

# ── Policy-kit agent (package name: polkit-gnome) ────────────────────────
polkit-kde-agent-1 &
gsettings set org.gnome.desktop.interface gtk-theme Adwaita:dark
# ── Set Session Variables and Theming ────────────────────────────────────────────────

if [ ! -f /tmp/qtile_autostart_done ]; then
  # Set XDG_CURRENT_DESKTOP
  xprop -root -set _NET_WM_DESKTOP_ENVIRONMENT "Qtile"
  touch /tmp/qtile_autostart_done
fi

if [ ! -f /tmp/qtile_darkmode_set ]; then
  # For GTK applications
  export GTK_THEME=Adwaita:dark 
  export GTK_APPLICATION_PREFERENCES=prefer-dark-theme=1
  # For Qt applications (Qt 5 and 6)
  export QT_STYLE_OVERRIDE=adwaita-dark # 
  export QT_QPA_PLATFORMTHEME="qt5ct" #
  touch /tmp/qtile_darkmode_set
fi

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
picom -b --config ~/.config/picom/picom.conf

# wallpaper service
variety --resume &

# screen-locker on suspend/idle (X11)
# ── blank after 5 min ─────────────────────────────────────────────────────
xset s 300 -dpms

# ── on suspend/idle, pick a random lock-image and run i3lock ──────────────
# blank after 5 min
xset s 300 -dpms
# lock using our script
xss-lock -- ~/.config/qtile/lock_with_random_bg_x11.sh &

