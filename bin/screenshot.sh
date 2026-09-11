#!/usr/bin/env bash
# Screenshots on this xrdp/Xvnc desktop.
#
#   screenshot.sh gui    - flameshot region selector (Ctrl+C copy, Ctrl+S save)
#   screenshot.sh full   - whole screen -> ~/Pictures/screenshot-<ts>.png
#   screenshot.sh clip   - whole screen -> clipboard
#
# Why the dance:
# * flameshot (>=12) turns the first launched process into a resident daemon
#   and forwards later `flameshot gui` calls to it. That daemon keeps the screen
#   geometry from when it started, and xrdp changes the geometry whenever the
#   RDP client's monitor layout does (this session began at 5040x1920, it is
#   1920x1200 now). A stale daemon therefore presents the wrong region - the
#   "drifting field of view". So: kill any resident instance, start fresh.
# * flameshot's `full`/`screen` CLI modes go through the xdg screenshot portal,
#   whose GTK backend needs gnome-shell (dead here) -> 30 s timeout. Whole-screen
#   captures use ImageMagick on the X root window instead (clipboard via copyq).
# * Since flameshot 14 even `gui` goes through that portal by default (same 30 s
#   timeout, then "Unable to capture screen"). It only falls back to a native X11
#   grab with `useX11LegacyScreenshot=true` in
#   ~/.var/app/org.flameshot.Flameshot/config/flameshot/flameshot.ini.
mode="${1:-gui}"
case "$mode" in
  gui)
    flatpak kill org.flameshot.Flameshot 2>/dev/null || true
    for _ in $(seq 10); do
      flatpak ps --columns=application 2>/dev/null | grep -q '^org.flameshot.Flameshot$' || break
      sleep 0.2
    done
    exec flatpak run org.flameshot.Flameshot gui
    ;;
  full)
    out="$HOME/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png"
    import -window root "$out" && notify-send -i camera-photo "Screenshot saved" "$out"
    ;;
  clip)
    import -window root png:- | copyq copy image/png - \
      && notify-send -i camera-photo "Screenshot" "copied to clipboard"
    ;;
  *) echo "usage: $0 [gui|full|clip]" >&2; exit 2 ;;
esac
