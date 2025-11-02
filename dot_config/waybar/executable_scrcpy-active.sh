#!/bin/bash
set -Eeuo pipefail

# Check if scrcpy is running and output status for waybar
pid=$(pgrep -x scrcpy | head -1)
if [ -n "$pid" ]; then
    # Kill it!
    if [ "${1-}" = "--kill" ]; then
        kill "$pid"
        echo ""
        exit 0
    fi

    # Get the command line arguments of the scrcpy process
    scrcpy_cmd=$(ps -p "$pid" -o args=)


    if echo "$scrcpy_cmd" | grep -q -- "--video-source=camera"; then
        echo "scrcpy  "
    else
        echo "scrcpy "
    fi
else
    echo ""
fi
