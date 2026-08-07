#!/usr/bin/env bash
set -euo pipefail

sound_file="${HOME}/.config/hypr/sounds/discord-ptt-stop.mp3"
sound_volume=49152
release_delay_seconds=0.05
capture_app_binaries=("Discord")

state_prefix="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/mic-push-to-mute-${UID}"
generation_file="${state_prefix}.generation"
lock_file="${state_prefix}.lock"

is_capture_app() {
    local candidate="$1"
    local binary

    for binary in "${capture_app_binaries[@]}"; do
        [[ "$candidate" == "$binary" ]] && return 0
    done
    return 1
}

set_capture_apps_mute() {
    local muted="$1"
    local index
    local binary

    while IFS=$'\t' read -r index binary; do
        [[ -n "$index" ]] || continue
        if is_capture_app "$binary"; then
            pactl set-source-output-mute "$index" "$muted" || true
        fi
    done < <(
        pactl --format=json list source-outputs |
            jq -r '.[] | [.index, (.properties["application.process.binary"] // "")] | @tsv'
    )
}

advance_generation() {
    local generation=0
    local lock_fd

    exec {lock_fd}>"$lock_file"
    flock "$lock_fd"

    if [[ -r "$generation_file" ]]; then
        read -r generation < "$generation_file" || generation=0
    fi
    [[ "$generation" =~ ^[0-9]+$ ]] || generation=0
    generation=$((generation + 1))
    printf '%s\n' "$generation" > "$generation_file"

    flock -u "$lock_fd"
    exec {lock_fd}>&-
    printf '%s\n' "$generation"
}

schedule_mute() {
    local generation
    generation="$(advance_generation)"

    (
        local current_generation=0

        sleep "$release_delay_seconds"
        flock 9
        if [[ -r "$generation_file" ]]; then
            read -r current_generation < "$generation_file" || current_generation=0
        fi
        [[ "$current_generation" == "$generation" ]] || exit 0

        set_capture_apps_mute 1
        flock -u 9
        exec 9>&-
        paplay --volume="$sound_volume" "$sound_file" >/dev/null 2>&1 &
    ) 9>"$lock_file" &
}

case "${1:-}" in
    mute)
        schedule_mute
        ;;
    unmute)
        advance_generation >/dev/null
        set_capture_apps_mute 0
        ;;
    watch)
        set_capture_apps_mute 1
        pactl subscribe | while read -r event; do
            if [[ "$event" == "Event 'new' on source-output"* ]]; then
                set_capture_apps_mute 1
            fi
        done
        ;;
    *)
        printf 'Usage: %s {mute|unmute|watch}\n' "${0##*/}" >&2
        exit 2
        ;;
esac
