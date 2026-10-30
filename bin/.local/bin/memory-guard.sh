#!/usr/bin/env bash

# Desktop warnings before RAM runs out, and a notice when earlyoom closes an app.
# Started from hyprland.lua; earlyoom (system/etc/default/earlyoom) does the killing.

# --- Configuration ---
WARN_PCT=${WARN_PCT:-15}         # Notify when available memory (RAM + free swap) drops below this %
CRITICAL_PCT=${CRITICAL_PCT:-8}  # Urgent notification below this %
REARM_PCT=${REARM_PCT:-20}       # Warn again only after recovering above this %
INTERVAL=2                       # Seconds between checks
APP_NAME="Memory"
ICON="dialog-warning"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/memory-guard.lock"

# --- Helpers ---
notify() {
    notify-send -a "$APP_NAME" -i "$ICON" -u "$1" "$2" "$3"
}

# Available RAM plus free swap, as a % of RAM plus swap
available_pct() {
    awk '/^MemTotal:/ {t+=$2} /^SwapTotal:/ {t+=$2} /^MemAvailable:/ {a+=$2} /^SwapFree:/ {a+=$2}
         END {printf "%d", a * 100 / t}' /proc/meminfo
}

# "Zen 6.1G, code 2.9G, vesktop 1.3G": biggest apps, processes of one app summed
top_apps() {
    # comm can contain spaces ("Isolated Web Co"), so take everything after the RSS column
    ps -eo rss=,comm= | awk '{rss=$1; sub(/^ *[0-9]+ /, ""); n=$0
            if (n ~ /^(Isolated Web Co|Web Content|WebExtensions|Privileged Cont|RDD Process|Utility Process|zen-bin)$/) n="Zen"
            a[n]+=rss} END {for (k in a) printf "%d\t%s\n", a[k], k}' \
        | sort -rn | head -n 3 \
        | awk -F'\t' '{printf "%s%s %.1fG", sep, $2, $1/1048576; sep=", "}'
}

# --- Actions ---
watch_memory() {
    local level=0 pct  # 0 ok, 1 warned, 2 critical
    while :; do
        pct=$(available_pct)
        if (( pct < CRITICAL_PCT && level < 2 )); then
            notify "critical" "Memory almost full (${pct}% left)" "An app will be closed soon. Biggest: $(top_apps)"
            level=2
        elif (( pct < WARN_PCT && level < 1 )); then
            notify "normal" "Memory is getting low (${pct}% left)" "Biggest: $(top_apps)"
            level=1
        elif (( pct > REARM_PCT )); then
            level=0
        fi
        sleep "$INTERVAL"
    done
}

# earlyoom logs e.g.: sending SIGTERM to process 1234 uid 1000 "Isolated Web Co": badness 900, VmRSS 1200 MiB
watch_kills() {
    journalctl -f -n 0 -o cat -u earlyoom 2> /dev/null | while read -r line; do
        [[ "$line" =~ sending\ SIG[A-Z]+\ to\ process\ [0-9]+\ uid\ [0-9]+\ \"([^\"]+)\".*VmRSS\ ([0-9]+)\ MiB ]] || continue
        # GiB with a decimal: swaync offers a "copy" button for bare 4+ digit numbers (2FA codes)
        notify "critical" "Closed ${BASH_REMATCH[1]} to free memory" \
            "It was using $(awk -v m="${BASH_REMATCH[2]}" 'BEGIN {printf "%.1f", m / 1024}') GiB."
    done
}

# --- Router ---
exec 9> "$LOCK"
flock -n 9 || exit 0  # already running

watch_kills &
trap 'kill $! 2> /dev/null' EXIT
watch_memory
