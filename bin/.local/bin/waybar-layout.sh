#!/usr/bin/env bash

# Switch waybar between the detailed and the compact layout.
# config.jsonc includes ~/.cache/waybar/layout.jsonc, a copy of one of
# ~/.config/waybar/layouts/*.jsonc; waybar reloads it on SIGUSR2.
#
#   waybar-layout.sh [toggle|full|compact|init]
#   init: create the cache copy if missing (run before starting waybar)

set -euo pipefail

# --- Configuration ---
LAYOUTS="$HOME/.config/waybar/layouts"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
STATE="$CACHE/layout"

# --- Actions ---
mkdir -p "$CACHE"
current=$(cat "$STATE" 2> /dev/null || echo full)
action=${1:-toggle}

case "$action" in
    toggle) [[ $current == full ]] && layout=compact || layout=full ;;
    init) layout=$current ;;
    full | compact) layout=$action ;;
    *)
        echo "usage: ${0##*/} [toggle|full|compact|init]" >&2
        exit 1
        ;;
esac

cp "$LAYOUTS/$layout.jsonc" "$CACHE/layout.jsonc"
echo "$layout" > "$STATE"
[[ $action == init ]] || pkill -SIGUSR2 -x waybar || true
