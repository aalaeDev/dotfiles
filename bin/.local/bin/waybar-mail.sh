#!/usr/bin/env bash

# Waybar custom/mail module: unread count of Betterbird's Unified Inbox, updated in real time.
# Betterbird keeps the Unified Inbox's unread count in "smart mailboxes/Inbox.msf" (a Mork db)
# and appends to it the moment the count changes, so we watch that file with inotify.

# --- Configuration ---
APP="betterbird"   # Command that launches it
PROCESS="betterbird(-bin)?" # Its process name (the AUR binary runs as betterbird-bin)
WORKSPACE="mail"   # Special workspace Betterbird lives on (SUPER+M)
PROFILES="$HOME/.thunderbird"
FALLBACK_POLL=30   # Seconds between checks when the file doesn't change (Betterbird start/quit)

# --- Helpers ---
# Unified Inbox db of the most recently used profile
inbox_db() {
    ls -t "$PROFILES"/*/"Mail/smart mailboxes/Inbox.msf" 2> /dev/null | head -n 1
}

# Last value of the folder's numNewMsgs column (Thunderbird's name for the unread count).
# Mork appends every change, so the last "(^<col>=<hex>)" is current; lines end in "\" when wrapped.
unread_count() {
    local db="$1" col hex
    col=$(grep -oE '\(([0-9A-F]+)=numNewMsgs\)' "$db" | head -n 1 | sed -E 's/\(([0-9A-F]+)=.*/\1/')
    [[ -z "$col" ]] && return 1
    hex=$(sed -z 's/\\\n//g' "$db" | grep -oE "\(\^$col=[0-9a-fA-F]*\)" | tail -n 1 | sed -E 's/.*=([0-9a-fA-F]*)\)/\1/')
    echo $(( 16#${hex:-0} ))
}

# --- Actions ---
print_status() {
    local db count

    if ! pgrep -x "$PROCESS" > /dev/null; then
        echo '{"text": "", "alt": "closed", "class": "closed", "tooltip": "Betterbird is not running\nClick: open Betterbird"}'
        return
    fi

    db=$(inbox_db)
    count=$([[ -n "$db" ]] && unread_count "$db")
    count=${count:-0}

    if [[ "$count" -eq 0 ]]; then
        echo '{"text": "", "alt": "none", "class": "none", "tooltip": "Unified Inbox: no unread mail\nClick: open Betterbird"}'
    else
        printf '{"text": "%d ", "alt": "unread", "class": "unread", "tooltip": "Unified Inbox: %d unread\\nClick: open Betterbird"}\n' \
            "$count" "$count"
    fi
}

# Print the status, then again whenever the Unified Inbox db changes (exits when waybar closes the pipe)
watch_status() {
    local db last="" current
    while :; do
        current=$(print_status)
        if [[ "$current" != "$last" ]]; then
            echo "$current" || exit 0
            last="$current"
        fi

        db=$(inbox_db)
        if [[ -n "$db" ]]; then
            inotifywait -qq -t "$FALLBACK_POLL" -e modify,close_write,moved_to,create "$(dirname "$db")"
        else
            sleep "$FALLBACK_POLL"
        fi
    done
}

open_inbox() {
    if pgrep -x "$PROCESS" > /dev/null; then
        hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$WORKSPACE\")" > /dev/null
    else
        hyprctl dispatch "hl.dsp.exec_cmd(\"[workspace special:$WORKSPACE] $APP\")" > /dev/null
    fi
}

# --- Router ---
case $1 in
    --status)
        print_status
        ;;
    --watch)
        watch_status
        ;;
    --open)
        open_inbox
        ;;
    *)
        echo "Usage: $0 {--status|--watch|--open}"
        exit 1
        ;;
esac
