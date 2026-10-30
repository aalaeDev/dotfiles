#!/usr/bin/env bash

# Waybar custom/updates module: pending pacman repo + AUR updates.

# --- Configuration ---
TERMINAL="${TERMINAL:-kitty}"
TOOLTIP_MAX_LINES=25

# --- Helpers ---
aur_helper() {
    for helper in paru yay; do
        if command -v "$helper" > /dev/null; then
            echo "$helper"
            return 0
        fi
    done
    return 1
}

# Escape for pango markup, then for a JSON string, joining lines with \n.
json_escape() {
    sed -e 's/\\/\\\\/g' -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\\"/g' \
        | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}

# --- Actions ---
print_status() {
    local repo aur helper list count tooltip

    repo=$(checkupdates 2> /dev/null || pacman -Qu 2> /dev/null)
    helper=$(aur_helper) && aur=$("$helper" -Qua 2> /dev/null)

    list=$(printf '%s\n%s\n' "$repo" "$aur" | grep .)
    count=$(printf '%s\n' "$list" | grep -c .)

    if [ "$count" -eq 0 ]; then
        echo '{"text": "", "alt": "updated", "class": "updated", "tooltip": "System is up to date"}'
        return
    fi

    tooltip=$(printf '%s\n' "$list" \
        | head -n "$TOOLTIP_MAX_LINES" \
        | json_escape)
    if [ "$count" -gt "$TOOLTIP_MAX_LINES" ]; then
        tooltip="$tooltip\\n… and $((count - TOOLTIP_MAX_LINES)) more"
    fi

    echo "{\"text\": \"$count \", \"alt\": \"has-updates\", \"class\": \"has-updates\", \"tooltip\": \"$tooltip\"}"
}

run_upgrade() {
    local helper cmd
    if helper=$(aur_helper); then
        cmd="$helper -Syu"
    else
        cmd="sudo pacman -Syu"
    fi

    "$TERMINAL" -e bash -c "$cmd; echo; read -n1 -r -p 'Press any key to close...'"
    pkill -RTMIN+9 waybar
}

# --- Entry point ---
case "$1" in
    --upgrade) run_upgrade ;;
    *) print_status ;;
esac
