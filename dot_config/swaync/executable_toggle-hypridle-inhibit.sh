#!/usr/bin/env bash

set -euo pipefail

INHIBIT_FILE="/tmp/hypridle-inhibit.lock"
ACTION="${1:-toggle}"

read_pid() {
    if [[ -f "$INHIBIT_FILE" ]]; then
        <"$INHIBIT_FILE" read -r pid || true
        printf '%s\n' "${pid:-}"
    fi
}

is_enabled() {
    local pid
    pid="$(read_pid)"

    if [[ -z "$pid" ]]; then
        return 1
    fi

    if kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    rm -f "$INHIBIT_FILE"
    return 1
}

enable_inhibit() {
    if is_enabled; then
        return 0
    fi

    systemd-inhibit --what=idle --who="SwayNC" --why="Toggle activated" --mode=block sleep infinity >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$INHIBIT_FILE"
}

disable_inhibit() {
    local pid
    pid="$(read_pid)"

    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
    fi

    rm -f "$INHIBIT_FILE"
}

toggle_inhibit() {
    if is_enabled; then
        disable_inhibit
    else
        enable_inhibit
    fi
}

status_inhibit() {
    if is_enabled; then
        printf 'on\n'
    else
        printf 'off\n'
    fi
}

swaync_action() {
    case "${SWAYNC_TOGGLE_STATE:-}" in
        true)
            enable_inhibit
            ;;
        false)
            disable_inhibit
            ;;
        *)
            toggle_inhibit
            ;;
    esac
}

swaync_state() {
    if is_enabled; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

case "$ACTION" in
    on|enable)
        enable_inhibit
        ;;
    off|disable)
        disable_inhibit
        ;;
    toggle)
        toggle_inhibit
        ;;
    status)
        status_inhibit
        ;;
    swaync)
        swaync_action
        ;;
    swaync-state)
        swaync_state
        ;;
    *)
        printf 'Usage: %s [on|off|toggle|status|swaync|swaync-state]\n' "$0" >&2
        exit 1
        ;;
esac
