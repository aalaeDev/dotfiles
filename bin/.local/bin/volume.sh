#!/usr/bin/env bash

# Change the volume in small steps that get bigger while the key is held. Stops at 100%.
#
#   volume.sh up|down

# --- Configuration ---
HOLD_GAP_MS=150     # Key repeats arrive closer together than this
FAST_AFTER_MS=800   # Held for this long: FAST_STEP instead of 1
FAST_STEP=2         # % per repeat
TICK_GAP_MS=120     # Otherwise the sounds of a held key merge into a buzz
RUN="${XDG_RUNTIME_DIR:-/tmp}"
BIN="$HOME/.local/bin"  # Not worked out from $0: this runs 25 times a second, every process counts

case "$1" in
    up)   sign="+" ;;
    down) sign="-" ;;
    *)
        echo "Usage: $0 up|down" >&2
        exit 1
        ;;
esac

# --- Actions ---
# Still busy with the previous repeat: skip this one rather than fall behind the key
exec 9> "$RUN/volume-key.lock"
flock -n 9 || exit 0

now=$(( ${EPOCHREALTIME/[.,]/} / 1000 ))
read -r held_since last_press last_tick 2> /dev/null < "$RUN/volume-key"
(( now - ${last_press:-0} < HOLD_GAP_MS )) || held_since=$now

step=1
(( now - held_since >= FAST_AFTER_MS )) && step=$FAST_STEP

if (( now - ${last_tick:-0} >= TICK_GAP_MS )); then
    last_tick=$now
    "$BIN/sound.sh" volume 9>&- &
fi
echo "$held_since $now $last_tick" > "$RUN/volume-key"

wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ "$step%$sign"
exec 9>&-

# At either end the level doesn't change, so the popup has to be told
# Not pkill: that reads every process on the system, the slowest part of this script by far
read -r osd 2> /dev/null < "$RUN/osd.lock" && kill -USR1 "$osd" 2> /dev/null
