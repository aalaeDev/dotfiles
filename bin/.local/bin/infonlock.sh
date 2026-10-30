#!/bin/bash

# Find the battery directory (Handles BAT0 or BAT1 depending on hardware)
BATTERY_DIR=$(ls -d /sys/class/power_supply/BAT* | head -n 1)

# Get the current battery percentage and status
battery_percentage=$(cat "$BATTERY_DIR/capacity")
battery_status=$(cat "$BATTERY_DIR/status")

# Define 11 battery icons for 0% to 100% (indices 0-10)
battery_icons=("󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹")

# Define the charging icon
charging_icon="󰂄"

# Calculate the index (0 to 10)
icon_index=$((battery_percentage / 10))

# Assign the corresponding icon
battery_icon=${battery_icons[icon_index]}

# Override with charging icon if plugged in
if [ "$battery_status" = "Charging" ]; then
    battery_icon="$charging_icon"
fi

# Statuses, each shown only when there is something to say
status=()

# Unread notifications
notifications=$(timeout 1 swaync-client -c 2> /dev/null)
[[ ${notifications:-0} -gt 0 ]] && status+=("$notifications "$'\U000F009A')

# Connected Bluetooth devices
bluetooth=$(timeout 1 bluetoothctl devices Connected 2> /dev/null | wc -l)
[[ $bluetooth -gt 0 ]] && status+=("$bluetooth "$'\U000F00B1')

# Volume
volume=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2> /dev/null)
if [[ $volume == *MUTED* ]]; then
    status+=($'\U000F0581')
elif [[ -n $volume ]]; then
    percent=$(awk '{ printf "%d", $2 * 100 }' <<< "$volume")
    status+=("$percent% "$'\U000F057E')
fi

# VPN, then Wi-Fi or ethernet
active=$(nmcli -t -f TYPE connection show --active 2> /dev/null)
grep -qE 'vpn|wireguard' <<< "$active" && status+=($'\U000F099D')
if grep -q 'wireless' <<< "$active"; then
    status+=($'\U000F0928')
elif grep -q 'ethernet' <<< "$active"; then
    status+=($'\U000F0200')
else
    status+=($'\U000F092D')
fi

# Output the statuses and the battery percentage and icon
for item in "${status[@]}"; do
    printf '%s   ' "$item"
done
echo "$battery_percentage% $battery_icon"
