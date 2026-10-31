#!/usr/bin/env bash

# Rofi Wi-Fi menu: nearby networks, connect (asks for a password when needed), disconnect,
# rescan, toggle the radio. Launched from the waybar network module.

# --- Configuration ---
PROMPT="Wi-Fi"
APP_NAME="Wi-Fi"                     # Notification app name
ICON="network-wireless"              # Notification icon
SIGNAL_ICONS=(󰤯 󰤟 󰤢 󰤥 󰤨)            # Same as the waybar network module

# --- Helpers ---
notify() {
    notify-send -a "$APP_NAME" -i "$ICON" -u "$1" "$2" "$3"
}

menu() {
    rofi -dmenu -i -p "$PROMPT" -format i "$@"
}

ask_password() {
    rofi -dmenu -password -p "Password" -mesg "$1" -l 0 \
        -theme-str 'entry { placeholder: "Password"; } counter { enabled: false; }' < /dev/null
}

signal_icon() {
    local i=$(( $1 * ${#SIGNAL_ICONS[@]} / 100 ))  # same buckets as waybar
    (( i >= ${#SIGNAL_ICONS[@]} )) && i=$(( ${#SIGNAL_ICONS[@]} - 1 ))
    echo "${SIGNAL_ICONS[$i]}"
}

has_profile() {
    nmcli -t -f NAME connection show | grep -Fxq -- "$1"
}

# Last line of nmcli's error, without the "Error: " prefix
reason() {
    tail -n 1 <<< "$1" | sed 's/^Error: //'
}

# --- Actions ---
connect() {
    local ssid="$1" secured="$2" out pass

    # Known network: reuse its saved profile
    if has_profile "$ssid"; then
        out=$(nmcli connection up id "$ssid" 2>&1) && {
            notify "normal" "Wi-Fi" "Connected to $ssid"
            return
        }
        # Saved password may be outdated: ask again and update the profile
        [[ "$secured" == 1 ]] || { notify "critical" "Wi-Fi" "Could not connect to $ssid: $(reason "$out")"; return 1; }
        pass=$(ask_password "Saved password for $ssid didn't work") || return 0
        [[ -z "$pass" ]] && return 0
        nmcli connection modify id "$ssid" wifi-sec.psk "$pass" > /dev/null 2>&1
        out=$(nmcli connection up id "$ssid" 2>&1)
    elif [[ "$secured" == 1 ]]; then
        pass=$(ask_password "$ssid") || return 0
        [[ -z "$pass" ]] && return 0
        out=$(nmcli device wifi connect "$ssid" password "$pass" 2>&1)
    else
        out=$(nmcli device wifi connect "$ssid" 2>&1)
    fi

    if [[ $? -eq 0 ]]; then
        notify "normal" "Wi-Fi" "Connected to $ssid"
    else
        notify "critical" "Wi-Fi" "Could not connect to $ssid: $(reason "$out")"
        # Don't keep a profile with a wrong password around
        [[ "$out" == *"Secrets were required"* || "$out" == *"property is invalid"* ]] && nmcli connection delete id "$ssid" > /dev/null 2>&1
    fi
}

show_menu() {
    local rescan="${1:-yes}"  # always scan fresh when the menu opens

    if [[ "$(nmcli radio wifi)" != "enabled" ]]; then
        case "$(printf '%s\n' "󰖩  Turn Wi-Fi on" "󱚾  Saved connections" | menu)" in
            0) nmcli radio wifi on && notify "low" "Wi-Fi" "Turned on" ;;
            1) nm-connection-editor & ;;
        esac
        return
    fi

    local scan map active choice kind ssid secured
    scan=$(mktemp)
    map=$(mktemp)
    trap 'rm -f "$scan" "$map"' RETURN

    scan_networks "$rescan" "$scan" || return 0
    active=$(sed -n 's/^\*:[^:]*:[^:]*://p' "$scan" | head -n 1)

    # $map records what each menu line is, in the same order
    choice=$(entries "$scan" "$map" "$active" | menu -mesg "${active:+Connected to $active}")
    IFS=$'\t' read -r kind ssid secured < <(sed -n "$(( ${choice:--1} + 1 ))p" "$map" 2> /dev/null)

    case "$kind" in
        network)
            [[ "$ssid" == "$active" ]] || connect "$ssid" "$secured" ;;
        disconnect)
            nmcli connection down id "$active" > /dev/null 2>&1 && notify "low" "Wi-Fi" "Disconnected from $active" ;;
        rescan)
            show_menu yes ;;
        off)
            nmcli radio wifi off && notify "low" "Wi-Fi" "Turned off" ;;
        saved)
            nm-connection-editor & ;;
    esac
}

# Scan into $2 while a "Scanning" window (same size as the menu) is up; fails if it was dismissed
scan_networks() {
    local rescan="$1" out="$2" scanner loader
    nmcli -t --escape no -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan "$rescan" > "$out" 2> /dev/null &
    scanner=$!
    rofi -dmenu -p "$PROMPT" -mesg "󰑐  Scanning for networks…" \
        -theme-str 'entry { placeholder: "Scanning…"; } counter { enabled: false; }' < /dev/null > /dev/null 2>&1 &
    loader=$!

    wait -n "$scanner" "$loader"
    if kill -0 "$scanner" 2> /dev/null; then
        # The loading window closed first: Esc, so give up
        kill "$scanner" 2> /dev/null
        return 1
    fi
    kill "$loader" 2> /dev/null
    wait "$loader" 2> /dev/null
    return 0
}

# Menu lines on stdout ("kind<TAB>ssid<TAB>secured" for each one goes to $2): the scanned networks,
# one per name (its strongest access point), strongest first, then the actions
entries() {
    local scan="$1" map="$2" active="$3" inuse signal security ssid line secured
    local -A seen

    while IFS=: read -r inuse signal security ssid; do
        [[ -z "$ssid" || -n "${seen[$ssid]}" ]] && continue
        seen[$ssid]=1
        secured=$([[ -n "$security" && "$security" != "--" ]] && echo 1 || echo 0)

        line="$(signal_icon "$signal")  $ssid"
        [[ "$secured" == 1 ]] && line+="  󰌾"
        [[ "$inuse" == "*" ]] && line+="  󰄬"

        printf 'network\t%s\t%s\n' "$ssid" "$secured" >> "$map"
        echo "$line"
    done < <(sort -t: -k2,2nr "$scan")

    if [[ -n "$active" ]]; then
        printf 'disconnect\t\t\n' >> "$map"
        echo "󰌙  Disconnect from $active"
    fi
    printf 'rescan\t\t\noff\t\t\nsaved\t\t\n' >> "$map"
    printf '%s\n' "󰑐  Rescan" "󰖪  Turn Wi-Fi off" "󱚾  Saved connections"
}

# A second click closes the menu instead of stacking another one
pkill -x rofi && exit 0

show_menu
