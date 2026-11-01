#!/usr/bin/env bash

# Current weather from Open-Meteo, cached so it keeps showing the last value offline.
#   weather.sh waybar   Waybar custom module JSON
#   weather.sh json     Current details and forecast, for the notification center (nc-daemon.sh)
# The city name never reaches the bar, which shows up in screenshots. Only the notification center names it.

# shellcheck source=/dev/null
source "$(dirname "$(readlink -f "$0")")/rice-env.sh"
[[ -n "$CITY" ]] || exit 0

# --- Configuration ---
MAX_AGE=1800     # Seconds before the forecast is refreshed
RETRY_AFTER=300  # Seconds to wait after a failed download

key=$(printf '%s|%s|%s' "$CITY" "$COUNTRY" "$WEATHER_UNITS" | md5sum | cut -c1-8)
place="$RICE_CACHE/weather-$key-place.json"
forecast="$RICE_CACHE/weather-$key.json"
air="$RICE_CACHE/weather-$key-air.json"
failed="$forecast.failed"
wind_unit=kmh
[[ "$WEATHER_UNITS" == fahrenheit ]] && wind_unit=mph

# --- Helpers ---
age_of() {
    echo $(( $(date +%s) - $(stat -c %Y "$1") ))
}

# Coordinates only change with the city, so they're looked up once
fetch_place() {
    [[ -s "$place" ]] && return 0
    local tmp
    tmp=$(mktemp "$place.XXXXXX")
    if curl -fsS -m 8 --get https://geocoding-api.open-meteo.com/v1/search \
        --data-urlencode "name=$CITY" -d count=100 -d format=json 2> /dev/null \
        | jq -e --arg country "${COUNTRY,,}" '
            .results as $all
            | ([$all[] | select((.country // "" | ascii_downcase) == $country)] | first) // $all[0]
            | {latitude, longitude} | select(.latitude != null)' > "$tmp" 2> /dev/null; then
        mv "$tmp" "$place"
    else
        rm -f "$tmp"
        return 1
    fi
}

# Nice to have: when it fails the panel just shows a dash
fetch_air() {
    local tmp
    tmp=$(mktemp "$air.XXXXXX")
    if curl -fsS -m 8 --get https://air-quality-api.open-meteo.com/v1/air-quality \
        -d "latitude=$(jq -r .latitude "$place")" -d "longitude=$(jq -r .longitude "$place")" \
        -d current=us_aqi -o "$tmp" 2> /dev/null && jq -e .current "$tmp" > /dev/null 2>&1; then
        mv "$tmp" "$air"
    else
        rm -f "$tmp"
    fi
}

refresh() {
    [[ -s "$forecast" ]] && (( $(age_of "$forecast") < MAX_AGE )) && return 0
    [[ -e "$failed" ]] && (( $(age_of "$failed") < RETRY_AFTER )) && return 0
    local tmp
    tmp=$(mktemp "$forecast.XXXXXX")
    if fetch_place && curl -fsS -m 8 --get https://api.open-meteo.com/v1/forecast \
        -d "latitude=$(jq -r .latitude "$place")" -d "longitude=$(jq -r .longitude "$place")" \
        -d current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m,visibility \
        -d daily=weather_code,temperature_2m_max,temperature_2m_min \
        -d "temperature_unit=$WEATHER_UNITS" -d "wind_speed_unit=$wind_unit" -d timezone=auto -d forecast_days=3 \
        -o "$tmp" 2> /dev/null && jq -e .current "$tmp" > /dev/null 2>&1; then
        mv "$tmp" "$forecast"
        rm -f "$failed"
        fetch_air
    else
        rm -f "$tmp"
        touch "$failed"
    fi
}

# WMO weather code to "glyph|description"
describe() {
    local night=$(( $2 == 0 ))
    case "$1" in
        0)        (( night )) && echo $'\U000F0594|Clear' || echo $'\U000F0599|Clear' ;;
        1|2)      (( night )) && echo $'\U000F0F31|Partly cloudy' || echo $'\U000F0595|Partly cloudy' ;;
        3)        echo $'\U000F0590|Cloudy' ;;
        45|48)    echo $'\U000F0591|Fog' ;;
        51|53|55|56|57) echo $'\U000F0597|Drizzle' ;;
        61|63|80|81)    echo $'\U000F0597|Rain' ;;
        65|66|67|82)    echo $'\U000F0596|Heavy rain' ;;
        71|73|75|77|85|86) echo $'\U000F0598|Snow' ;;
        95|96|99) echo $'\U000F0593|Thunderstorm' ;;
        *)        echo $'\U000F0590|Unknown' ;;
    esac
}

# --- Actions ---
refresh
if [[ ! -s "$forecast" ]]; then
    [[ "${1:-waybar}" == waybar ]] && echo '{"text": ""}'
    exit 0
fi

read -r temp feels humidity code is_day < <(jq -r '.current |
    "\(.temperature_2m | round) \(.apparent_temperature | round) \(.relative_humidity_2m) \(.weather_code) \(.is_day)"' "$forecast")
IFS='|' read -r icon desc <<< "$(describe "$code" "$is_day")"

case "${1:-waybar}" in
    waybar)
        tooltip="$desc, feels like $feels°, humidity $humidity%"
        while read -r day high low day_code; do
            IFS='|' read -r _ day_desc <<< "$(describe "$day_code" 1)"
            tooltip+=$'\n'"$(printf '%s\t%s°\t%s°\t%s' "$(date -d "$day" +%a)" "$high" "$low" "$day_desc")"
        done < <(jq -r '.daily | range(0; .time | length) as $i
            | "\(.time[$i]) \(.temperature_2m_max[$i] | round) \(.temperature_2m_min[$i] | round) \(.weather_code[$i])"' "$forecast")
        jq -cn --arg text "$temp° <span size='130%' rise='-1451'>$icon</span>" --arg tooltip "$(pad_tooltip --align lrrl <<< "$tooltip")" \
            '{text: $text, tooltip: $tooltip}'
        ;;
    json)
        days=$(while read -r day high low day_code; do
            IFS='|' read -r day_icon day_desc <<< "$(describe "$day_code" 1)"
            jq -cn --arg day "$(date -d "$day" +%A)" --arg high "$high" --arg low "$low" \
                --arg icon "$day_icon" --arg desc "$day_desc" '$ARGS.named'
        done < <(jq -r '.daily | range(1; .time | length) as $i
            | "\(.time[$i]) \(.temperature_2m_max[$i] | round) \(.temperature_2m_min[$i] | round) \(.weather_code[$i])"' "$forecast") | jq -cs .)
        jq -c --arg city "$CITY" --arg icon "$icon" --arg desc "$desc" --arg temp "$temp" \
            --arg humidity "$humidity" --arg wind_unit "${wind_unit/kmh/km/h}" --arg units "$WEATHER_UNITS" \
            --arg aqi "$(jq -r '.current.us_aqi // empty' "$air" 2> /dev/null)" --argjson days "$days" '
            .current as $c
            | {city: $city, icon: $icon, desc: $desc, temp: $temp, humidity: $humidity, aqi: $aqi, days: $days,
               wind: (if $c.wind_speed_10m == null then "" else "\($c.wind_speed_10m | round) \($wind_unit)" end),
               visibility: (if $c.visibility == null then ""
                   elif $units == "fahrenheit" then "\(($c.visibility / 160.934 | round) / 10) mi"
                   else "\(($c.visibility / 100 | round) / 10) km" end)}' "$forecast"
        ;;
esac
