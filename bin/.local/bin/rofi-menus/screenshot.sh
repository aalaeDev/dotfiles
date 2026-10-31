#!/usr/bin/env bash

# Screenshot menu: a row of capture tiles, launched from Super+Print. History opens the Walker menu.

# --- Configuration ---
SHOT="$HOME/.local/bin/screenshot.sh"
THEME="$HOME/.config/rofi/screenshot.rasi"

# --- Helpers ---
tile() {
    printf "<span size='xx-large'>%s</span>\n<span size='small'>%s</span>|" "$1" "$2"
}

tiles() {
    rofi -dmenu -i -markup-rows -format i -p "Capture" -sep '|' -eh 3 -theme "$THEME"
}

capture_menu() {
    local gif_label="GIF" index actions=(region output window pretty text gif history)
    pgrep -x wf-recorder > /dev/null && gif_label="Stop GIF"

    index=$( {
        tile "󰩭" "Region"
        tile "󰍹" "Screen"
        tile "󰖲" "Window"
        tile "󰋩" "Pretty"
        tile "󰊄" "Text"
        tile "󰵸" "$gif_label"
        tile "󰋚" "History"
    } | tiles)
    [[ -n "$index" ]] || return 0

    [[ "${actions[index]}" == "history" ]] && exec walker -m menus:screenshots
    # Let the menu fade out, or it shows up in the capture
    sleep 0.25
    "$SHOT" "${actions[index]}"
}

# --- Main ---
capture_menu
