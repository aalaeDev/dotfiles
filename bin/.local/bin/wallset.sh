#!/bin/bash

#pkill -x rofi && exit

WALL_DIR="$HOME/Pictures/Wallpapers/Desktop"

CWD="$(pwd)"

cd "$WALL_DIR" || exit 1

IFS=$'\n'

SELECTED_WALL=$(for a in *.jpg; do echo -en "$a\0icon\x1f$a\n" ; done | rofi -dmenu -theme "~/.config/rofi/wallpaper_switcher.rasi")

if [ -n "$SELECTED_WALL" ]; then
	echo $SELECTED_WALL
	matugen image $WALL_DIR/$SELECTED_WALL --source-color-index 1
	EXTENSION="${SELECTED_WALL##*.}"
	cp "$WALL_DIR/$SELECTED_WALL" "$HOME/dotfiles/hypr/.config/hypr/assets/current-wallpaper.$EXTENSION"
	notify-send "Theme & Wallpaper Updated" "Your theme and wallpaper have been successfully changed into."
fi
