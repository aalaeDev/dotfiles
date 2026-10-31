#!/usr/bin/env bash

# Lock the screen, with a sound for locking and for a successful unlock.

BIN="$(dirname "$(readlink -f "$0")")"

pidof hyprlock > /dev/null && exit 0  # avoid starting multiple instances

"$BIN/sound.sh" lock &
hyprlock && "$BIN/sound.sh" unlock
