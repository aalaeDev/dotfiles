#!/usr/bin/env bash

# Inserts text into the focused window and leaves the clipboard as it was.
#
#   clipboard-insert.sh <text>

# The one format worth keeping from the clipboard: text, else an image, never an app's private type
clipboard_type() {
    local types
    types=$(wl-paste --list-types 2> /dev/null)
    grep -m1 -Fx 'text/plain;charset=utf-8' <<< "$types" \
        || grep -m1 -Fx 'text/plain' <<< "$types" \
        || grep -m1 '^image/' <<< "$types"
}

# Pastes rather than types: wtype's fake keyboard garbles emoji in Chromium and Electron apps. Shift+Insert
# works in every toolkit, and terminals read it from primary.
saved=$(mktemp)
type=$(clipboard_type)
[[ -n "$type" ]] && wl-paste --no-newline --type "$type" > "$saved"

# Marked sensitive so clipboard managers leave the text out of their history
printf '%s' "$1" | wl-copy --sensitive
printf '%s' "$1" | wl-copy --primary --sensitive
sleep 0.15
hyprctl dispatch 'hl.dsp.send_shortcut({ mods = "SHIFT", key = "Insert" })' > /dev/null

# Slow apps read the paste late
sleep 0.4
if [[ -s "$saved" ]]; then
    wl-copy --type "$type" < "$saved"
else
    wl-copy --clear
fi
rm -f "$saved"
