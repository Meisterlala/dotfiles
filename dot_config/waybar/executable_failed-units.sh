#!/bin/bash
# waybar-failed-units.sh
failed=$(systemctl --failed --no-legend --plain)
if [[ -z "$failed" ]]; then
    notify-send "Systemd" "No failed units 🎉"
else
    notify-send "Failed systemd units" "$failed"
fi

