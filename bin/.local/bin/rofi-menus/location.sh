#!/usr/bin/env bash

# Rofi location menu: pick a country and city for athan and weather, saved to .env.
# Launched from the notification center's settings button.

# --- Configuration ---
BIN="$(dirname "$(dirname "$(readlink -f "$0")")")"
# shellcheck source=/dev/null
source "$BIN/rice-env.sh"
COUNTRIES="/usr/share/iso-codes/json/iso_3166-1.json"
EXAMPLE="$(dirname "$RICE_ENV")/.env.example"
APP_NAME="Location"                 # Notification app name
ICON="preferences-system"           # Notification icon
WAYBAR_SIGNAL=11                    # custom/today in waybar's modules.jsonc
# Only the place being typed goes out, to the same service weather.sh already uses
GEOCODER="https://geocoding-api.open-meteo.com/v1/search"

# --- Helpers ---
notify() {
    notify-send -a "$APP_NAME" -i "$ICON" -u "$1" "$2" "$3"
}

pick_country() {
    local rows index
    rows=$(jq -r '."3166-1"[] | "\(.common_name // .name)\t\(.alpha_2)"' "$COUNTRIES" | sort) || return 1
    index=$(cut -f1 <<< "$rows" | rofi -dmenu -i -p "Country" -format i \
        -mesg "Now: ${CITY:-not set}${COUNTRY:+, $COUNTRY}") || return 1
    [[ -n "$index" ]] || return 1
    country_name=$(sed -n "$((index + 1))p" <<< "$rows" | cut -f1)
    country_code=$(sed -n "$((index + 1))p" <<< "$rows" | cut -f2)
}

ask_city() {
    rofi -dmenu -p "City" -mesg "$1" -l 0 \
        -theme-str 'entry { placeholder: "Type a city and press Enter"; } counter { enabled: false; }' < /dev/null
}

# One entry per name, the top result: fetch_place in weather.sh gets the same one back from just the name
search_city() {
    curl -fsS -m 8 --get "$GEOCODER" --data-urlencode "name=$1" -d "countryCode=$country_code" \
        -d count=100 -d format=json 2> /dev/null \
        | jq -ce 'reduce (.results // [])[] as $r ([];
            if any(.[]; .name == $r.name) then . else . + [$r] end)'
}

pick_city() {
    local message="In $country_name" query results index
    while true; do
        query=$(ask_city "$message") || return 1
        [[ -n "$query" ]] || continue
        if ! results=$(search_city "$query"); then
            notify "critical" "$APP_NAME" "Could not search for cities. Is the network up?"
            return 1
        fi
        if [[ "$results" == "[]" ]]; then
            message="No results for \"$query\" in $country_name"
            continue
        fi
        index=$(jq -r '.[] | [.name, .admin1 // empty] | join(", ")' <<< "$results" \
            | rofi -dmenu -i -p "City" -format i -mesg "In $country_name") || return 1
        [[ -n "$index" ]] || return 1
        city=$(jq -r ".[$index].name" <<< "$results")
        country=$(jq -r --arg fallback "$country_name" ".[$index].country // \$fallback" <<< "$results")
        return 0
    done
}

# Replaces one setting's value, leaving its comment and the rest of the file alone
set_var() {
    local key="$1" value="$2" line found=0 tmp="$RICE_ENV.tmp" pattern
    # .env is sourced by bash, so nothing in a value may be left for it to expand
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//\$/\\\$}
    value=${value//\`/\\\`}
    pattern="^$key=(\"([^\"\\\\]|\\\\.)*\"|'[^']*'|[^[:space:]#]*)(.*)\$"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $pattern ]]; then
            printf '%s="%s"%s\n' "$key" "$value" "${BASH_REMATCH[3]}"
            found=1
        else
            printf '%s\n' "$line"
        fi
    done < "$RICE_ENV" > "$tmp"
    (( found )) || printf '%s="%s"\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$RICE_ENV"
}

# --- Actions ---
pick_country || exit 0
pick_city || exit 0

[[ -e "$RICE_ENV" ]] || cp "$EXAMPLE" "$RICE_ENV"
set_var CITY "$city"
set_var COUNTRY "$country"

# Show the new place now rather than on the next tick. Anchored so nothing else that mentions the name is hit.
pkill -USR1 -f '^(/usr/bin/env )?(/[^ ]*/)?bash [^ ]*/nc-daemon\.sh$'
pkill -RTMIN+"$WAYBAR_SIGNAL" -x waybar
notify "normal" "$APP_NAME" "Athan and weather now use $city, $country"
