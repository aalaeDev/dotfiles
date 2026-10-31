#!/usr/bin/env bash

# Play a desktop sound. The sounds come from sound-generate.py.
#
#   sound.sh <name>         Play one sound, a file name in the sounds package
#   sound.sh notification   Pick the sound of the notification swaync just received
#   sound.sh walker         The menu sound, unless this keypress is closing Walker. Run it before Walker
#   sound.sh session-start  Wait for the audio server first, it starts along with the session
#   sound.sh test           Play everything, to hear how it all sounds
#
# Blocks until the sound is over: add & unless what comes next should wait for it.

# shellcheck source=/dev/null
source "$(dirname "$(readlink -f "$0")")/rice-env.sh"

# --- Configuration ---
SOUNDS="$HOME/.local/share/sounds/rice"
TEST_GAP=0.4  # Seconds of silence between sounds in the test

# --- Helpers ---
play() {
    [[ -r "$SOUNDS/$1.ogg" ]] || return 0
    # Its default latency is 100 ms, enough to hear a key press and its sound as two separate things
    pw-play --latency=20ms --volume "$SOUND_VOLUME" "$SOUNDS/$1.ogg" 2> /dev/null
}

# The apps here have a sound of their own, or sound.sh has already been told about the event
notification() {
    [[ "$(swaync-client -D)" == true ]] && return 0
    case "$SWAYNC_APP_NAME" in
        Screenshot | "Power Manager") return 0 ;;
        Athan) play athan ;;
        Memory) play warning ;;
        *)
            if [[ "$SWAYNC_URGENCY" == Critical ]]; then
                play critical
            else
                play notification
            fi
            ;;
    esac
}

# --- Actions ---
case "$1" in
    notification) notification ;;
    walker) hyprctl layers | grep -q 'namespace: walker' || { play menu & } ;;
    session-start)
        for _ in {1..50}; do
            pactl info &> /dev/null && break
            sleep 0.2
        done
        play session-start
        ;;
    test)
        for file in "$SOUNDS"/*.ogg; do
            name="${file##*/}"
            echo "${name%.ogg}"
            play "${name%.ogg}"
            sleep "$TEST_GAP"
        done
        ;;
    *) play "$1" ;;
esac
