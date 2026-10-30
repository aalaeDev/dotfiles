#!/usr/bin/env bash

# Build the "Matugen" icon theme: Tela's folders recolored from the wallpaper palette.
# Everything else (apps, file types) is inherited from Tela unchanged.
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

sed -e "s/^Name=.*/Name=$THEME/" -e "s/^Inherits=.*/Inherits=$BASE,hicolor,Adwaita,breeze/" \
    "$BASE_DIR/index.theme" > "$build/index.theme"
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
