#!/usr/bin/env bash

# --- Configuration ---
MENU_CMD="rofi --dmenu --prompt 'Select Exit Node'"  # Change to rofi/fuzzel/dmenu as needed
STATE_FILE="/tmp/tailscale-waybar.state"             # Used to track transition states
APP_NAME="Tailscale"                                 # Notification app name
ICON="network-vpn"                                   # Notification icon

# --- Helpers ---
notify() {
    local urgency="$1"
    local title="$2"
    local message="$3"
    notify-send -a "$APP_NAME" -i "$ICON" -u "$urgency" "$title" "$message"
}

get_backend_state() {
    tailscale status --json | jq -r '.BackendState // "Stopped"'
}

# --- Actions ---
toggle_status() {
    local current_state
    current_state=$(get_backend_state)

    if [[ "$current_state" == "Running" ]]; then
        echo "disconnecting" > "$STATE_FILE"
        notify "low" "Tailscale" "Disconnecting..."

        tailscale down

        rm -f "$STATE_FILE"
        notify "normal" "Tailscale" "Disconnected"
    else
        echo "connecting" > "$STATE_FILE"
        # notify "low" "Tailscale" "Connecting..."

        tailscale up

        rm -f "$STATE_FILE"
        notify "normal" "Tailscale" "Connected"
    fi
}

select_exit_node() {
    if [[ "$(get_backend_state)" != "Running" ]]; then
        notify "critical" "Tailscale" "VPN must be running to set an exit node."
        return 1
    fi

    # Get available exit nodes and strip the long tailnet domain for cleaner menus
    local nodes
    nodes=$(tailscale status --json | jq -r '
        .Peer[] | select(.ExitNodeOption == true) | .DNSName | split(".")[0]
    ')

    if [[ -z "$nodes" ]]; then
        notify "normal" "Tailscale" "No exit nodes available on your network."
        return 1
    fi

    local options="None (disable exit node)\n$nodes"
    local selected
    selected=$(echo -e "$options" | eval "$MENU_CMD")

    # User cancelled
    [[ -z "$selected" ]] && return 0

    if [[ "$selected" == "None"* ]]; then
        notify "low" "Tailscale" "Disabling exit node..."
        tailscale set --exit-node=
        notify "normal" "Tailscale" "Exit node disabled"
    else
        notify "low" "Tailscale" "Connecting to exit node: $selected..."
        tailscale set --exit-node="$selected"
        notify "normal" "Tailscale" "Traffic is now routed through $selected"
    fi
}

print_status() {
    # 1. Check for manual transition states first
    if [[ -f "$STATE_FILE" ]]; then
        local transition_state
        transition_state=$(cat "$STATE_FILE")
        if [[ "$transition_state" == "connecting" ]]; then
            echo '{"text":"Connecting...","class":"connecting","alt":"connecting","tooltip":"Connecting to Tailscale..."}'
            return
        elif [[ "$transition_state" == "disconnecting" ]]; then
            echo '{"text":"Disconnecting...","class":"disconnecting","alt":"disconnecting","tooltip":"Disconnecting from Tailscale..."}'
            return
        fi
    fi

    # 2. Get actual JSON status from Tailscale
    local status_json
    status_json=$(tailscale status --json)
    local backend_state
    backend_state=$(echo "$status_json" | jq -r '.BackendState // "Stopped"')

    # 3. Handle native Tailscale states
    if [[ "$backend_state" == "Starting" ]]; then
        echo '{"text":"Starting...","class":"connecting","alt":"connecting","tooltip":"Tailscale is starting..."}'
        return
    elif [[ "$backend_state" != "Running" ]]; then
        echo '{"text":"","class":"stopped","alt":"stopped","tooltip":"The VPN is not active."}'
        return
    fi

    # 4. Handle Running state (with your color/IP logic)
    local T="green"
    local F="red"
    local I="none"
    local colors=()

    # Parse arguments for colors and IP version
    for arg in "$@"; do
        arg_lower=$(echo "$arg" | tr '[:upper:]' '[:lower:]' | tr -d '\n')
        case "$arg_lower" in
            ipv4|ipv6) I="$arg_lower" ;;
            *) [[ -n "$arg" ]] && colors+=("$arg") ;;
        esac
    done

    [[ ${#colors[@]} -ge 1 ]] && T="${colors[0]}"
    [[ ${#colors[@]} -ge 2 ]] && F="${colors[1]}"

    local ip_index=""
    case "$I" in
        ipv4) ip_index="0" ;;
        ipv6) ip_index="-1" ;;
    esac

    # Extract peers for the tooltip
    local peers
    if [[ -n "$ip_index" ]]; then
        peers=$(jq -r --arg T "$T" --arg F "$F" --arg Index "$ip_index" '
            .Peer[]? |
            "<span color=\"" + (if .Online then $T else $F end) + "\">" +
            (.DNSName | split(".")[0]) + ": (" + .TailscaleIPs[$Index|tonumber] + ")</span>"
        ' <<< "$status_json")
    else
        peers=$(jq -r --arg T "$T" --arg F "$F" '
            .Peer[]? |
            "<span color=\"" + (if .Online then $T else $F end) + "\">" +
            (.DNSName | split(".")[0]) + "</span>"
        ' <<< "$status_json")
    fi

    # Extract exit node
    local exitnode
    exitnode=$(jq -r '.Peer[]? | select(.ExitNode == true).DNSName | split(".")[0]' <<< "$status_json")

    # Format the final Waybar output
    jq -nc --arg txt " exit-node: ${exitnode:-none}" --arg tip "$peers" \
        '{"text": $txt, "class": "connected", "alt": "connected", "tooltip": $tip}'
}

# --- Router ---
case $1 in
    --status)
        print_status "${@:2}"
    ;;
    --toggle)
        toggle_status
    ;;
    --select-exit-node)
        select_exit_node
    ;;
    *)
        echo "Usage: $0 {--status|--toggle|--select-exit-node}"
        exit 1
    ;;
esac
