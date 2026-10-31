#!/usr/bin/env bash

# Sounds for what happens without a keypress: charger, USB, Bluetooth audio, mic mute and low battery.
# Started from hyprland.lua. Sounds that come with an action are played by the script of that action.

# --- Configuration ---
SOUND="$(dirname "$(readlink -f "$0")")/sound.sh"
LOW_PCT=20         # Sound when the battery drops to this %, on battery power
CRITICAL_PCT=10    # And again at this %
REARM_PCT=25       # Sound again only after charging above this %
BATTERY_INTERVAL=30
RESUME_QUIET=10    # Seconds of silence after waking up: devices come back one by one
DEVICE_GAP=2       # A dock or hub is many USB devices: one sound for all of them
RUN="${XDG_RUNTIME_DIR:-/tmp}/sound-daemon"
LOCK="$RUN/lock"

# --- Helpers ---
# Don't wait for the sound: the next event may be right behind it
play() {
    "$SOUND" "$1" &
}

# Also silent while going to sleep and waking up, when nothing that changes is news
quiet() {
    (( $(date +%s) < $(cat "$RUN/quiet-until" 2> /dev/null || echo 0) ))
}

play_device() {
    local now last
    now=$(date +%s)
    last=$(cat "$RUN/device-last" 2> /dev/null || echo 0)
    (( now - last < DEVICE_GAP )) && return 0
    echo "$now" > "$RUN/device-last"
    play "$1"
}

# --- Actions ---
watch_sleep() {
    gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 2> /dev/null |
        while read -r line; do
            case "$line" in
                *PrepareForSleep\ \(true\)*) echo $(( $(date +%s) + 86400 )) > "$RUN/quiet-until" ;;
                *PrepareForSleep\ \(false\)*) echo $(( $(date +%s) + RESUME_QUIET )) > "$RUN/quiet-until" ;;
            esac
        done
}

# udev prints each event as properties, ending on an empty line
watch_devices() {
    local action="" devtype="" type="" online="" charger=""
    charger=$(cat /sys/class/power_supply/A*/online 2> /dev/null | head -n 1)
    udevadm monitor --udev --property --subsystem-match=usb/usb_device --subsystem-match=power_supply 2> /dev/null |
        while IFS= read -r line; do
            case "$line" in
                ACTION=*) action="${line#*=}" ;;
                DEVTYPE=*) devtype="${line#*=}" ;;
                POWER_SUPPLY_TYPE=*) type="${line#*=}" ;;
                POWER_SUPPLY_ONLINE=*) online="${line#*=}" ;;
                "")
                    if [[ "$type" == Mains && "$online" != "$charger" ]]; then
                        charger="$online"
                        quiet || { [[ "$online" == 1 ]] && play power-in || play power-out; }
                    elif [[ "$devtype" == usb_device ]] && ! quiet; then
                        [[ "$action" == add ]] && play_device device-in
                        [[ "$action" == remove ]] && play_device device-out
                    fi
                    action="" devtype="" type="" online=""
                    ;;
            esac
        done
}

# Audio devices only: a Bluetooth mouse drops and reconnects whenever it dozes off
watch_bluetooth() {
    local address
    gdbus monitor --system --dest org.bluez 2> /dev/null | while read -r line; do
        [[ "$line" =~ dev_([0-9A-F_]+):.*org\.bluez\.Device1.*\'Connected\':\ \<(true|false)\> ]] || continue
        address="${BASH_REMATCH[1]//_/:}"
        quiet && continue
        bluetoothctl info "$address" | grep -q 'Icon: audio' || continue
        [[ "${BASH_REMATCH[2]}" == true ]] && play device-in || play device-out
    done
}

# Follows the mute itself, so it also hears the swaync button and a mute button on a headset
watch_mic() {
    local source muted now_source now_muted
    source=$(pactl get-default-source)
    muted=$(pactl get-source-mute "$source")
    pactl subscribe | while read -r line; do
        [[ "$line" == *"on source #"* || "$line" == *"on server"* ]] || continue
        now_source=$(pactl get-default-source)
        now_muted=$(pactl get-source-mute "$now_source" 2> /dev/null) || continue
        if [[ "$now_source" == "$source" && "$now_muted" != "$muted" ]]; then
            [[ "$now_muted" == *yes ]] && play mic-off || play mic-on
        fi
        source="$now_source" muted="$now_muted"
    done
}

watch_battery() {
    local level=0 battery capacity status
    battery=$(echo /sys/class/power_supply/BAT*)
    [[ -r "$battery/capacity" ]] || return 0
    while :; do
        capacity=$(< "$battery/capacity")
        status=$(< "$battery/status")
        if [[ "$status" == Discharging ]] && (( capacity <= CRITICAL_PCT && level < 2 )); then
            play battery-critical
            level=2
        elif [[ "$status" == Discharging ]] && (( capacity <= LOW_PCT && level < 1 )); then
            play battery-low
            level=1
        elif (( capacity > REARM_PCT )); then
            level=0
        fi
        sleep "$BATTERY_INTERVAL"
    done
}

# --- Router ---
mkdir -p "$RUN"
exec 9> "$LOCK"
flock -n 9 || exit 0  # already running

trap 'pkill -P $$' EXIT
# 9>&-: the watchers mustn't inherit the lock, or a restart would find it taken
watch_sleep 9>&- &
watch_devices 9>&- &
watch_bluetooth 9>&- &
watch_mic 9>&- &
watch_battery 9>&- &
wait
