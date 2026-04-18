#!/bin/env bash

# Options
lock="󰌾  Lock"
logout="󰍃  Logout"
suspend="󰒲  Suspend"
reboot="󰜉  Reboot"
shutdown="  Shutdown"

# Updated Rofi Command
# Added -theme flag to use the custom layout
choice=$(printf "%s\n%s\n%s\n%s\n%s" "$lock" "$logout" "$suspend" "$reboot" "$shutdown" \
    | rofi -dmenu -i -p "Power" \
    -theme "~/.config/rofi/powermenu.rasi")

# Logic
case "$choice" in
  "$lock")     hyprlock ;;
  "$logout")   hyprctl dispatch exit ;;
  "$suspend")  systemctl suspend ;;
  "$reboot")   systemctl reboot ;;
  "$shutdown") systemctl poweroff ;;
esac
