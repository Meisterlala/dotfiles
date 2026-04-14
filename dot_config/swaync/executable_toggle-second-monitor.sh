#!/usr/bin/env bash

set -euo pipefail

MONITOR_DESC="Acer Technologies ED270U P TKYEE0013W01"
ACTION="${1:-status}"

TARGET_NAME=""
TARGET_DISABLED=""
TARGET_DPMS=""

load_target_monitor() {
    local output line current_name="" current_desc="" current_disabled="false" current_dpms="1"

    TARGET_NAME=""
    TARGET_DISABLED=""
    TARGET_DPMS=""

    if ! output="$(hyprctl monitors all 2>/dev/null)"; then
        return 1
    fi

    while IFS= read -r line; do
        case "$line" in
            Monitor\ *)
                if [[ "$current_desc" == "$MONITOR_DESC" ]]; then
                    TARGET_NAME="$current_name"
                    TARGET_DISABLED="$current_disabled"
                    TARGET_DPMS="$current_dpms"
                    return 0
                fi
                current_name="${line#Monitor }"
                current_name="${current_name%% *}"
                current_desc=""
                current_disabled="false"
                current_dpms="1"
                ;;
            *description:\ *)
                current_desc="${line#*description: }"
                ;;
            *disabled:\ *)
                current_disabled="${line#*disabled: }"
                ;;
            *dpmsStatus:\ *)
                current_dpms="${line#*dpmsStatus: }"
                ;;
        esac
    done <<< "$output"

    if [[ "$current_desc" == "$MONITOR_DESC" ]]; then
        TARGET_NAME="$current_name"
        TARGET_DISABLED="$current_disabled"
        TARGET_DPMS="$current_dpms"
    fi
}

require_target_monitor() {
    if ! load_target_monitor; then
        printf 'Could not query monitors\n' >&2
        return 1
    fi

    if [[ -z "$TARGET_NAME" ]]; then
        printf 'missing\n' >&2
        return 1
    fi
}

monitor_status() {
    if ! load_target_monitor; then
        printf 'unknown\n'
        return 0
    fi

    if [[ -z "$TARGET_NAME" ]]; then
        printf 'missing\n'
    elif [[ "$TARGET_DISABLED" == "true" ]]; then
        printf 'disabled\n'
    elif [[ "$TARGET_DPMS" == "0" || "$TARGET_DPMS" == "false" ]]; then
        printf 'off\n'
    else
        printf 'on\n'
    fi
}

enable_monitor() {
    require_target_monitor || return 1

    if [[ "$TARGET_DISABLED" == "true" ]]; then
        printf 'disabled\n' >&2
        return 1
    fi

    hyprctl dispatch dpms on "$TARGET_NAME" >/dev/null
}

disable_monitor() {
    require_target_monitor || return 1
    hyprctl dispatch dpms off "$TARGET_NAME" >/dev/null
}

toggle_monitor() {
    case "$(monitor_status)" in
        on)
            disable_monitor
            ;;
        off)
            enable_monitor
            ;;
        disabled|missing)
            printf 'Monitor is not available for DPMS toggle\n' >&2
            return 1
            ;;
        unknown)
            printf 'Could not determine monitor state\n' >&2
            return 1
            ;;
    esac
}

swaync_action() {
    case "${SWAYNC_TOGGLE_STATE:-}" in
        true)
            disable_monitor
            ;;
        false)
            enable_monitor
            ;;
        *)
            toggle_monitor
            ;;
    esac
}

swaync_state() {
    case "$(monitor_status)" in
        off|disabled)
            printf 'true\n'
            ;;
        *)
            printf 'false\n'
            ;;
    esac
}

case "$ACTION" in
    enable)
        enable_monitor
        ;;
    disable)
        disable_monitor
        ;;
    toggle)
        toggle_monitor
        ;;
    status)
        monitor_status
        ;;
    swaync)
        swaync_action
        ;;
    swaync-state)
        swaync_state
        ;;
    *)
        printf 'Usage: %s [enable|disable|toggle|status|swaync|swaync-state]\n' "$0" >&2
        exit 1
        ;;
esac
