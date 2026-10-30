#!/bin/bash

# 1. Get the current status (Playing, Paused, Stopped, or empty)
status=$(playerctl status 2>/dev/null)

# 2. Exit cleanly if nothing is running so your status bar hides the module
if [[ -z "$status" || "$status" == "Stopped" ]]; then
    echo ""
    exit 0
fi

# 3. Identify the player to assign the correct icon
player=$(playerctl metadata --format '{{playerName}}' 2>/dev/null)

case "$player" in
    spotify)      icon="" ;;    # Spotify
    firefox)      icon="󰈹" ;;    # Firefox
    chromium|chrome) icon="" ;; # Chrome
    vlc)          icon="󰕼" ;;    # VLC
    *)            icon="" ;;    # Generic music icon for anything else
esac

# 4. Add a pause indicator if the music isn't actively playing
if [[ "$status" == "Paused" ]]; then
    icon=" $icon"
fi

# 5. Fetch title and artist, capping length to prevent UI stretching
title=$(playerctl metadata --format '{{title}}' 2>/dev/null | cut -c 1-40)
artist=$(playerctl metadata --format '{{artist}}' 2>/dev/null | cut -c 1-30)

# Hyprlock renders this as Pango markup, where a bare & blanks the whole label
title=${title//&/&amp;}
artist=${artist//&/&amp;}

# 6. Format the final output
if [[ -n "$artist" ]]; then
    echo "$icon  $title - $artist"
else
    echo "$icon  $title"
fi
