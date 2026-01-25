#!/usr/bin/env bash

# --- CONFIGURATION ---
# OpenRGB
PROFILE_OFF="off"
PROFILE_ON="on"
# CoolerControl API settings
API_URL="http://localhost:11987"
MODE_ON="5fd7eba6-b519-4cc6-8f21-a239357c8bda"
MODE_OFF="1b781fa9-b1dc-4467-bd52-e04c981c6dee"
# ---------------------

apply_mode() {
    local mode_id=$1
    echo "Applying CoolerControl Mode: $mode_id"
    curl -s -X POST "$API_URL/modes/apply" \
         -H "Content-Type: application/json" \
         -d "{\"id\": \"$mode_id\"}" > /dev/null
}

lights_off() {
    echo "Turning Lights Off"

    # 1. Apply CoolerControl "Off" Mode
    apply_mode "$MODE_OFF"

    # 2. Kill RGB
    echo "Applying OpenRGB Profile: $PROFILE_OFF"
    openrgb --profile "$PROFILE_OFF" > /dev/null 2>&1
}

lights_on() {
    echo "Turning Lights Back On"

    # 1. Apply CoolerControl "On" Mode
    apply_mode "$MODE_ON"

    # 2. Restore RGB
    echo "Applying OpenRGB Profile: $PROFILE_ON"
    openrgb --profile "$PROFILE_ON" > /dev/null 2>&1
}


case "$1" in
    off)
        lights_off
        ;;
    on)
        lights_on
        ;;
    -h|--help|*)
        echo "Usage: $(basename "$0") [on|off]"
        echo ""
        echo "Commands:"
        echo "  off    Kill RGB and apply CoolerControl '$MODE_OFF'"
        echo "  on     Restore RGB and apply CoolerControl '$MODE_ON'"
        exit 0
        ;;
esac
