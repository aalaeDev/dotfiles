#!/usr/bin/env bash

# Elephant's clipboard command: put the chosen entry (on stdin) on the clipboard, then paste it into the
# window that gets focus back. Shift+Insert works in every toolkit, and terminals read it from primary.

entry=$(mktemp)
trap 'rm -f "$entry"' EXIT
cat > "$entry"

wl-copy < "$entry" > /dev/null 2>&1
grep -qI . "$entry" && wl-copy --primary < "$entry" > /dev/null 2>&1

# Walker has to close first
sleep 0.25
hyprctl dispatch 'hl.dsp.send_shortcut({ mods = "SHIFT", key = "Insert" })' > /dev/null
