#!/bin/sh
set -eu

class="org.mozilla.Thunderbird"
hidden_workspace="special:thunderbird"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
state_file="$state_dir/thunderbird-last-workspace"

get_client() {
    hyprctl clients -j | jq -c --arg class "$class" '[.[] | select(.class == $class)][0] // empty'
}

client=$(get_client)

if [ -z "$client" ]; then
    birdtray --show-tb >/dev/null 2>&1 || systemctl --user start thunderbird-xwayland.service
    sleep 0.5
    client=$(get_client)
fi

if [ -z "$client" ]; then
    exit 0
fi

address=$(printf '%s' "$client" | jq -r '.address')
workspace=$(printf '%s' "$client" | jq -r '.workspace.name')

if [ "$workspace" = "$hidden_workspace" ]; then
    target="1"
    if [ -f "$state_file" ]; then
        target=$(sed -n '1p' "$state_file")
    fi

    case "$target" in
        special:*) target="1" ;;
    esac

    hyprctl dispatch "hl.dsp.window.move({ workspace = \"$target\", window = \"address:$address\" })" >/dev/null
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null
else
    mkdir -p "$state_dir"
    printf '%s\n' "$workspace" > "$state_file"
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"$hidden_workspace\", window = \"address:$address\", follow = false })" >/dev/null
fi
