#!/bin/bash

#pkill -x rofi && exit

# Enable extended globbing to match multiple file extensions
shopt -s extglob

WALL_DIR="$HOME/Pictures/Wallpapers/Desktop"

CWD="$(pwd)"

# An image passed as an argument (Nemo's "Set as Wallpaper") skips the picker
if [ -n "$1" ]; then
    SELECTED_WALL=$(realpath "$1")
else
    cd "$WALL_DIR" || exit 1

    IFS=$'\n'

    # Match jpg, jpeg, and png (case-insensitive if needed, but standard lowercase here)
    SELECTED_WALL=$(for a in *.@(jpg|jpeg|png); do echo -en "$a\0icon\x1f$a\n" ; done | rofi -dmenu -theme "~/.config/rofi/wallpaper_switcher.rasi")
    [ -n "$SELECTED_WALL" ] && SELECTED_WALL="$WALL_DIR/$SELECTED_WALL"
fi

if [ -n "$SELECTED_WALL" ]; then
    echo "$SELECTED_WALL"
    matugen image "$SELECTED_WALL" --source-color-index 1
    convert "$SELECTED_WALL" "$HOME/dotfiles/hypr/.config/hypr/assets/current-wallpaper.jpg"
    notify-send "Theme & Wallpaper Updated" "Your theme and wallpaper have been successfully changed."
fi
