#!/bin/bash

# Define the base directory (e.g., in your home directory)
SCREENSHOTS_DIR="$HOME/Pictures/Screenshots"

# Get the current month and year for the folder name
MONTH_YEAR=$(date +%Y-%m)

# Get the full timestamp including Year, Month, Day, Hour, Minute, and Second
# This ensures a unique filename for every screenshot.
FULL_TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)

# Define the full path for the folder
SAVE_PATH="$SCREENSHOTS_DIR/$MONTH_YEAR"

# Hyprshot takes the folder (-o) and the file name (-f) separately
FILE_NAME="$FULL_TIMESTAMP.png"

# Create the directory if it doesn't exist
mkdir -p "$SAVE_PATH"

# Check the first argument passed to the script
MODE="$1"

# All hyprshot commands here use --copy and --save, which is the desired behavior

if [ "$MODE" = "region" ]; then
    # Launch Hyprshot selection tool (similar to flameshot gui)
    echo "Starting Hyprshot in interactive selection mode..."
    hyprshot -m region -o "$SAVE_PATH" -f "$FILE_NAME" -z

elif [ "$MODE" = "output" ]; then
    # Capture the focused monitor right away (plain "-m output" waits for a click to pick one)
    echo "Capturing the active single screen..."
    hyprshot -m output -m active -o "$SAVE_PATH" -f "$FILE_NAME"

elif [ "$MODE" = "window" ]; then
    # Capture the selected window (Hyprshot prompts for selection)
    echo "Starting Hyprshot to select a window for capture..."
    hyprshot -m window -o "$SAVE_PATH" -f "$FILE_NAME" -z

else
    # Handle incorrect or missing argument
    echo "Error: Invalid or missing argument."
    echo "Usage: $0 [gui|full|screen|window]"
    echo "  region: Launches the interactive selection tool."
    echo "  output: Captures only the active monitor."
    echo "  window: Captures a selected window."
    exit 1
fi
