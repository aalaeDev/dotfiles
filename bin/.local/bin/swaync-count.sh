#!/bin/bash

# Function to print the count and icon
print_count() {
    count=$(swaync-client -c)
    if [ "$count" -gt 0 ]; then
        # Icon for notifications present (solid bell icon)
        ICON=""
        # Output with count and icon
        echo "{\"text\": \"$count $ICON\", \"class\": \"has-notifications\"}"
    else
        # Icon for no notifications (regular bell icon)
        ICON=""
        # Output with just the icon
        echo "{\"text\": \"0 $ICON\", \"class\": \"no-notifications\"}"
    fi
}

# Check if swaync-client is running and subscribe to events if it is
if which swaync-client > /dev/null; then
    # Subscribe to events and print the count every time a notification is added or closed
    swaync-client -s | while read -r line; do
        print_count
    done &
    # Also print the count immediately when the script starts
    print_count
fi
