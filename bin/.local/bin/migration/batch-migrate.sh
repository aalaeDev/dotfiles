#!/bin/bash

# --- CONFIGURATION ---
# Add the relative paths (from your Home folder) that you want to migrate.
# Format: "PackageName:Path/To/Config"
APPS=(
    "btop:.config/btop"
    "cava:.config/cava"
    "fastfetch:.config/fastfetch"
    "fish:.config/fish"
    "grub:.config/grub"
    "gtk-3.0:.config/gtk-3.0"
    "gtk-4.0:.config/gtk-4.0"
    "hypr:.config/hypr"
    "kitty:.config/kitty"
    "matugen:.config/matugen"
    "nvim:.config/nvim"
    "qt5ct:.config/qt5ct"
    "qt6ct:.config/qt6ct"
    "rofi:.config/rofi"
    "swaync:.config/swaync"
    "waybar:.config/waybar"
    "xkb:.config/xkb"
)

DOTFILES_DIR="$HOME/dotfiles"
mkdir -p "$DOTFILES_DIR"

# --- THE LOOP ---
for entry in "${APPS[@]}"; do
    # Split the string into Package and Path
    PKG="${entry%%:*}"
    REL_PATH="${entry#*:}"

    echo "------------------------------------------"

    # Check if the source actually exists before moving
    if [ ! -e "$HOME/$REL_PATH" ]; then
        echo "Skipping: $HOME/$REL_PATH not found."
        continue
    fi

    echo "Migrating [$PKG] from ~/$REL_PATH..."

    # 1. Create structure in dotfiles
    mkdir -p "$DOTFILES_DIR/$PKG/$(dirname "$REL_PATH")"

    # 2. Move the file/folder
    mv "$HOME/$REL_PATH" "$DOTFILES_DIR/$PKG/$REL_PATH"

    # 3. Stow it back
    cd "$DOTFILES_DIR"
    stow -v --adopt "$PKG"
done

echo "------------------------------------------"
echo "Batch migration complete!"
