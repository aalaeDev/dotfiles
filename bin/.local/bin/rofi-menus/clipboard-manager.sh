#!/bin/bash

session_type=$XDG_SESSION_TYPE

# Nothing is decoded or copied on Esc: an empty pipe would wipe the clipboard
choice=$(cliphist list | rofi -dmenu -i -p "󰅍  Clipboard" -display-columns 2 -mesg "$(cliphist list | wc -l) entries") || exit 0

if [ "$session_type" == "wayland" ]; then
    cliphist decode <<< "$choice" | wl-copy

elif [ "$session_type" == "x11" ]; then
    cliphist decode <<< "$choice" | xclip -selection clipboard
else
    echo "Unsupported session type: $session_type"
fi
