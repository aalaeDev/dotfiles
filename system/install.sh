#!/usr/bin/env bash

# Install the system-level configs in this package (copied, not stowed: they live
# under /etc and /opt and must not depend on links into $HOME). Re-run after editing them.
#
#   ./system/install.sh

set -euo pipefail

# --- Configuration ---
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES=(zram-generator earlyoom power-profiles-daemon)

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

echo ":: Installing autoconfig (live theme reload) into Zen and Betterbird"
# Kept in /usr/local/share too: the pacman hook copies it back after app updates
SHARE=/usr/local/share/dotfiles/autoconfig
sudo rm -rf /usr/local/share/dotfiles/zen-autoconfig     # earlier location
while IFS= read -r -d '' file; do
    relative="${file#"$SRC"/autoconfig/}"
    sudo install -Dm644 "$file" "$SHARE/$relative"
    for app in /opt/zen-browser-bin /opt/betterbird; do
        [[ -d $app ]] || continue
        sudo install -Dm644 "$file" "$app/$relative"
        echo "   $app/$relative"
    done
done < <(find "$SRC/autoconfig" -type f -print0)
sudo rm -f /etc/pacman.d/hooks/zen-autoconfig.hook       # replaced by dotfiles-autoconfig.hook

echo ":: Patching OnlyOffice editors for local themes"
# The pacman hook runs this again after app updates
sudo sh /etc/pacman.d/scripts/onlyoffice-theme-patch.sh

echo ":: Applying"
sudo systemctl daemon-reload                      # zram-generator creates dev-zram0.swap
sudo systemctl start dev-zram0.swap
sudo sysctl --quiet --system
sudo systemd-tmpfiles --create /etc/tmpfiles.d/memory.conf
sudo systemctl enable --now earlyoom
sudo systemctl enable --now power-profiles-daemon
sudo systemctl restart earlyoom                   # pick up /etc/default/earlyoom if it was running

echo ":: Done"
swapon --show
