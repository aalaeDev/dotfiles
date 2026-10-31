#!/usr/bin/env bash

# Open a rofi menu from a shortcut: the same shortcut closes it, another menu's shortcut switches to that one.
#
#   toggle.sh <name> <command...>

STATE="${XDG_RUNTIME_DIR:-/tmp}/rofi-menu"
name="$1"
shift

if pgrep -x rofi > /dev/null; then
    previous=$(cat "$STATE" 2> /dev/null)
    pkill -x rofi
    [[ "$previous" == "$name" ]] && exit 0
    # Only one rofi can run at a time: wait for this one to go
    for _ in {1..50}; do
        pgrep -x rofi > /dev/null || break
        sleep 0.02
    done
fi

echo "$name" > "$STATE"
exec "$@"
