#!/usr/bin/env bash

# Build the "Matugen" icon theme: Tela's folders recolored from the wallpaper palette.
# Adds tinted status icons (battery, dialogs) for notifications. Apps and file types come from Tela unchanged.
# Run by matugen, which writes the palette to ~/.cache/icon-colors.sh first.

set -euo pipefail

# --- Configuration ---
BASE=Tela-circle-dracula-dark
BASE_DIR="/usr/share/icons/$BASE"
THEME=Matugen
ICONS="$HOME/.local/share/icons"
SIZES=(16 22 24 scalable)

# --- Actions ---
# shellcheck source=/dev/null
source "$HOME/.cache/icon-colors.sh"

# Build beside the live theme, then swap, so apps never see it half written
build=$(mktemp -d "$ICONS/.$THEME.XXXXXX")
trap 'rm -rf "$build"' EXIT

for size in "${SIZES[@]}"; do
    mkdir -p "$build/$size"
    cp -rL "$BASE_DIR/$size/places" "$build/$size/"
done
# Tela's other folder colors go unused
find "$build" -name '*-*' -regextype posix-extended \
    -regex '.*/(black|blue|brown|custom|cyan|green|grey|magenta|orange|pink|purple|red|teal|violet|yellow)-[^/]*' -delete

# Folder body, tab, glyphs; the small sizes use #5294e2 and #aaaaaa
find "$build" -name '*.svg' -exec sed -i \
    -e "s/#44475a/$CONTAINER/gI" \
    -e "s/#bd93f9/$PRIMARY/gI" \
    -e "s/#333333/$ON_CONTAINER/gI" \
    -e "s/#5294e2/$PRIMARY/gI" \
    -e "s/#aaaaaa/$ON_SURFACE/gI" {} +

# Our own status icons: tinted chips that replace Tela's under the standard names, for every app
mkdir -p "$build/rice/status"
tint() {
    sed -e "s/ON_CONTAINER/$ON_CONTAINER/g" -e "s/CONTAINER/$CONTAINER/g" -e "s/ERROR/$ERROR/g"
}
for icon in "$HOME"/.config/matugen/icons/*.svg; do
    tint < "$icon" > "$build/rice/status/${icon##*/}"
done

# name, level %, charging (0/1). Symbolic names drop the chip: GTK paints those as a flat mask.
battery_icon() {
    local width=$(( $2 * 18 / 100 )) color=ON_CONTAINER body bolt=""
    (( $2 <= 20 && ! $3 )) && color=ERROR
    (( $3 )) && bolt='<path fill="CONTAINER" stroke="ON_CONTAINER" stroke-width="1" d="M25 16 18 25h5l-2 7 8-10h-5z"/>'
    body="<rect x=\"10\" y=\"16\" width=\"25\" height=\"16\" rx=\"4\" fill=\"none\" stroke=\"ON_CONTAINER\" stroke-width=\"2.4\"/><rect x=\"36.5\" y=\"21\" width=\"2.5\" height=\"6\" rx=\"1\" fill=\"ON_CONTAINER\"/><rect x=\"13.5\" y=\"19.5\" width=\"$width\" height=\"9\" rx=\"1.5\" fill=\"$color\"/>$bolt"
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 48 48\"><rect width=\"48\" height=\"48\" rx=\"12\" fill=\"CONTAINER\"/>$body</svg>" \
        | tint > "$build/rice/status/$1.svg"
    echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 48 48\">$body</svg>" \
        | sed -e 's/fill="CONTAINER"/fill="none"/g' | tint > "$build/rice/status/$1-symbolic.svg"
}
for level in 0 10 20 30 40 50 60 70 80 90 100; do
    battery_icon "battery-level-$level" "$level" 0
    battery_icon "battery-level-$level-charging" "$level" 1
done
for pair in empty:0 caution:10 low:20 good:60 full:100; do
    battery_icon "battery-${pair%:*}" "${pair#*:}" 0
    battery_icon "battery-${pair%:*}-charging" "${pair#*:}" 1
done
battery_icon battery-full-charged 100 1
battery_icon battery-level-100-charged 100 1

sed -e "s/^Name=.*/Name=$THEME/" -e "s/^Inherits=.*/Inherits=$BASE,hicolor,Adwaita,breeze/" \
    -e 's|^Directories=|Directories=rice/status,|' "$BASE_DIR/index.theme" > "$build/index.theme"
printf '\n[rice/status]\nSize=48\nMinSize=8\nMaxSize=512\nType=Scalable\nContext=Status\n' >> "$build/index.theme"
chmod 755 "$build"

rm -rf "${ICONS:?}/$THEME"
mv "$build" "$ICONS/$THEME"
trap - EXIT

# Running apps cache icons until the theme name changes
if [[ $(gsettings get org.gnome.desktop.interface icon-theme) == "'$THEME'" ]]; then
    gsettings set org.gnome.desktop.interface icon-theme "$BASE"
    sleep 0.3
fi
gsettings set org.gnome.desktop.interface icon-theme "$THEME"
