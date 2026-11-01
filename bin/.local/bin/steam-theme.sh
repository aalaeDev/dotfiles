#!/bin/sh
# Applies the matugen palette to Steam through Adwaita-for-Steam (matugen post_hook), then
# restarts a running client to show it, unless a game is up: Steam can't reload its skin.
# Pinned, so a wallpaper change never runs unreviewed code; bump the commit to update the skin
dir="$HOME/.local/share/adwaita-steam"
commit=1e92107

[ -d "$HOME/.steam/steam/steamui" ] || exit 0
if [ ! -d "$dir/repo" ]; then
    git clone --quiet https://github.com/tkashkin/Adwaita-for-Steam "$dir/repo" \
        && git -C "$dir/repo" checkout --quiet "$commit" \
        || { rm -rf "$dir/repo"; exit 1; }
fi
(cd "$dir/repo" && python3 install.py --target default --color-scheme dark \
    --accent-color theme --font system --custom-css "$dir/matugen.css") || exit 1

pgrep -x steam > /dev/null || exit 0
pgrep -f '[r]eaper SteamLaunch' > /dev/null && exit 0
# Reopen it as it was: with a window, or quietly in the tray
hyprctl clients -j | jq -e '.[] | select(.class == "steam")' > /dev/null && flags='' || flags='-silent'
# Detached, so matugen doesn't wait on it; the lock merges quick wallpaper changes
setsid -f flock -no "/run/user/$(id -u)/steam-theme.lock" sh -c '
    /usr/bin/steam -shutdown
    for _ in $(seq 60); do
        pgrep -x steam > /dev/null || { setsid -f /usr/bin/steam "$@"; exit; }
        sleep 1
    done
' sh $flags > /dev/null 2>&1 < /dev/null
