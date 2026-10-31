#!/usr/bin/env bash

# Wallpaper picker: a filmstrip of cards showing each wallpaper's theme, then matugen applies it.
#
#   wallset.sh            Open the picker
#   wallset.sh <image>    Apply an image directly (Nemo's "Set as Wallpaper")
#   wallset.sh --banner   Only rebuild the rofi hero banner from the current wallpaper

# --- Configuration ---
WALL_DIR="$HOME/Pictures/Wallpapers/Desktop"
CARDS="$HOME/.local/bin/wallpaper-cards.sh"
BANNER="$HOME/.cache/rofi/banner.png"
THEME="$HOME/.config/rofi/wallpaper_switcher.rasi"
COLORS="$HOME/.config/rofi/colors.rasi"
SOURCE_INDEX=1

# --- Helpers ---
current_wallpaper() {
    awww query 2> /dev/null | sed -n 's/.*image: //p' | head -n 1
}

escape() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' <<< "$1"
}

# Pango swatches, one per color given
swatches() {
    local color line=""
    for color in "$@"; do
        line+="<span foreground='$color'>●</span> "
    done
    echo "${line% }"
}

# A value out of the generated rofi colors, by name
rofi_color() {
    sed -n "s/^ *$1: *\(#[0-9a-fA-F]*\);.*/\1/p" "$COLORS"
}

# A wide crop for the top of the rofi menus, as wide as any hero is at its height. Mostly the
# wallpaper's own colors: only the bottom, behind the search, is darkened a little.
build_banner() {
    mkdir -p "${BANNER%/*}"
    # Walker's theme loads it by a relative path
    ln -sf "$BANNER" "$HOME/.config/walker/themes/rice/banner.png"
    magick -define jpeg:size=2856x680 "$1[0]" -thumbnail '1428x340^' -gravity center -extent 1428x340 \
        \( -size 1428x340 gradient:'#ffffff-#a8a8a8' \) -compose Multiply -composite \
        -strip "$BANNER.tmp.png" && mv "$BANNER.tmp.png" "$BANNER"
}

apply() {
    local file="$1" index="${2:-$SOURCE_INDEX}" card

    # Big images take a while to convert: don't make the theme wait for them
    magick "$file[0]" "$HOME/dotfiles/hypr/.config/hypr/assets/current-wallpaper.jpg" &
    build_banner "$file" &

    matugen image "$file" --source-color-index "$index" || matugen image "$file" --source-color-index 0 || {
        notify-send -a "Wallpapers" -u critical "Wallpaper not applied" "matugen failed on ${file##*/}"
        return 1
    }
    wait

    card=$("$CARDS" path "$file")
    notify-send -a "Wallpapers" -i "$card" "Theme updated" \
        "$(escape "${file##*/}")  $(swatches "$(rofi_color selected)" "$(rofi_color active)" "$(rofi_color tertiary)")"
}

# The second step of Alt+t: every source color of a wallpaper, with the palette it would produce
pick_variant() {
    local file="$1" tmp i=0 color choice rows=() colors
    tmp=$(mktemp -d)
    mapfile -t colors < <(matugen image "$file" --show-source-colors --dry-run 2> /dev/null)
    for color in "${colors[@]}"; do
        "$CARDS" palette "$file" "$i" > "$tmp/$i" &
        i=$(( i + 1 ))
    done
    wait

    for i in "${!colors[@]}"; do
        read -r -a palette < "$tmp/$i"
        rows+=("<span foreground='${colors[$i]}'>󰝤</span>  Source color $(( i + 1 ))   <span foreground='$(rofi_color foreground-dim)'>${colors[$i]}</span>     $(swatches "${palette[@]:0:3}")")
    done
    rm -rf "$tmp"

    choice=$(printf '%s\n' "${rows[@]}" | rofi -dmenu -i -markup-rows -format i -p "Theme" \
        -selected-row "$SOURCE_INDEX" -mesg "Pick the accent for <b>$(escape "${file##*/}")</b>" \
        -theme-str "window { width: 560px; } listview { lines: ${#rows[@]}; }") || return 0
    [[ -n "$choice" ]] && apply "$file" "$choice"
}

pick() {
    # A second press closes the picker instead of stacking another one
    pkill -x rofi && exit 0

    "$CARDS" build

    local rows current name row total size header choice code
    rows=$(mktemp)
    trap 'rm -f "$rows"' RETURN
    "$CARDS" list > "$rows"
    current=$(current_wallpaper)
    name=${current##*/}
    row=$(tr '\0' '\t' < "$rows" | awk -F'\t' -v name="$name" '$1 == name { print NR; exit }')
    total=$(wc -l < "$rows")

    local accent dim fg key
    accent=$(rofi_color selected)
    dim=$(rofi_color foreground-dim)
    fg=$(rofi_color foreground)
    key() { echo "<span foreground='$accent'><b>$1</b></span> <span foreground='$dim'>$2</span>"; }

    header="<span foreground='$accent'>󰸉</span>  <span foreground='$fg'><b>$(escape "${name:-No wallpaper}")</b></span>"
    if [[ -f "$current" ]]; then
        size=$(magick identify -ping -format '%wx%h' "$current[0]" 2> /dev/null)
        header+="   <span foreground='$dim'>${size/x/×}</span>"
        [[ -n "$row" ]] && header+="   <span foreground='$dim'>$row/$total</span>"
    fi
    header+="     $(swatches "$accent" "$(rofi_color active)" "$(rofi_color tertiary)" "$(rofi_color surface-container-high)" "$fg")"
    header+="     $(key Enter apply)   $(key Alt+r random)   $(key Alt+t accent)   $(key Esc close)"

    choice=$(rofi -dmenu -i -no-custom -show-icons -p "" -theme "$THEME" \
        -selected-row "$(( ${row:-1} - 1 ))" -mesg "$header" \
        -kb-row-left Left -kb-row-right Right -kb-move-char-back Control+b -kb-move-char-forward Control+f \
        -kb-custom-1 "Alt+r" -kb-custom-2 "Alt+t" < "$rows")
    code=$?

    case "$code" in
        0)  apply "$WALL_DIR/$choice" ;;
        10) apply "$(find "$WALL_DIR" -maxdepth 1 -type f -regextype posix-extended -iregex '.*\.(jpe?g|png)' \
                ! -path "$current" | shuf -n 1)" ;;
        11) pick_variant "$WALL_DIR/$choice" ;;
    esac
}

# --- Main ---
case "$1" in
    "")       pick ;;
    --banner) build_banner "$(current_wallpaper)" ;;
    *)        apply "$(realpath "$1")" ;;
esac
