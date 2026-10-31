#!/bin/sh
# Hands a new palette to open OnlyOffice pages, which poll this file (matugen post_hook)
live="/run/user/$(id -u)/onlyoffice-matugen.js"
{
    printf 'window.__matugenTheme('
    cat "$HOME/.local/share/onlyoffice/desktopeditors/uithemes/matugen.json"
    printf ')'
} > "$live.tmp" && mv "$live.tmp" "$live"
