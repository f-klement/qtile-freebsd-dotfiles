#!/usr/bin/env bash
# Rosé Pine screen lock via i3lock-color (a themeable superset of i3lock).
# Picks a random wallpaper, blurs it, and draws the unlock ring in the palette.
# Colour args are RRGGBBAA hex (no leading '#').
IMG="$(find ~/Pictures/wallpapers -type f \( -iname '*.jpg' -o -iname '*.png' \) | shuf -n1)"

# Rosé Pine palette
base=191724; surface=1f1d2e; text=e0def4; muted=6e6a86
iris=c4a7e7; foam=9ccfd8; gold=f6c177; love=eb6f92

if [[ -n "$IMG" ]]; then
  bg=(--image="$IMG" --blur=6)
else
  bg=(--color="$base")
fi

exec i3lock \
  "${bg[@]}" \
  --nofork --ignore-empty-password --show-failed-attempts \
  --clock --indicator \
  --radius=120 --ring-width=8 \
  --inside-color="${surface}cc"     --ring-color="${iris}ff" \
  --insidever-color="${surface}cc"  --ringver-color="${foam}ff" \
  --insidewrong-color="${surface}cc" --ringwrong-color="${love}ff" \
  --line-uses-inside \
  --keyhl-color="${gold}ff" --bshl-color="${love}ff" \
  --separator-color="${base}00" \
  --verif-color="${foam}ff" --wrong-color="${love}ff" \
  --time-color="${text}ff" --date-color="${muted}ff" \
  --greeter-color="${text}ff" \
  --time-str="%H:%M" --date-str="%A, %d %B" \
  --verif-text="…" --wrong-text="✗" --noinput-text="" --lock-text="" --lockfailed-text="" \
  --time-font="JetBrainsMono Nerd Font" --date-font="JetBrainsMono Nerd Font" \
  --verif-font="JetBrainsMono Nerd Font" --wrong-font="JetBrainsMono Nerd Font"
