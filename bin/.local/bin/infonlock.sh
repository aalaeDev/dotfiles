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

# Output the battery percentage and icon
echo "$battery_percentage% $battery_icon"
