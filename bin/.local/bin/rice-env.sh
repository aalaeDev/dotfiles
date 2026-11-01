#!/usr/bin/env bash

# Sourced by scripts that need personal settings: loads the gitignored ~/dotfiles/.env.

# --- Configuration ---
RICE_ENV="${RICE_ENV:-$HOME/dotfiles/.env}"
RICE_CACHE="${RICE_CACHE:-$HOME/.cache/rice}"

# --- Actions ---
CITY="" COUNTRY="" ATHAN_METHOD=3 ATHAN_LATE_MINUTES=30 WEATHER_UNITS=celsius SOUND_VOLUME=1
# shellcheck source=/dev/null
[[ -r "$RICE_ENV" ]] && source "$RICE_ENV"
mkdir -p "$RICE_CACHE"

# Lines up tab-separated columns in a Waybar tooltip: must match "tooltip label" in waybar/style.css
pad_tooltip() {
    "$(dirname "$(readlink -f "$0")")/pad-columns.py" --font "SF Pro Text" --size 12 --weight 500 "$@"
}
