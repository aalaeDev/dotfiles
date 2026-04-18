#!/bin/bash

killall -9 waybar

swaync-client -R
swaync-client --reload-css

waybar &
