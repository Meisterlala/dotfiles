#!/usr/bin/env bash
set -euo pipefail

preferred_root="${HOME}/Nextcloud/Photos/Screenshots"
fallback_root="${HOME}/Pictures/Screenshots"

year="$(date '+%Y')"
month="$(date '+%m')"
stamp="$(date '+%Y%m%d-%H%M')"
cursor_pos=""
cursor_x=""
cursor_y=""
freeze_pid=""
watcher_pid=""

notify_msg() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$1" "$2"
    fi
}

random_letters() {
    local s
    s="$(LC_ALL=C head -c 256 /dev/urandom | tr -dc 'a-z' | cut -c1-6)"
    [[ ${#s} -eq 6 ]]
    printf '%s' "$s"
}

hide_cursor() {
    if command -v hyprctl >/dev/null 2>&1; then
        cursor_pos="$(hyprctl cursorpos)"
        cursor_x="${cursor_pos%, *}"
        cursor_y="${cursor_pos#*, }"
        hyprctl dispatch 'hl.dsp.cursor.move({ x = 99999, y = 99999 })' >/dev/null 2>&1 || true
    fi
}

show_cursor() {
    if command -v hyprctl >/dev/null 2>&1 && [[ -n "$cursor_x" && -n "$cursor_y" ]]; then
        hyprctl dispatch "hl.dsp.cursor.move({ x = $cursor_x, y = $cursor_y })" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    show_cursor

    if [[ -n "$watcher_pid" ]]; then
        kill "$watcher_pid" >/dev/null 2>&1 || true
    fi

    if [[ -n "$freeze_pid" ]]; then
        kill "$freeze_pid" >/dev/null 2>&1 || true
    fi

    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch '(function() hl.config({ animations = { enabled = true } }); return hl.dsp.no_op() end)()' >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

suffix="$(random_letters)" || {
    notify_msg "Screenshot failed" "Could not generate filename suffix."
    exit 1
}

preferred_dir="${preferred_root}/${year}/${month}"
fallback_dir="${fallback_root}/${year}/${month}"

if mkdir -p -- "$preferred_dir" 2>/dev/null; then
    base_dir="$preferred_dir"
else
    mkdir -p -- "$fallback_dir"
    base_dir="$fallback_dir"
    notify_msg \
        "Screenshot path unavailable" \
        "Could not use preferred folder. Saving to fallback folder instead."
fi

rawfile="${base_dir}/${stamp}-${suffix}.png"
outfile="${base_dir}/${stamp}-${suffix}-satty.png"

if command -v hyprctl >/dev/null 2>&1; then
    hyprctl dispatch '(function() hl.config({ animations = { enabled = false } }); return hl.dsp.no_op() end)()'
fi

if command -v hyprpicker >/dev/null 2>&1; then
    hyprpicker -r -z >/dev/null 2>&1 &
    freeze_pid="$!"
    sleep 0.05
fi

if [[ -n "$freeze_pid" ]]; then
    (
        while pgrep -x slurp >/dev/null 2>&1; do
            sleep 0.05
        done
        kill "$freeze_pid" >/dev/null 2>&1 || true
    ) &
    watcher_pid="$!"
fi

geometry="$(slurp -d || true)"
if [[ -z "$geometry" ]]; then
    notify_msg "Screenshot cancelled" "No region was selected."
    exit 1
fi

hide_cursor

if ! grim -g "$geometry" "$rawfile"; then
    notify_msg "Screenshot failed" "Could not create screenshot."
    exit 1
fi

show_cursor

if ! wl-copy --type image/png < "$rawfile"; then
    notify_msg "Clipboard failed" "Screenshot was saved, but copying failed."
fi

setsid -f satty \
    --filename "$rawfile" \
    --output-filename "$outfile" \
    --disable-notifications \
    --copy-command wl-copy \
    --early-exit \
    >/dev/null 2>&1 || {
    notify_msg "Satty failed" "Could not open or save the annotated screenshot."
    exit 1
}
