#!/usr/bin/env bash

INTERNAL="eDP-1"
EXTERNAL="HDMI-2"

# Helper to check if monitor exists
monitor_exists() {
    bspc query -M --names | grep -qx "$1"
}

# Helper to check if desktop exists
desktop_exists() {
    bspc query -D --names | grep -qx "$1"
}

if xrandr -q | grep -q "^$EXTERNAL connected"; then
    # External monitor connected: set layout and move desktop 9 if needed
    xrandr --output "$INTERNAL" --primary --output "$EXTERNAL" --auto --right-of "$INTERNAL"

    if ! bspc query -D -m "$EXTERNAL" --names | grep -qx 9; then
        bspc desktop 9 --to-monitor "$EXTERNAL"
    fi

    # Remove default desktop if exists
    if desktop_exists Desktop; then
        bspc desktop Desktop --remove
    fi

else
    # External monitor disconnected: turn off external and reset desktops
    xrandr --output "$EXTERNAL" --off

    # Add default desktop to external if monitor exists
    if monitor_exists "$EXTERNAL"; then
        if ! desktop_exists Desktop; then
            bspc monitor "$EXTERNAL" -a Desktop
        fi
    fi

    # Move desktop 9 back if it exists
    if desktop_exists 9; then
        bspc desktop 9 --to-monitor "$INTERNAL"
    fi

    # Remove default desktop if exists
    if desktop_exists Desktop; then
        bspc desktop Desktop --remove
    fi

    # Reorder desktops on internal monitor (no need to check monitor existence)
    bspc monitor "$INTERNAL" -o 1 2 3 4 5 6 7 8 9 text code browser notes mail

    # Remove external monitor if it exists
    if monitor_exists "$EXTERNAL"; then
        bspc monitor "$EXTERNAL" --remove
    fi
fi

