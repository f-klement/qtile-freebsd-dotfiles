#!/usr/bin/env bash
# Screenshots for the qtile desktop on FreeBSD/X11.
#
#   screenshot.sh gui    - interactive region selector -> clipboard/save
#   screenshot.sh full   - whole screen -> ~/Pictures/screenshot-<ts>.png
#   screenshot.sh clip   - whole screen -> clipboard
#
# FreeBSD has no flatpak, so the old flatpak-flameshot daemon dance is gone.
# Instead we probe for whatever native X11 capture tool is installed and use
# it. Install one of these to enable screenshots:
#
#   pkg install flameshot      # best: interactive region select + annotate
#   pkg install scrot          # light, has -s region select
#   pkg install maim slop      # maim -s for region select
#   pkg install ImageMagick7   # provides `import` (region + root window)
#
# Clipboard uses xclip (installed); copyq is a fallback. notify-send comes
# from libnotify and is served by dunst.
set -u

mode="${1:-gui}"
outdir="$HOME/Pictures"
ts() { date +%Y%m%d-%H%M%S; }
have() { command -v "$1" >/dev/null 2>&1; }

notify() { have notify-send && notify-send -i camera-photo "$1" "${2:-}"; }

no_backend() {
    notify "Screenshot unavailable" \
        "No capture tool found. Install one: pkg install flameshot (or scrot / maim / ImageMagick7)."
    echo "screenshot.sh: no capture backend (flameshot/scrot/maim/import) installed" >&2
    exit 1
}

# Copy a PNG file on stdin's path ($1) to the clipboard.
to_clipboard() {
    if have xclip; then
        xclip -selection clipboard -t image/png -i "$1"
    elif have copyq; then
        copyq copy image/png - < "$1"
    else
        return 1
    fi
}

# Capture the whole screen to the PNG path in $1. Returns non-zero if no tool.
capture_full() {
    local out="$1"
    if   have scrot;  then scrot -o "$out"
    elif have maim;   then maim "$out"
    elif have import; then import -window root "$out"
    else return 2
    fi
}

# Interactive region capture to the PNG path in $1.
capture_region() {
    local out="$1"
    if   have scrot;  then scrot -s -o "$out"
    elif have maim;   then maim -s "$out"
    elif have import; then import "$out"
    else return 2
    fi
}

case "$mode" in
  gui)
    # flameshot has its own richer selector+annotate UI; prefer it outright.
    if have flameshot; then
        exec flameshot gui
    fi
    tmp="$(mktemp -t shot).png"
    trap 'rm -f "$tmp"' EXIT
    capture_region "$tmp" || no_backend
    [ -s "$tmp" ] || exit 0            # user cancelled the selection
    if to_clipboard "$tmp"; then
        notify "Screenshot" "region copied to clipboard"
    else
        mkdir -p "$outdir"; mv "$tmp" "$outdir/screenshot-$(ts).png"
        trap - EXIT
    fi
    ;;
  full)
    mkdir -p "$outdir"
    out="$outdir/screenshot-$(ts).png"
    capture_full "$out" || no_backend
    notify "Screenshot saved" "$out"
    ;;
  clip)
    tmp="$(mktemp -t shot).png"
    trap 'rm -f "$tmp"' EXIT
    capture_full "$tmp" || no_backend
    to_clipboard "$tmp" && notify "Screenshot" "copied to clipboard"
    ;;
  *) echo "usage: $0 [gui|full|clip]" >&2; exit 2 ;;
esac
