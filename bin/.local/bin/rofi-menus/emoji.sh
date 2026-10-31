#!/usr/bin/env bash

# Emoji and kaomoji picker: inserts into the focused window, categories as tabs, most used first.
#
#   emoji.sh [emoji|kaomoji]    Open a menu
#   emoji.sh rows <kind> <tab>  Rofi's script mode: list a tab, or record what was picked

# --- Configuration ---
SELF="$HOME/.local/bin/rofi-menus/emoji.sh"
BUILD="$HOME/.local/bin/rofi-menus/emoji-data.py"
INSERT="$HOME/.local/bin/clipboard-insert.sh"
CACHE="$HOME/.cache/rofi-emoji"
HISTORY="$HOME/.local/state/rofi-emoji"
PICK="${XDG_RUNTIME_DIR:-/tmp}/rofi-emoji-pick"
RECENT=26          # Two rows of the grid in the all tab
EMOJI_TABS=(all smileys people nature food travel activities objects symbols flags)
KAOMOJI_TABS=(all happy love sad angry flip shrug hide animal)

hints() {
    local other="kaomoji"
    [[ "$1" == "kaomoji" ]] && other="emoji"
    echo "<b>Enter</b> insert   <b>Alt+c</b> copy   <b>Tab</b> next category   <b>Alt+k</b> $other"
}

# --- Rofi's script mode: runs once per tab, and again on a pick ---
rows() {
    local kind="$1" tab="$2" text="$3"
    case "${ROFI_RETV:-0}" in
        0)
            # Script mode takes its message from here, not from -mesg
            printf '\0message\x1f%s\n' "$(hints "$kind")"
            # Off by default: without it Alt+c and Alt+k never reach this script
            printf '\0use-hot-keys\x1ftrue\n'
            cat "$CACHE/$kind-$tab.rows"
            ;;
        1)  printf 'insert\n%s' "$text" > "$PICK" ;;
        10) printf 'copy\n%s' "$text" > "$PICK" ;;
        11) printf 'switch\n' > "$PICK" ;;
    esac
}

# --- Helpers ---
# Data files only change with rofimoji, so the rows outlive a session
ensure_rows() {
    [[ -f "$CACHE/emoji-all.rows" && -f "$CACHE/kaomoji-all.rows" && "$CACHE/emoji-all.rows" -nt "$BUILD" ]] \
        || python3 "$BUILD"
}

# Move the most used entries to the top of the all tab
rank() {
    local kind="$1" base="$CACHE/$kind-base.rows" all="$CACHE/$kind-all.rows" top
    [[ -f "$base" && "$base" -nt "$BUILD" ]] || cp "$all" "$base"
    top=$(sort "$HISTORY/$kind" | uniq -c | sort -rn | head -n "$RECENT" | sed -E 's/^ *[0-9]+ //')
    awk -F'\0' -v top="$top" '
        BEGIN { n = split(top, names, "\n"); for (i = 1; i <= n; i++) order[names[i]] = i }
        ($1 in order) { first[order[$1]] = $0; next }
        { rest[++count] = $0 }
        END {
            for (i = 1; i <= n; i++) if (i in first) print first[i]
            for (i = 1; i <= count; i++) print rest[i]
        }' "$base" > "$all.tmp" && mv "$all.tmp" "$all"
}

open_menu() {
    local kind="$1" tab modi="" tabs first
    if [[ "$kind" == "emoji" ]]; then
        tabs=("${EMOJI_TABS[@]}")
    else
        tabs=("${KAOMOJI_TABS[@]}")
    fi
    for tab in "${tabs[@]}"; do
        modi+="${tab^}:$SELF rows $kind $tab,"
    done
    first="${tabs[0]^}"

    rm -f "$PICK"
    rofi -show "$first" -modi "${modi%,}" -theme "$HOME/.config/rofi/$kind.rasi" -i -no-custom -scroll-method 1 \
        -kb-element-next "" -kb-element-prev "" -kb-mode-next "Tab" -kb-mode-previous "ISO_Left_Tab" \
        -kb-row-left Left -kb-row-right Right -kb-move-char-back Control+b -kb-move-char-forward Control+f \
        -kb-custom-1 "Alt+c" -kb-custom-2 "Alt+k"
}

# --- Main ---
if [[ "$1" == "rows" ]]; then
    rows "$2" "$3" "$4"
    exit 0
fi

ensure_rows
mkdir -p "$HISTORY"
kind="${1:-emoji}"

while true; do
    open_menu "$kind"
    [[ -f "$PICK" ]] || exit 0
    { read -r action; text=$(cat); } < "$PICK"
    rm -f "$PICK"

    case "$action" in
        switch)
            [[ "$kind" == "emoji" ]] && kind="kaomoji" || kind="emoji"
            continue
            ;;
        insert) "$INSERT" "$text" ;;
        copy)   printf '%s' "$text" | wl-copy ;;
    esac
    echo "$text" >> "$HISTORY/$kind"
    rank "$kind"
    exit 0
done
