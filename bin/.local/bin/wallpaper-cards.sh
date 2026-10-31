#!/usr/bin/env bash

# Wallpaper cards for the rofi picker: a thumbnail with the real matugen palette and the
# resolution baked in, because rofi can't update a details panel when the selection moves.
#
#   wallpaper-cards.sh build          Build what's missing, prune stale cards
#   wallpaper-cards.sh list           Print rofi rows (name + card icon), in picker order
#   wallpaper-cards.sh path <file>    Print the card path of one wallpaper, building it if needed
#   wallpaper-cards.sh palette <file> [index]    Print a wallpaper's palette colors

# --- Configuration ---
WALL_DIR="$HOME/Pictures/Wallpapers/Desktop"
CACHE_DIR="$HOME/.cache/wallpaper-cards"
SIZE=340           # Keep in sync with element-icon in wallpaper_switcher.rasi
THUMB_HEIGHT=256
FONT="JetBrainsMono-NF-Medium"
FONT_BOLD="JetBrainsMono-NF-Bold"
SOURCE_INDEX=1     # Same source color wallset.sh applies by default

# --- Helpers ---
wallpapers() {
    find "$WALL_DIR" -maxdepth 1 -type f -regextype posix-extended -iregex '.*\.(jpe?g|png)' | sort
}

# Cached card of a wallpaper; the name changes with the file, so edits rebuild it
card_path() {
    local name
    name=$(stat -c '%n-%Y-%s' "$1")
    echo "$CACHE_DIR/${name##*/}.png"
}

# One find for every wallpaper, because this runs each time the picker opens: "<format>" per file
scan() {
    find "$WALL_DIR" -maxdepth 1 -type f -regextype posix-extended -iregex '.*\.(jpe?g|png)' -printf "$1" | LC_ALL=C sort
}

# "primary secondary tertiary surface_container on_surface surface" for a wallpaper
palette() {
    local json
    json=$(matugen image "$1" --source-color-index "${2:-$SOURCE_INDEX}" --dry-run --json hex 2> /dev/null) \
        || json=$(matugen image "$1" --source-color-index 0 --dry-run --json hex 2> /dev/null) \
        || return 1
    jq -r '.colors | [.primary, .secondary, .tertiary, .surface_container, .on_surface, .surface]
        | map(.default.color) | join(" ")' <<< "$json"
}

# Short label for a resolution: 4K, 2K, HD or the real size, plus a tag for ultrawides
resolution_label() {
    local w="$1" h="$2" label
    case "$w" in
        7680) label="8K" ;;
        3840) label="4K" ;;
        2560) label="2K" ;;
        1920) label="HD" ;;
        *)    label="${w}×${h}" ;;
    esac
    (( w * 10 / h >= 21 )) && label+=" · Wide"
    echo "$label"
}

build_card() {
    local file="$1" card size w h name label
    card=$(card_path "$file")
    local primary secondary tertiary container on_surface surface
    read -r primary secondary tertiary container on_surface surface < <(palette "$file")
    [[ -n "$primary" ]] || return 1

    size=$(magick identify -ping -format '%w %h' "$file[0]") || return 1
    read -r w h <<< "$size"
    name=$(basename "${file%.*}")
    (( ${#name} > 14 )) && name="${name:0:13}…"
    label=$(resolution_label "$w" "$h")

    # Everything sits on the wallpaper's own surface color: the card previews its theme
    local args=(
        -define "jpeg:size=$(( SIZE * 2 ))x$(( THUMB_HEIGHT * 2 ))" "$file[0]"
        -thumbnail "${SIZE}x${THUMB_HEIGHT}^" -gravity center -extent "${SIZE}x${THUMB_HEIGHT}"
        -background "$surface" -gravity north -extent "${SIZE}x${SIZE}" -gravity northwest
    )

    # Swatches run edge to edge inside a 14px margin, with the source colors first
    local x=14 y=$(( THUMB_HEIGHT + 14 )) width=56 color
    for color in "$primary" "$secondary" "$tertiary" "$container" "$on_surface"; do
        args+=(-fill "$color" -draw "roundrectangle $x,$y $(( x + width )),$(( y + 22 )) 7,7")
        x=$(( x + width + 8 ))
    done

    args+=(
        -fill "$on_surface" -font "$FONT_BOLD" -pointsize 16 -annotate "+14+$(( THUMB_HEIGHT + 50 ))" "$name"
        -gravity northeast -fill "$primary" -font "$FONT" -pointsize 12 -annotate "+14+$(( THUMB_HEIGHT + 53 ))" "$label"
        \( -size "${SIZE}x${SIZE}" xc:none -fill white -draw "roundrectangle 0,0 $(( SIZE - 1 )),$(( SIZE - 1 )) 18,18" \)
        -gravity center -compose DstIn -composite -strip
    )

    # A temp file first, so a killed build never leaves half a card in the cache
    magick "${args[@]}" "$card.tmp.png" && mv "$card.tmp.png" "$card"
}

# Cards that should exist, sorted by path, with their wallpaper: "<card><TAB><wallpaper>"
expected_cards() {
    scan "$CACHE_DIR/%f-%Ts-%s.png\t%p\n"
}

missing_cards() {
    LC_ALL=C join -t $'\t' -v 1 <(expected_cards) <(find "$CACHE_DIR" -maxdepth 1 -name '*.png' | LC_ALL=C sort) | cut -f 2
}

prune_cards() {
    LC_ALL=C comm -13 <(expected_cards | cut -f 1 | LC_ALL=C sort) \
        <(find "$CACHE_DIR" -maxdepth 1 -name '*.png' | LC_ALL=C sort) | tr '\n' '\0' | xargs -0 -r rm -f
}

# Build in parallel; slow enough the first time to be worth a progress notification
build_all() {
    local missing total done=0 _
    mkdir -p "$CACHE_DIR"
    prune_cards
    missing=$(missing_cards)
    [[ -z "$missing" ]] && return 0
    total=$(wc -l <<< "$missing")

    while read -r _; do
        done=$(( done + 1 ))
        notify-send -a "Wallpapers" -i preferences-desktop-wallpaper -u low \
            -h string:x-canonical-private-synchronous:wallpaper-cards \
            -h "int:value:$(( done * 100 / total ))" \
            "Preparing wallpapers" "$done of $total"
    done < <(tr '\n' '\0' <<< "$missing" | xargs -0 -P "$(nproc)" -I{} "$0" build-one {})
}

# --- Main ---
case "$1" in
    build)
        build_all
        ;;
    build-one)
        build_card "$2"
        echo "$2"
        ;;
    list)
        scan "%f\000icon\037$CACHE_DIR/%f-%Ts-%s.png\n"
        ;;
    palette)
        palette "$2" "$3"
        ;;
    path)
        card=$(card_path "$2")
        mkdir -p "$CACHE_DIR"
        [[ -f "$card" ]] || build_card "$2"
        echo "$card"
        ;;
    *)
        echo "Usage: ${0##*/} build|list|path <file>" >&2
        exit 1
        ;;
esac
