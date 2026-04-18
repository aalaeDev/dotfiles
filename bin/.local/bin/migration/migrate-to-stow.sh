#!/bin/bash

# Usage: ./migrate.sh <package_name> <path_relative_to_home>
# Example: ./migrate.sh nvim .config/nvim

PKG=$1
REL_PATH=$2
DOTFILES_DIR="$HOME/dotfiles"

# Check if target actually exists
if [ ! -e "$HOME/$REL_PATH" ]; then
    echo "Error: $HOME/$REL_PATH does not exist."
    exit 1
fi

echo "Migrating $REL_PATH to $DOTFILES_DIR/$PKG..."

# 1. Prepare the structure in dotfiles
# We create the nested path so it matches exactly
mkdir -p "$DOTFILES_DIR/$PKG/$(dirname "$REL_PATH")"

# 2. Move the file/folder
# If it's a folder, we move the whole thing.
mv "$HOME/$REL_PATH" "$DOTFILES_DIR/$PKG/$REL_PATH"

# 3. Use Stow to link it back
cd "$DOTFILES_DIR"
stow -v --adopt "$PKG"

echo "Done! You can now see the link with: ls -l ~/$REL_PATH"
