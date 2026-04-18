#!/bin/bash

# --- CONFIGURATION ---
# Use the same list as your migration script
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

BACKUP_DIR="$HOME/.config.old"
mkdir -p "$BACKUP_DIR"

echo "Moving original configs to $BACKUP_DIR..."

# --- THE LOOP ---
for entry in "${APPS[@]}"; do
    # Get the path after the colon (e.g., .config/nvim)
    REL_PATH="${entry#*:}"

    # Check if a REAL directory (not a symlink) exists at the target
    if [ -d "$HOME/$REL_PATH" ] && [ ! -L "$HOME/$REL_PATH" ]; then
        echo "Backing up: ~/$REL_PATH"

        # Create subdirectories in backup to match structure
        mkdir -p "$BACKUP_DIR/$(dirname "$REL_PATH")"

        # Move the real folder to the backup
        mv "$HOME/$REL_PATH" "$BACKUP_DIR/$REL_PATH"
    elif [ -L "$HOME/$REL_PATH" ]; then
        echo "Skipping: ~/$REL_PATH is already a symlink."
    else
        echo "Skipping: ~/$REL_PATH does not exist."
    fi
done

echo "------------------------------------------"
echo "Backup complete. Your .config is ready for 'stow *'."
