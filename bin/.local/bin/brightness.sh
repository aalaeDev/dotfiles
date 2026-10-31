#!/usr/bin/env bash

# Change the screen brightness, without going so dark that the screen looks switched off.
#
#   brightness.sh up|down

# --- Configuration ---
STEP=5     # % per press
MIN_PCT=5
LOCK="${XDG_RUNTIME_DIR:-/tmp}/osd.lock"

# --- Actions ---
minimum=$(( $(brightnessctl m) * MIN_PCT / 100 ))
case "$1" in
    up)   brightnessctl -q -n"$minimum" s "+$STEP%" ;;
    down) brightnessctl -q -n"$minimum" s "$STEP%-" ;;
    *)
        echo "Usage: $0 up|down" >&2
        exit 1
        ;;
esac

# At either end the level doesn't change, so the popup has to be told
read -r osd 2> /dev/null < "$LOCK" && kill -USR2 "$osd" 2> /dev/null
