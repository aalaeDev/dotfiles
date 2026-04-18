#!/bin/bash

# Define the base directory (e.g., in your home directory)
SCREENSHOTS_DIR="Pictures/Screenshots"

# Get the current month and year for the folder name
MONTH_YEAR=$(date +%Y-%m)

# Get the full timestamp including Year, Month, Day, Hour, Minute, and Second
# This ensures a unique filename for every screenshot.
FULL_TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)

# Define the full path for the folder
SAVE_PATH="$SCREENSHOTS_DIR/$MONTH_YEAR"

# Define the full file path and name prefix using the timestamp
# Hyprshot uses the path directly and will append the extension (e.g., .png)
FULL_FILE_PATH="$SAVE_PATH/$FULL_TIMESTAMP.png"

# Create the directory if it doesn't exist
mkdir -p "$SAVE_PATH"

# Check the first argument passed to the script
MODE="$1"

# All hyprshot commands here use --copy and --save, which is the desired behavior

if [ "$MODE" = "region" ]; then
    # Launch Hyprshot selection tool (similar to flameshot gui)
    echo "Starting Hyprshot in interactive selection mode..."
    hyprshot -m region -f "$FULL_FILE_PATH" -z

elif [ "$MODE" = "output" ]; then
    # Capture only the single active screen (where the cursor is)
    echo "Capturing the active single screen..."
    hyprshot -m output -f "$FULL_FILE_PATH" -z

elif [ "$MODE" = "window" ]; then
    # Capture the selected window (Hyprshot prompts for selection)
    echo "Starting Hyprshot to select a window for capture..."
    hyprshot -m window -f "$FULL_FILE_PATH" -z

else
    # Handle incorrect or missing argument
    echo "Error: Invalid or missing argument."
    echo "Usage: $0 [gui|full|screen|window]"
    echo "  region: Launches the interactive selection tool."
    echo "  output: Captures only the active monitor."
    echo "  window: Captures a selected window."
    exit 1
fi
