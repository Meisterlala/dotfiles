#!/bin/bash
# Toggle hypridle inhibit state

INHIBIT_FILE="/tmp/hypridle-inhibit.lock"
ACTION="${1:-toggle}"

case "$ACTION" in
    on)
        # Enable inhibit
        if [ ! -f "$INHIBIT_FILE" ]; then
            systemd-inhibit --what=idle --who="SwayNC" --why="Toggle activated" --mode=block sleep infinity &
            echo $! > "$INHIBIT_FILE"
        fi
        ;;
    off)
        # Disable inhibit
        if [ -f "$INHIBIT_FILE" ]; then
            PID=$(cat "$INHIBIT_FILE")
            kill "$PID" 2>/dev/null
            rm "$INHIBIT_FILE"
        fi
        ;;
    toggle)
        # Toggle state
        if [ -f "$INHIBIT_FILE" ]; then
            "$0" off
        else
            "$0" on
        fi
        ;;
esac
