#!/bin/bash
# waybar-restart-failed.sh
mapfile -t failed_units < <(systemctl --failed --no-legend --plain | awk '{print $1}')

if [[ ${#failed_units[@]} -eq 0 ]]; then
    notify-send "Systemd" "No failed units to restart 🎉"
else
    for unit in "${failed_units[@]}"; do
        systemctl restart "$unit"
    done
    notify-send "Systemd" "Restarted ${#failed_units[@]} failed units"
fi

