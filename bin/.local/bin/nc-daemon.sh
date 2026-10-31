#!/usr/bin/env bash

# Once a minute: send the athan notification when one is due, and refresh the notification center cards.
# swaync has no live widgets, so the card is label text merged into the generated config.json,
# and the bar's fill is a generated stylesheet.

# --- Configuration ---
BIN="$(dirname "$(readlink -f "$0")")"
# shellcheck source=/dev/null
source "$BIN/rice-env.sh"
SWAYNC="$HOME/.config/swaync"
CARD_WIDTH=50  # Characters that fit one line of the weather card
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

# Prints the config with the cards placed above the others. swaync gives one font size per widget, so
# anything sized differently is its own widget: a menubar's left and right slots hold the clock and dates.
# Menus are the only part of swaync that expands on click, so prayers and weather details are their rows.
render_config() {
    local athan weather
    athan=$("$BIN/athan.sh" json)
    weather=$("$BIN/weather.sh" json)
    jq --argjson athan "${athan:-null}" --argjson weather "${weather:-null}" --arg clock "$(date +%H:%M)" \
        --arg date "$(date '+%A, %-d %B')" --argjson width "$CARD_WIDTH" '
        def row($left; $right): $left + (" " * ([$width - ($left | length) - ($right | length), 1] | max)) + $right;
        def pad($size): . + (" " * ([$size - length, 0] | max));
        def or_dash: if . == "" or . == null then "–" else . end;
        def info($text): {label: $text, command: ""};
        def align_right: (map(length) | max) as $size | map(" " * ($size - length) + .) | join("\n");
        ([if $athan then "menubar#today-head", "label#athan-bar", "menubar#athan-state" else empty end,
            if $weather then "menubar#weather" else empty end]) as $cards
        | .widgets = $cards + .widgets
        | if $athan then
            .["widget-config"] += {
                "menubar#today-head": {
                    "buttons#clock": {position: "left", actions: [info($clock)]},
                    "buttons#dates": {position: "right",
                        actions: [info([$date, $athan.hijri, "󰺾 \($athan.city)"] | align_right)]}},
                "label#athan-bar": {text: "", "max-lines": 1},
                "menubar#athan-state": {"menu#state": {
                    label: "\($athan.state) 󰅀",
                    position: "left",
                    actions: [$athan.times[] | info(row("\(.icon)  \(.name)"; .time))]}}}
          else . end
        | if $weather then
            .["widget-config"]["menubar#weather"] = {
                "menu#weather": {
                    label: "\($weather.city) 󰅀\n\($weather.desc)",
                    position: "left",
                    actions: [
                        info(row("Wind"; $weather.wind | or_dash)),
                        info(row("Visibility"; $weather.visibility | or_dash)),
                        info(row("Air quality"; $weather.aqi | or_dash)),
                        info(row("Humidity"; "\($weather.humidity)%")),
                        ($weather.days[] | info(row("\(.icon)  \(.day | pad(11))\(.desc)"; "\(.low)° / \(.high)°")))]},
                "buttons#temp": {position: "right", actions: [info("\($weather.icon) \($weather.temp)°")]}}
          else . end' "$SWAYNC/config.base.json"
}

# A style reload leaves the widgets alone, so unlike the text this also runs with the panel open
refresh_bar() {
    local mode at name percent row color=primary new=""
    read -r mode at name < <("$BIN/athan.sh" status)
    if [[ -n "$mode" ]]; then
        percent=$("$BIN/athan.sh" percent)
        [[ "$mode" == late ]] && color=tertiary
        # The menu's rows: Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha
        case "$name" in Fajr) row=1 ;; Dhuhr) row=3 ;; Asr) row=4 ;; Maghrib) row=5 ;; Isha) row=6 ;; esac
        new=".widget-label.athan-bar > label { background-image: linear-gradient(to right, @$color $percent%, @outline_variant $percent%); }"
        new+=$'\n'".widget-menubar.athan-state > revealer button:nth-child($row) label { color: @$color; font-weight: 700; }"
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
