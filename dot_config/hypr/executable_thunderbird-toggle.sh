#!/bin/bash
# Toggle a persistent mail overlay, never minimize/unmap or quit Thunderbird.
set -euo pipefail

exec 9>"${XDG_RUNTIME_DIR:?}/thunderbird-toggle.lock"
flock -n 9 || exit 0

get_client() {
    hyprctl clients -j | jq -c '
        [.[] | select((.class | ascii_downcase) == "thunderbird"
            or .class == "org.mozilla.Thunderbird")]
        | sort_by(.floating) | .[0] // empty'
}

fail() {
    command -v notify-send >/dev/null && notify-send "Thunderbird" "$1" || true
    printf '%s\n' "$1" >&2
    exit 1
}

client=$(get_client)
if [[ -z "$client" ]]; then
    # Start directly: Birdtray can return success without actually launching TB.
    systemctl --user start --no-block thunderbird-xwayland.service
    for ((i=0; i<150; i++)); do
        client=$(get_client)
        [[ -n "$client" ]] && break
        sleep 0.2
    done
    [[ -n "$client" ]] || fail "No Thunderbird window appeared within 30 seconds. Check thunderbird-xwayland.service."
fi

address=$(jq -r '.address' <<<"$client")
workspace=$(jq -r '.workspace.name' <<<"$client")
if [[ "$workspace" != "special:thunderbird" ]]; then
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:thunderbird\", window = \"address:$address\", follow = false })" >/dev/null
fi

# One toggle shows it here, hides it if already here, or transfers it from
# another monitor. Do not double-toggle: that transfers it and then hides it.
hyprctl dispatch 'hl.dsp.workspace.toggle_special("thunderbird")' >/dev/null
