#!/usr/bin/env bash

# Waybar custom/power-plan module: show and switch the power-profiles-daemon plan.
# The script streams a line per change, so plans set elsewhere show up too. Note that
# xfce4-power-manager goes back to its profile-on-ac / profile-on-battery plan
# (default: balanced) when the charger is plugged in or out.
#
# --auto (started by Hyprland) drops from the default plan to power saver on low battery and
# back once it's above the threshold. Other plans are left alone, and so is a plan picked
# while the battery is low, until it's above the threshold again.
#
#   waybar-power-plan.sh [--watch|--cycle|--default|--auto]

# --- Configuration ---
PLANS=(power-saver balanced performance)   # Click order
DEFAULT="balanced"
LOW_BATTERY=20   # Percent; same as the battery module's warning state
AUTO_POLL=60     # Seconds between battery checks
AUTO_STATE="${XDG_RUNTIME_DIR:-/tmp}/waybar-power-plan.auto"   # "auto" or "manual" while low

# --- Helpers ---
current() {
    powerprofilesctl get 2> /dev/null
}

status() {
    local plan tooltip
    plan=$(current)
    case "$plan" in
        power-saver) tooltip="Power saver: slower, longer battery" ;;
        balanced) tooltip="Balanced" ;;
        performance) tooltip="Performance: faster, shorter battery" ;;
        *) plan="unavailable" tooltip="power-profiles-daemon isn't running" ;;
    esac
    tooltip+="\nClick: next plan · Right-click: back to $DEFAULT"
    printf '{"alt": "%s", "class": "%s", "tooltip": "%s"}\n' "$plan" "$plan" "$tooltip"
}

battery_low() {
    local battery
    for battery in /sys/class/power_supply/BAT*; do
        [[ -r "$battery/capacity" ]] || continue
        (( $(< "$battery/capacity") <= LOW_BATTERY ))
        return
    done
    return 1
}

# A choice made while low wins over --auto until the battery recovers
mark_manual() {
    if battery_low; then
        echo manual > "$AUTO_STATE"
    fi
}

# --- Actions ---
auto() {
    exec 9> "$AUTO_STATE.lock"
    flock -n 9 || exit 0   # Already running

    local plan state
    while sleep "$AUTO_POLL"; do
        plan=$(current)
        state=$(cat "$AUTO_STATE" 2> /dev/null)
        if battery_low; then
            if [[ $state != manual && $plan == "$DEFAULT" ]]; then
                powerprofilesctl set power-saver && echo auto > "$AUTO_STATE"
            fi
        else
            if [[ $state == auto && $plan == power-saver ]]; then
                powerprofilesctl set "$DEFAULT"
            fi
            rm -f "$AUTO_STATE"
        fi
    done
}

watch_plan() {
    status
    # Waits for the service if it isn't up yet. The first change can arrive as ActiveProfile
    # or as a name owner change, so any message on its name refreshes
    gdbus monitor --system --dest net.hadess.PowerProfiles 2> /dev/null | while read -r _; do
        status
    done
}

cycle() {
    local plan i
    plan=$(current) || exit 0
    mark_manual
    for i in "${!PLANS[@]}"; do
        if [[ ${PLANS[i]} == "$plan" ]]; then
            powerprofilesctl set "${PLANS[(i + 1) % ${#PLANS[@]}]}"
            return
        fi
    done
}

# --- Main ---
case "${1:-}" in
    --watch) watch_plan ;;
    --cycle) cycle ;;
    --default)
        mark_manual
        powerprofilesctl set "$DEFAULT"
        ;;
    --auto) auto ;;
    *) status ;;
esac
