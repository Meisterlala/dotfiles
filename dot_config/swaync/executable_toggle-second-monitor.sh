#!/bin/bash

set -euo pipefail

MONITOR_DESC="Acer Technologies ED270U P TKYEE0013W01"
MONITOR_SELECTOR="desc:${MONITOR_DESC}"
MONITOR_MODE="2560x1440@165.00"
MONITOR_POSITION="auto-right"
MONITOR_SCALE="1"
ACTION="${1:-toggle}"

monitor_status() {
    python3 - "$MONITOR_DESC" <<'PY'
import json
import subprocess
import sys

desc = sys.argv[1]

try:
    output = subprocess.check_output(["hyprctl", "-j", "monitors", "all"], text=True)
except Exception:
    print("unknown")
    raise SystemExit(0)

try:
    monitors = json.loads(output)
except json.JSONDecodeError:
    print("unknown")
    raise SystemExit(0)

for monitor in monitors:
    if monitor.get("description") == desc:
        print("disabled" if monitor.get("disabled", False) else "enabled")
        raise SystemExit(0)

print("missing")
PY
}

enable_monitor() {
    hyprctl keyword monitor "$MONITOR_SELECTOR,$MONITOR_MODE,$MONITOR_POSITION,$MONITOR_SCALE" >/dev/null
}

disable_monitor() {
    hyprctl keyword monitor "$MONITOR_SELECTOR,disable" >/dev/null
}

case "$ACTION" in
    enable)
        enable_monitor
        ;;
    disable)
        disable_monitor
        ;;
    toggle)
        case "$(monitor_status)" in
            enabled)
                disable_monitor
                ;;
            disabled|missing)
                enable_monitor
                ;;
        esac
        ;;
    status)
        monitor_status
        ;;
esac
