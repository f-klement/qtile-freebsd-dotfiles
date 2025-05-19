#!/usr/bin/env bash
# pick a random .jpg/.png from your lock folder
IMG="$(find ~/Pictures/wallpapers -type f \( -iname '*.jpg' -o -iname '*.png' \) | shuf -n1)"
# if none found, go black
if [[ -z "$IMG" ]]; then
  exec i3lock --color=000000 --nofork --show-failed-attempts --ignore-empty-password
else
  exec i3lock --image="$IMG" --nofork --show-failed-attempts --ignore-empty-password
fi
