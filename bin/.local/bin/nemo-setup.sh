#!/usr/bin/env bash

# Apply Nemo preferences. They live in dconf, which stow can't link; re-run after editing.

set -euo pipefail

# --- Actions ---
# "Open in Terminal"
gsettings set org.cinnamon.desktop.default-applications.terminal exec kitty
gsettings set org.cinnamon.desktop.default-applications.terminal exec-arg ''

# Quieter icon view: size under the name, the rest on hover
gsettings set org.nemo.icon-view captions "['size', 'none', 'none']"
gsettings set org.nemo.preferences tooltips-in-icon-view true
gsettings set org.nemo.preferences tooltips-show-mod-date true
gsettings set org.nemo.preferences date-format informal

# Less chrome: tapping Alt brings the menu bar back
gsettings set org.nemo.preferences disable-menu-warning true
gsettings set org.nemo.window-state start-with-menu-bar false
gsettings set org.nemo.preferences show-show-thumbnails-toolbar false

# Our Extract Here and Compress actions replace File Roller's duplicates
gsettings set org.nemo.plugins disabled-extensions "['nemo-fileroller']"
