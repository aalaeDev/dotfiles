#!/bin/sh
# Starts Steam, first restoring the skin if a client update wiped its patched library.css
css="$HOME/.steam/steam/steamui/css/library.css"
head -c 40 "$css" 2> /dev/null | grep -q 'Adwaita-for-Steam' || "$HOME/.local/bin/steam-theme.sh"
exec /usr/bin/steam "$@"
