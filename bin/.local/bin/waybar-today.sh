#!/usr/bin/env bash

# Waybar custom/today module: weather beside the clock, prayer times and forecast on hover.

# --- Configuration ---
BIN="$(dirname "$(readlink -f "$0")")"

# --- Actions ---
athan=$("$BIN/athan.sh" waybar)
weather=$("$BIN/weather.sh" waybar)
jq -cn --argjson athan "${athan:-{\}}" --argjson weather "${weather:-{\}}" '
    {text: ([$athan.text, $weather.text] | map(select(. != null and . != "")) | join("  ")),
     tooltip: ("<tt>" + ([$athan.tooltip, $weather.tooltip] | map(select(. != null)) | join("\n\n")) + "</tt>"),
     class: ($athan.class // "")}'
