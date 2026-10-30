#!/usr/bin/env bash

# Install the system-level configs in this package (copied, not stowed: they live
# under /etc and must not depend on links into $HOME). Re-run after editing them.
#
#   ./system/install.sh

set -euo pipefail

# --- Configuration ---
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES=(zram-generator earlyoom)

# --- Actions ---
echo ":: Installing packages: ${PACKAGES[*]}"
sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"

echo ":: Copying configs to /etc"
# Packages first, then our files, so they replace the package defaults
while IFS= read -r -d '' file; do
    target="/${file#"$SRC"/}"
    sudo install -Dm644 "$file" "$target"
    echo "   $target"
done < <(find "$SRC/etc" -type f -print0)

echo ":: Applying"
sudo systemctl daemon-reload                      # zram-generator creates dev-zram0.swap
sudo systemctl start dev-zram0.swap
sudo sysctl --quiet --system
sudo systemd-tmpfiles --create /etc/tmpfiles.d/memory.conf
sudo systemctl enable --now earlyoom
sudo systemctl restart earlyoom                   # pick up /etc/default/earlyoom if it was running

echo ":: Done"
swapon --show
