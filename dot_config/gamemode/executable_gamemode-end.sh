#!/bin/sh
# Restore llama-swap only if GameMode stopped a previously running service.
marker="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/llama-swap-gamemode.was-active"

if [ -f "$marker" ]; then
    rm -f "$marker"
    /usr/bin/systemctl --user start llama-swap.service
fi
