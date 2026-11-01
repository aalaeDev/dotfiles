#!/usr/bin/env bash

# Prayer times from Aladhan, cached by month so they keep working offline.
#   athan.sh waybar   Waybar custom module JSON
#   athan.sh percent  How far along the bar is, 0-100
#   athan.sh status   "mode epoch name" of the current state, for nc-daemon.sh
#   athan.sh json     Hijri date, place, state and today's times, for nc-daemon.sh
# After an athan it shows how late you are for ATHAN_LATE_MINUTES, then counts down to the next one.

# shellcheck source=/dev/null
source "$(dirname "$(readlink -f "$0")")/rice-env.sh"
[[ -n "$CITY" ]] || exit 0

# --- Configuration ---
PRAYERS=(Fajr Dhuhr Asr Maghrib Isha)
ICON=$'\U000F1827'         # Mosque
BAR_CELLS=20
RETRY_AFTER=300            # Seconds to wait after a failed download
NOW="${NOW:-$(date +%s)}"  # Overridable to test any moment

key=$(printf '%s|%s|%s' "$CITY" "$COUNTRY" "$ATHAN_METHOD" | md5sum | cut -c1-8)

# --- Helpers ---
month_file() {
    echo "$RICE_CACHE/athan-$key-$1.json"
}

# Download one month (YYYY-MM) unless it's cached or the last try just failed
fetch_month() {
    local file failed tmp
    file=$(month_file "$1")
    failed="$file.failed"
    [[ -s "$file" ]] && return 0
    [[ -e "$failed" ]] && (( NOW - $(stat -c %Y "$failed") < RETRY_AFTER )) && return 1

    tmp=$(mktemp "$file.XXXXXX")
    if curl -fsS -m 8 --get "https://api.aladhan.com/v1/calendarByCity/${1%-*}/$((10#${1#*-}))" \
        --data-urlencode "city=$CITY" --data-urlencode "country=$COUNTRY" \
        --data-urlencode "method=$ATHAN_METHOD" -o "$tmp" 2> /dev/null \
        && jq -e '.code == 200 and (.data | length > 0)' "$tmp" > /dev/null 2>&1; then
        mv "$tmp" "$file"
        rm -f "$failed"
    else
        rm -f "$tmp"
        touch "$failed"
        return 1
    fi
}

# Prints "name epoch" per prayer for a date (YYYY-MM-DD). Times look like "05:12 (+01)".
day_times() {
    local file name clock
    file=$(month_file "${1%-*}")
    [[ -s "$file" ]] || return 0
    while read -r name clock; do
        echo "$name $(date -d "$1 $clock" +%s)"
    done < <(jq -r --arg day "$(date -d "$1" +%d-%m-%Y)" '
        .data[] | select(.date.gregorian.date == $day) | .timings
        | ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"][] as $p | "\($p) \(.[$p] | split(" ")[0])"' "$file")
}

# Sets mode (late|countdown), name, at, percent, and for late: late_min
compute_state() {
    local today yesterday tomorrow n e last_name="" last_at=0
    today=$(date -d "@$NOW" +%F)
    yesterday=$(date -d "$today -1 day" +%F)
    tomorrow=$(date -d "$today +1 day" +%F)

    fetch_month "${today%-*}" || [[ -s $(month_file "${today%-*}") ]] || return 1
    fetch_month "${tomorrow%-*}"
    # Next month ahead of time, so a month end offline still works
    fetch_month "$(date -d "$(date -d "@$NOW" +%Y-%m-15) +1 month" +%Y-%m)"

    name=""
    while read -r n e; do
        if (( e <= NOW )); then
            last_name=$n last_at=$e
        elif [[ -z "$name" ]]; then
            name=$n at=$e
        fi
    done < <(day_times "$yesterday"; day_times "$today"; day_times "$tomorrow")

    if (( last_at && NOW - last_at < ATHAN_LATE_MINUTES * 60 )); then
        mode=late name=$last_name at=$last_at
        late_min=$(( (NOW - last_at) / 60 ))
        percent=$(( (NOW - last_at) * 100 / (ATHAN_LATE_MINUTES * 60) ))
    else
        [[ -n "$name" ]] || return 1
        mode=countdown
        percent=0
        (( last_at )) && percent=$(( (NOW - last_at) * 100 / (at - last_at) ))
    fi
}

bar() {
    local i out="" cells=$(( percent * BAR_CELLS / 100 ))
    for (( i = 0; i < BAR_CELLS; i++ )); do
        if (( i < cells )); then out+="▰"; else out+="▱"; fi
    done
    echo "$out"
}

# "1h 24m", rounded up so it never reads 0m before the athan
remaining() {
    local min=$(( (at - NOW + 59) / 60 ))
    if (( min >= 60 )); then echo "$(( min / 60 ))h $(( min % 60 ))m"; else echo "${min}m"; fi
}

clock_of() {
    date -d "@$1" +%H:%M
}

# --- Actions ---
# The pill only says something while you're late; the rest waits in the tooltip
print_waybar() {
    local text="" headline times n e
    if ! compute_state; then
        echo '{"text": ""}'
        return
    fi
    if [[ "$mode" == late ]]; then
        text="<span size='130%' rise='-1451'>$ICON</span> ${late_min}m"
        headline="$name, ${late_min}m late"
    else
        headline="$name in $(remaining)"
    fi
    # Columns line up with spaces, so they keep a monospaced font
    times=$(while read -r n e; do
        printf '%-8s %s\n' "$n" "$(clock_of "$e")"
    done < <(day_times "$(date -d "@$NOW" +%F)"))
    jq -cn --arg text "$text" --arg tooltip "$headline"$'\n'"$(bar)"$'\n\n'"<span font_family='JetBrainsMono NF'>$times</span>" --arg class "$mode" \
        '{text: $text, tooltip: $tooltip, class: $class}'
}

# Sunrise isn't a prayer, so it's only listed here and never part of the state
print_json() {
    local state
    compute_state || return 0
    if [[ "$mode" == late ]]; then state="$name, ${late_min}m late"; else state="$name in $(remaining)"; fi
    jq -c --arg day "$(date -d "@$NOW" +%d-%m-%Y)" --arg city "$CITY" --arg country "$COUNTRY" \
        --arg mode "$mode" --arg name "$name" --arg state "$state" '
        .data[] | select(.date.gregorian.date == $day)
        | .timings as $t | .date.hijri as $h
        | {city: $city, country: $country, mode: $mode, name: $name, state: $state,
           hijri: "\($h.day | tonumber) \($h.month.en) \($h.year) \($h.designation.abbreviated)",
           times: [{Fajr: "\uDB81\uDD9A", Sunrise: "\uDB81\uDD9C", Dhuhr: "\uDB81\uDD99",
                    Asr: "\uDB81\uDD95", Maghrib: "\uDB81\uDD9B", Isha: "\uDB81\uDD94"}
                   | to_entries[] | {name: .key, icon: .value, time: ($t[.key] | split(" ")[0])}]}' "$(month_file "$(date -d "@$NOW" +%Y-%m)")"
}

case "${1:-waybar}" in
    waybar)  print_waybar ;;
    json)    print_json ;;
    percent) compute_state && echo "$percent" ;;
    status)  compute_state && echo "$mode $at $name" ;;
esac
