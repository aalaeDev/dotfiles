#!/usr/bin/env bash

# Nemo's archive actions, built on bsdtar. Results land beside the originals and never
# replace anything; an archive bsdtar can't open (password, odd format) goes to File Roller.
#
#   file-archive.sh extract FILE...
#   file-archive.sh compress [--as FORMAT] FILE...

set -uo pipefail

# --- Configuration ---
APP_NAME="Archives"
ICON="package-x-generic"
FORMATS=(zip tar.gz tar.zst tar.xz 7z)
MENU_THEME='window { width: 420px; } prompt { enabled: false; } listview { lines: 5; fixed-height: true; }'

# --- Helpers ---
notify() {
    notify-send -a "$APP_NAME" -i "$ICON" "$@"
}

# First free path for $1 + $2 (name, extension): "name (2).ext" when "name.ext" is taken.
unique_path() {
    local path="$1$2" n=2
    while [[ -e $path ]]; do
        path="$1 ($n)$2"
        n=$((n + 1))
    done
    echo "$path"
}

extract_one() {
    local archive dir name work entries target
    archive=$(realpath "$1")
    dir=$(dirname "$archive")
    name=$(basename "$archive")
    name=$(sed -E 's/(\.tar)?\.[^.]+$//' <<< "$name")

    # Unpack aside so a failure leaves nothing behind
    work=$(mktemp -d "$dir/.extracting.XXXXXX") || return 1
    if ! bsdtar -xf "$archive" -C "$work" 2> /dev/null; then
        rm -rf "$work"
        return 1
    fi

    # One top-level item stays as it is; several get a folder named after the archive
    mapfile -t entries < <(find "$work" -mindepth 1 -maxdepth 1)
    if [[ ${#entries[@]} -eq 1 ]]; then
        local item ext=""
        item=$(basename "${entries[0]}")
        [[ -f ${entries[0]} && $item == ?*.* ]] && ext=".${item##*.}"
        target=$(unique_path "$dir/${item%"$ext"}" "$ext")
        mv "${entries[0]}" "$target" && rmdir "$work"
    else
        target=$(unique_path "$dir/$name" "")
        chmod 755 "$work"
        mv "$work" "$target"
    fi
}

extract() {
    local file done=0
    for file in "$@"; do
        if extract_one "$file"; then
            done=$((done + 1))
        else
            notify -u normal "Opening in File Roller" "$(basename "$file") could not be extracted directly."
            file-roller "$file" &
        fi
    done
    [[ $done -gt 0 ]] && notify "Extracted" "$done of $# archive(s)"
}

compress() {
    local format="" first dir base output names=() file
    if [[ ${1:-} == --as ]]; then
        format=$2
        shift 2
    else
        format=$(printf '%s\n' "${FORMATS[@]}" | rofi -dmenu -i -p "" -theme-str "$MENU_THEME entry { placeholder: \"Compress $# item(s) as...\"; }") || exit 0
    fi
    [[ -n $format ]] || exit 0

    first=$(realpath "$1")
    dir=$(dirname "$first")
    # One item names the archive after itself, several after their folder
    if [[ $# -eq 1 ]]; then
        base=$(basename "$first")
        [[ -f $first ]] && base=${base%.*}
    else
        base=$(basename "$dir")
    fi
    output=$(unique_path "$dir/$base" ".$format")

    for file in "$@"; do
        names+=("./$(basename "$file")")
    done
    if bsdtar -a -cf "$output" -C "$dir" -- "${names[@]}" 2> /dev/null; then
        notify "Compressed" "$(basename "$output")"
    else
        rm -f "$output"
        notify -u critical "Compression failed" "$(basename "$output")"
        return 1
    fi
}

# --- Actions ---
action=${1:-}
shift || true
case "$action" in
    extract) extract "$@" ;;
    compress) compress "$@" ;;
    *)
        echo "usage: ${0##*/} extract FILE... | compress [--as FORMAT] FILE..." >&2
        exit 1
        ;;
esac
