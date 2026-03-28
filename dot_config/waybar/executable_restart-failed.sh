#!/usr/bin/env bash
# Restart failed system and user services.

set -u

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

refresh_waybar() {
  pkill -RTMIN+10 waybar >/dev/null 2>&1 || true
}

mapfile -t failed_system_services < <(systemctl --failed --type=service --no-legend --plain 2>/dev/null | awk '{print $1}')
mapfile -t failed_user_services < <(systemctl --user --failed --type=service --no-legend --plain 2>/dev/null | awk '{print $1}')

total=$(( ${#failed_system_services[@]} + ${#failed_user_services[@]} ))
if (( total == 0 )); then
  notify-send "Systemd" "No failed services to restart"
  refresh_waybar
  exit 0
fi

restarted=0
failed=()

for unit in "${failed_system_services[@]}"; do
  if systemctl restart "$unit" >/dev/null 2>&1; then
    ((restarted++))
  else
    failed+=("system:$unit")
  fi
done

for unit in "${failed_user_services[@]}"; do
  if systemctl --user restart "$unit" >/dev/null 2>&1; then
    ((restarted++))
  else
    failed+=("user:$unit")
  fi
done

if (( ${#failed[@]} == 0 )); then
  notify-send "Systemd" "Restarted ${restarted}/${total} failed services"
else
  details=$(printf '%s\n' "${failed[@]}")
  notify-send "Systemd" "Restarted ${restarted}/${total} failed services\nSome restarts failed" "$details"
fi

refresh_waybar
