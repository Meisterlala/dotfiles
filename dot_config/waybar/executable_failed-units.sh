#!/bin/bash
# waybar-failed-units.sh
# Show both system and user failed services in one list

# Ensure we can talk to your Hyprland notif daemon
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

failed=$( { systemctl --failed --no-legend; systemctl --user --failed --no-legend; } 2>/dev/null )

if [[ -z "$failed" ]]; then
    notify-send "Systemd" "No failed units 🎉"
else
    notify-send "Failed systemd units" "$failed"
fi

