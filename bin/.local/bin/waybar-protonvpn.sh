#!/usr/bin/env bash

# Waybar custom/protonvpn module: Proton VPN status + connect/disconnect via the official CLI.
# Status is read from NetworkManager (fast), actions go through `protonvpn` (proton-vpn-cli).

# --- Configuration ---
SIGNAL=10                                                   # Must match "signal" in modules.jsonc
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/protonvpn-waybar.state" # Used to track transition states
APP_NAME="Proton VPN"                                       # Notification app name
CLI_LOG="$HOME/.cache/Proton/VPN/logs/vpn-cli.log"          # Where the CLI logs failures
ICON="network-vpn"                                          # Notification icon
FRAMES=3                                                    # Animation frames, "<state>-N" keys in format-icons
FRAME_MS=250                                                # Animation frame duration
COUNTRIES=(                                                 # Right-click menu; typing any other country works too
    "United States" "United Kingdom" "Germany" "Netherlands"
    "Switzerland" "France" "Spain" "Japan" "Canada"
)

# --- Helpers ---
notify() {
    notify-send -a "$APP_NAME" -i "$ICON" -u "$1" "$2" "$3"
}

# Last lines of CLI output, or of the CLI log when the CLI failed silently.
failure_reason() {
    if [[ -n "$1" ]]; then
        tail -n 3 <<< "$1"
    else
        grep -E '\| ERROR \|' "$CLI_LOG" 2> /dev/null | tail -n 1 | awk -F' \\| ' '{ print $NF }'
        echo "See $CLI_LOG"
    fi
}

refresh() {
    pkill -RTMIN+"$SIGNAL" waybar
}

# Active Proton connection as "NAME:DEVICE" (e.g. "ProtonVPN CH#242:proton0"), empty when down.
active_connection() {
    nmcli -t -f NAME,DEVICE connection show --active 2> /dev/null \
        | grep -m1 -E '^ProtonVPN|:proton[0-9]+$'
}

set_state() {
    echo "$1" > "$STATE_FILE"
    refresh

    # Keep waybar redrawing so the icon animates; stops on its own once the state file is gone
    (
        while [[ -f "$STATE_FILE" ]]; do
            sleep "0.$(printf '%03d' "$FRAME_MS")"
            refresh
        done
    ) &
    ANIMATION_PID=$!
}

clear_state() {
    rm -f "$STATE_FILE"
    kill "$ANIMATION_PID" 2> /dev/null
    refresh
}

# --- Actions ---
connect() {
    local output conn
    set_state "connecting"

    if output=$(protonvpn connect "$@" 2>&1); then
        conn=$(active_connection)
        notify "normal" "Proton VPN" "Connected to ${conn%%:*}"
    else
        notify "critical" "Proton VPN" "Connection failed:\n$(failure_reason "$output")"
    fi

    clear_state
}

disconnect() {
    local output
    set_state "disconnecting"

    if output=$(protonvpn disconnect 2>&1); then
        notify "normal" "Proton VPN" "Disconnected"
    else
        notify "critical" "Proton VPN" "Disconnect failed:\n$(failure_reason "$output")"
    fi

    clear_state
}

toggle() {
    # Ignore clicks while a connect/disconnect is still in progress
    [[ -f "$STATE_FILE" ]] && return 0

    if [[ -n "$(active_connection)" ]]; then
        disconnect
    else
        connect
    fi
}

select_country() {
    [[ -f "$STATE_FILE" ]] && return 0

    local selected
    selected=$(printf '%s\n' "Fastest" "${COUNTRIES[@]}" "Disconnect" \
        | rofi -dmenu -i -p "Proton VPN")

    # User cancelled
    [[ -z "$selected" ]] && return 0

    case "$selected" in
        Fastest) connect ;;
        Disconnect) disconnect ;;
        *) connect --country "$selected" ;;
    esac
}

print_status() {
    # 1. Transition states set by this script
    #    Runs several times a second while animating, so no forks here: frame comes from the clock
    if [[ -f "$STATE_FILE" ]]; then
        local state frame
        read -r state < "$STATE_FILE"
        frame=$(( ${EPOCHREALTIME/[.,]/} / (FRAME_MS * 1000) % FRAMES ))
        printf '{"text": "", "alt": "%s-%d", "class": "%s", "tooltip": "Proton VPN: %s..."}\n' \
            "$state" "$frame" "$state" "$state"
        return
    fi

    # 2. Actual connection state from NetworkManager
    local conn name device
    conn=$(active_connection)

    if [[ -z "$conn" ]]; then
        echo '{"text": "", "alt": "disconnected", "class": "disconnected", "tooltip": "Proton VPN: disconnected\nClick: connect to fastest server\nRight-click: choose country"}'
        return
    fi

    name=${conn%%:*}
    device=${conn##*:}

    jq -nc --arg txt " ${name#ProtonVPN }" --arg tip "Proton VPN: connected to ${name#ProtonVPN } ($device)" \
        '{"text": $txt, "alt": "connected", "class": "connected", "tooltip": "\($tip)\nClick: disconnect\nRight-click: switch country"}'
}

# --- Router ---
case $1 in
    --status)
        print_status
        ;;
    --toggle)
        toggle
        ;;
    --select-country)
        select_country
        ;;
    *)
        echo "Usage: $0 {--status|--toggle|--select-country}"
        exit 1
        ;;
esac
