#!/usr/bin/env bash

# Once a minute: send the athan notification when one is due, and refresh the notification center cards.
# swaync has no live widgets, so the card is label text merged into the generated config.json,
# and the bar's fill is a generated stylesheet.

# --- Configuration ---
BIN="$(dirname "$(readlink -f "$0")")"
# shellcheck source=/dev/null
source "$BIN/rice-env.sh"
SWAYNC="$HOME/.config/swaync"
# Rows are one label each, so pad-columns.py lines them up: these must match the card rows in style.css
ROW_FONT="SF Pro Text"
ROW_SIZE=12
ROW_WEIGHT=500
ROW_WIDTH=365  # Pixels that fit one line of a card: the width of its bar
STAMP="$RICE_CACHE/athan-notified"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/nc-daemon.lock"
CLAUDE_TICK=5  # Seconds between Claude Code and media updates while one is active

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
    local athan weather claude
    athan=$("$BIN/athan.sh" json)
    weather=$("$BIN/weather.sh" json)
    claude=$("$BIN/claude-widget.sh" --nc)
    jq --argjson athan "${athan:-null}" --argjson weather "${weather:-null}" --argjson claude "${claude:-[]}" \
        --argjson streams "${STREAMS:-[]}" --arg clock "$(date +%H:%M)" --arg date "$(date '+%A, %-d %B')" '
        def row($left; $right): "\($left)\t\($right)";
        def or_dash: if . == "" or . == null then "–" else . end;
        def info($text): {label: $text, command: ""};
        def align_right: map("\t\(.)") | join("\n");
        ([if $athan then "menubar#today-head", "label#athan-bar", "menubar#athan-state" else empty end,
            if $weather then "menubar#weather" else empty end]) as $cards
        # Glance, then controls, then what is going on: sessions sit with the notifications
        | .widgets = $cards + (.widgets | map(if . == "title"
            then ($claude[] | "menubar#\(.slug)", "label#\(.slug)-bar"), . else . end))
        # The size button for the card lives here. One stream is already what the player above shows.
        | .widgets |= map(if . == "mpris" then ., "menubar#playing" else . end)
        | .["widget-config"]["menubar#playing"] = ({"buttons#size": {position: "right",
                actions: [{label: "󰘖", command: "~/.local/bin/nc-media.py toggle"}]}}
            + if ($streams | length) > 1 then {"menu#streams": {
                label: "Playing · \($streams | length) 󰅀",
                position: "left",
                actions: [$streams[] | {
                    label: row(.title | if length > 40 then .[:39] + "…" else . end; if .muted then "󰖁" else "󰕾" end),
                    command: (.ids | map("wpctl set-mute \(.) toggle") | join("; "))}]}} else {} end)
        | reduce $claude[] as $session (.;
            def word: {running: "Working", waiting: "Needs you", done: "Done"}[.];
            def glyph: {running: "✻", waiting: "✻", done: "󰄬"}[.];
            def clip($size): if length > $size then .[:$size - 1] + "…" else . end;
            def detail:
                if .state == "done" then "Finished in \(if .elapsed >= 60 then "\(.elapsed / 60 | floor)m \(.elapsed % 60)s" else "\(.elapsed)s" end)"
                elif .state == "waiting" then "Waiting for permission"
                elif (.total // 0) > 0 then ["\(.done // 0)/\(.total)", .note // empty] | join(" · ")
                else "Estimated from past turns" end;
            .["widget-config"] += {
                "menubar#\($session.slug)": {
                    "buttons#name": {position: "left",
                        actions: [info("\($session.name | clip(34))\n\([$session.project, ($session | detail)] | join(" · ") | clip(38))")]},
                    "buttons#status": {position: "right",
                        actions: [info("\($session.state | glyph)  \($session.state | word)")]}},
                "label#\($session.slug)-bar": {text: "", "max-lines": 1}})
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
                    actions: [$athan.times[] | info(row("\(.icon)  \(.name)"; .time))]},
                    # Colored and sized by privacy-dots.py. The row is here anyway, so a dot moves nothing.
                    "buttons#privacy": {position: "right",
                        actions: [info("●  Mic"), info("●  Camera"), info("●  Screen"), info("●  Location")]}}}
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
                        ($weather.days[] | info(row("\(.icon)  \(.day)\t\(.desc)"; "\(.low)° / \(.high)°")))]},
                "buttons#temp": {position: "right", actions: [info("\($weather.icon) \($weather.temp)°")]}}
          else . end' "$SWAYNC/config.base.json" \
        | "$BIN/pad-columns.py" --json --fractional --font "$ROW_FONT" --size "$ROW_SIZE" --weight "$ROW_WEIGHT" --width "$ROW_WIDTH"
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
        # Color only: another weight changes the text's width and undoes the row's padding
        new+=$'\n'".widget-menubar.athan-state > revealer button:nth-child($row) label { color: @$color; }"
    fi
    [[ "$new" == "$(cat "$SWAYNC/athan-bar.css" 2> /dev/null)" ]] && return 0
    printf '%s\n' "$new" > "$SWAYNC/athan-bar.css"
    swaync-client -sw -rs > /dev/null
}

# One card per session, so its look is generated with its fill. Named after the session rather than its
# position: with the panel open the config can't reload, and a bar must not move to someone else's card.
claude_card_css() {
    local slug=$1 state=$2 percent=$3 color=primary
    case "$state" in waiting) color=tertiary ;; done) color=green ;; esac
    cat << EOF
.widget-menubar.$slug {
    background: transparent;
    color: @on_surface;
    border: 1px solid transparent;
    border-top-color: @hairline;
    border-bottom: none;
    border-radius: 0;
    margin: 4px 4px 0;
    padding: 0;
}
.widget-menubar.$slug > .menu-button-bar > .start,
.widget-menubar.$slug > .menu-button-bar > .end { margin: 0; }
.widget-menubar.$slug button,
.widget-menubar.$slug button:hover,
.widget-menubar.$slug button:active {
    background: transparent;
    color: @on_surface;
    border: none;
    box-shadow: none;
    font-size: 12px;
    font-weight: 500;
    padding: 8px 12px 4px;
    margin: 0;
    min-height: 0;
}
.widget-menubar.$slug > .menu-button-bar > .end button { color: @$color; font-weight: 600; }
.widget-label.$slug-bar {
    border: 1px solid transparent;
    border-top: none;
    border-radius: 0;
    margin: 0 4px 4px;
    padding: 2px 12px 12px;
}
.widget-label.$slug-bar > label {
    font-size: 1px;
    min-height: 3px;
    border-radius: 2px;
    background-image: linear-gradient(to right, @$color $percent%, @outline_variant $percent%);
EOF
    [[ "$state" == done ]] || echo "    animation: claude_breathe 1.6s ease-in-out infinite alternate;"
    echo "}"
}

# Sets CLAUDE_KEY to who's doing what, which is what the cards' text shows. The percent only moves the bars,
# so they can keep moving with the panel open.
refresh_claude_bar() {
    local sessions new="" slug state percent
    sessions=$("$BIN/claude-widget.sh" --nc)
    CLAUDE_KEY=$(jq -r 'map("\(.session) \(.state)") | join(" ")' <<< "${sessions:-[]}")
    while read -r slug state percent; do
        new+=$(claude_card_css "$slug" "$state" "$percent")$'\n'
    done < <(jq -r '.[] | "\(.slug) \(.state) \(.percent)"' <<< "${sessions:-[]}")
    # A session that's over keeps its card until the config can reload, so it keeps its look too
    while read -r slug; do
        new+=$(claude_card_css "$slug" done 100)$'\n'
    done < <(jq -r --argjson live "${sessions:-[]}" '.widgets[] | select(startswith("menubar#claude-")) | ltrimstr("menubar#")
        | select(IN($live[].slug) | not)' "$SWAYNC/config.json" 2> /dev/null)
    # -f: style.css imports it, so it has to exist even with nothing to show
    [[ -f "$SWAYNC/claude-bar.css" && "$new" == "$(cat "$SWAYNC/claude-bar.css")"$'\n' ]] && return 0
    printf '%s' "$new" > "$SWAYNC/claude-bar.css"
    swaync-client -sw -rs > /dev/null
}

# Sets STREAMS to the apps making sound right now, one per tab for a browser
refresh_streams() {
    STREAMS=$(pw-dump 2> /dev/null | jq -c '[.[]
        | select(.type == "PipeWire:Interface:Node")
        | select(.info.props["media.class"] == "Stream/Output/Audio" and .info.state == "running")
        | {id, muted: (.info.params.Props[0].mute // false),
            # Tabs name their stream after the page. Other apps use a word that says nothing.
            title: (.info.props["media.name"] as $name
                | if ($name // "" | test("^(playback|audiostream|audio stream|)$"; "i")) then .info.props["application.name"] // "Unknown" else $name end)}]
        | group_by(.title) | map({title: .[0].title, ids: map(.id), muted: all(.muted)})')
    [[ -n "$STREAMS" ]] || STREAMS="[]"
}

refresh_media_bar() {
    "$BIN/nc-media.py" refresh
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

# USR1 ends the wait early: the location menu changed the city, or a Claude Code session changed state
trap ':' USR1

while true; do
    notify_athan
    refresh_bar
    refresh_claude_bar
    refresh_media_bar
    refresh_streams
    refresh_card
    # Up to the next minute, in short naps while Claude Code or something audible is on so the bars stay live
    while true; do
        left=$(( 60 - $(date +%s) % 60 ))
        [[ -n "$CLAUDE_KEY" || "$STREAMS" != "[]" ]] && (( left > CLAUDE_TICK )) && left=$CLAUDE_TICK
        # 9>&-: the sleep mustn't inherit the lock, or a restart would find it taken
        sleep "$left" 9>&- &
        sleeper=$!
        wait "$sleeper"
        interrupted=$?
        kill "$sleeper" 2> /dev/null
        (( interrupted > 128 )) && break
        (( $(date +%s) % 60 < CLAUDE_TICK )) && break
        previous=$CLAUDE_KEY$STREAMS
        refresh_claude_bar
        refresh_media_bar
        refresh_streams
        [[ "$CLAUDE_KEY$STREAMS" == "$previous" ]] || refresh_card
    done
done
