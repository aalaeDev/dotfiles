#!/usr/bin/env bash

# Sourced by scripts that need personal settings: loads the gitignored ~/dotfiles/.env.

# --- Configuration ---
RICE_ENV="${RICE_ENV:-$HOME/dotfiles/.env}"
RICE_CACHE="${RICE_CACHE:-$HOME/.cache/rice}"

# --- Actions ---
CITY="" COUNTRY="" ATHAN_METHOD=3 ATHAN_LATE_MINUTES=30 WEATHER_UNITS=celsius
# shellcheck source=/dev/null
[[ -r "$RICE_ENV" ]] && source "$RICE_ENV"
mkdir -p "$RICE_CACHE"
