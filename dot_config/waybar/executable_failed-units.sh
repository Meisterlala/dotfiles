#!/usr/bin/env bash
# Waybar module helper for failed systemd services.

set -u

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

refresh_waybar() {
  pkill -RTMIN+10 waybar >/dev/null 2>&1 || true
}

mapfile -t failed_system_services < <(systemctl --failed --type=service --no-legend --plain 2>/dev/null | awk '{print $1}')
mapfile -t failed_user_services < <(systemctl --user --failed --type=service --no-legend --plain 2>/dev/null | awk '{print $1}')

system_count=${#failed_system_services[@]}
user_count=${#failed_user_services[@]}
total=$(( system_count + user_count ))

build_tooltip() {
  local tooltip=""
  local section=""

  join_lines() {
    local out=""
    local item
    for item in "$@"; do
      [[ -n "$out" ]] && out+=$'\n'
      out+="$item"
    done
    printf '%s' "$out"
  }

  if (( system_count > 0 )); then
    section=$(join_lines "${failed_system_services[@]}")
    tooltip+="System failed services (${system_count}):"
    tooltip+=$'\n'
    tooltip+="$section"
  fi

  if (( user_count > 0 )); then
    section=$(join_lines "${failed_user_services[@]}")
    [[ -n "$tooltip" ]] && tooltip+=$'\n\n'
    tooltip+="User failed services (${user_count}):"
    tooltip+=$'\n'
    tooltip+="$section"
  fi

  printf '%s' "$tooltip"
}

escape_json() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

if [[ "${1:-}" == "--notify" ]]; then
  if (( total == 0 )); then
    notify-send "Systemd" "No failed services"
  else
    notify-send "Failed systemd services" "$(build_tooltip)"
  fi
  refresh_waybar
  exit 0
fi

if (( total == 0 )); then
  printf '{"text":"","tooltip":"No failed systemd services","class":"ok"}\n'
  exit 0
fi

tooltip=$(build_tooltip)
tooltip_json=$(escape_json "$tooltip")
printf '{"text":" %d","tooltip":"%s","class":"critical"}\n' "$total" "$tooltip_json"
