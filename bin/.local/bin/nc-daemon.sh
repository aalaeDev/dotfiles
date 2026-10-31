#!/usr/bin/env bash

# Once a minute: send the athan notification when one is due, and refresh the notification center card.
# swaync has no live widgets, so the card is label text merged into the generated config.json,
# and the bar's fill is a generated stylesheet.

# --- Configuration ---
BIN="$(dirname "$(readlink -f "$0")")"
# shellcheck source=/dev/null
source "$BIN/rice-env.sh"
SWAYNC="$HOME/.config/swaync"
STAMP="$RICE_CACHE/athan-notified"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/nc-daemon.lock"

# --- Helpers ---
# Once per athan, also across restarts. Only ever in the late window, so a long suspend stays quiet.
notify_athan() {
    local mode at name late
    read -r mode at name < <("$BIN/athan.sh" status)
    [[ "$mode" == late && "$at" != "$(cat "$STAMP" 2> /dev/null)" ]] || return 0
    echo "$at" > "$STAMP"
    late=$(( ($(date +%s) - at) / 60 ))
    if (( late > 0 )); then
        notify-send -a Athan -i rice-athan "$name" "Started ${late}m ago, at $(date -d "@$at" +%H:%M)"
    else
        notify-send -a Athan -i rice-athan "It's time for $name" "$(date -d "@$at" +%H:%M)"
    fi
}

# Reloading while the panel is open would reset its sliders. The next minute catches up.
panel_open() {
    timeout 1 swaync-client -swb 2> /dev/null | head -n 1 | grep -q cc-open
}

# Prints the config with the card's widgets placed above the others
render_config() {
    local athan
    athan=$("$BIN/athan.sh" card)
    jq --arg state "${athan%%$'\n'*}" --arg times "${athan#*$'\n'}" \
        --arg weather "$("$BIN/weather.sh" card)" '
        ([if $state != "" then "label#athan", "label#athan-bar", "label#athan-times" else empty end,
          if $weather != "" then "label#weather" else empty end]) as $card
        | .widgets = $card + .widgets
        | .["widget-config"]["label#athan"] = {text: $state, "max-lines": 1}
        | .["widget-config"]["label#athan-bar"] = {text: "", "max-lines": 1}
        | .["widget-config"]["label#athan-times"] = {text: $times, "max-lines": 2}
        | .["widget-config"]["label#weather"] = {text: $weather, "max-lines": 1}' "$SWAYNC/config.base.json"
}

# A style reload leaves the widgets alone, so unlike the text this also runs with the panel open
refresh_bar() {
    local mode at name percent color=primary new=""
    read -r mode at name < <("$BIN/athan.sh" status)
    if [[ -n "$mode" ]]; then
        percent=$("$BIN/athan.sh" percent)
        [[ "$mode" == late ]] && color=tertiary
        new=".widget-label.athan-bar > label { background-image: linear-gradient(to right, @$color $percent%, @outline_variant $percent%); }"
    fi
    [[ "$new" == "$(cat "$SWAYNC/athan-bar.css" 2> /dev/null)" ]] && return 0
    printf '%s\n' "$new" > "$SWAYNC/athan-bar.css"
    swaync-client -sw -rs > /dev/null
}

refresh_card() {
    local new
    new=$(render_config) || return 0
    [[ "$new" == "$(cat "$SWAYNC/config.json" 2> /dev/null)" ]] && return 0
    panel_open && return 0
    # Write through a temp file so swaync never reads half a config
    printf '%s\n' "$new" > "$SWAYNC/.config.json.tmp"
    mv "$SWAYNC/.config.json.tmp" "$SWAYNC/config.json"
    swaync-client -sw -R > /dev/null
}

# --- Actions ---
exec 9> "$LOCK"
flock -n 9 || exit 0

while true; do
    notify_athan
    refresh_bar
    refresh_card
    # 9>&-: the sleep mustn't inherit the lock, or a restart would find it taken
    sleep $(( 60 - $(date +%s) % 60 )) 9>&-
done
