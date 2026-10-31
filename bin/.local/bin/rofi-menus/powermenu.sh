#!/usr/bin/env bash

# Power menu: a row of tiles under the session info. Launched from waybar and Super+X.

tile() {
    printf "<span size='xx-large'>%s</span>\n<span size='small'>%s</span>|" "$1" "$2"
}

color() {
    sed -n "s/^ *$1: *\(#[0-9a-fA-F]*\);.*/\1/p" "$HOME/.config/rofi/colors.rasi"
}

# Session info, the same icon + value pair for each item
info() {
    local accent dim uptime battery capacity status icon levels=(󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)
    accent=$(color selected)
    dim=$(color foreground-dim)
    item() { printf "<span foreground='%s'>%s</span> %s    " "$accent" "$1" "$2"; }

    uptime=$(uptime -p | sed 's/^up //; s/ weeks\?/w/; s/ days\?/d/; s/ hours\?/h/; s/ minutes\?/m/; s/,//g')
    item "󰀄" "<b>$USER</b>"
    item "󰥔" "$(date '+%a %d %b  %H:%M')"
    item "󰔟" "<span foreground='$dim'>up</span> $uptime"

    for battery in /sys/class/power_supply/BAT*; do
        [[ -r "$battery/capacity" ]] || continue
        capacity=$(< "$battery/capacity")
        status=$(< "$battery/status")
        icon=${levels[$(( capacity >= 100 ? 9 : capacity / 10 ))]}
        [[ "$status" == "Charging" ]] && icon="󰂄"
        item "$icon" "$capacity%"
        break
    done
}

choice=$( {
    tile "󰌾" "Lock"
    tile "󰍃" "Logout"
    tile "󰒲" "Suspend"
    tile "󰜉" "Reboot"
    tile "󰐥" "Shutdown"
} | rofi -dmenu -i -markup-rows -format i -p "Power" -mesg "$(info | sed 's/ *$//')" -sep '|' -eh 3 \
    -theme "~/.config/rofi/powermenu.rasi")

case "$choice" in
    0) "$HOME/.local/bin/lock.sh" ;;
    1) "$HOME/.local/bin/sound.sh" session-end; hyprctl dispatch 'hl.dsp.exit()' ;;
    2) systemctl suspend ;;
    3) "$HOME/.local/bin/sound.sh" session-end; systemctl reboot ;;
    4) "$HOME/.local/bin/sound.sh" session-end; systemctl poweroff ;;
esac
