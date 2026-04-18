#!/bin/bash

# Find the device ID between the single quotes
DEVICE=$(brightnessctl --list | grep "scrolllock" | head -n1 | awk -F "'" '{print $2}')

# Check if we actually found a device
if [ -z "$DEVICE" ]; then
    echo "No scrolllock device found. Is the keyboard plugged in?"
    exit 1
fi

# Get current brightness (usually 0 or 1)
CURRENT=$(brightnessctl --device="$DEVICE" get)

# Toggle logic: if 0, set to 1. Otherwise, set to 0.
if [ "$CURRENT" -eq 0 ]; then
    brightnessctl --device="$DEVICE" set 1
else
    brightnessctl --device="$DEVICE" set 0
fi
