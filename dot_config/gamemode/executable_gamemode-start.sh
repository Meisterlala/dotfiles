#!/bin/sh
# Stop the router itself so background clients cannot reload models while gaming.
marker="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/llama-swap-gamemode.was-active"

if /usr/bin/systemctl --user is-active --quiet llama-swap.service; then
    : > "$marker"
    /usr/bin/systemctl --user stop llama-swap.service
else
    rm -f "$marker"
fi
