#!/bin/sh

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/gamemode-inhibit.pid"
LLAMA_STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gamemode-llama-swap.state"

if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$PID_FILE"
fi

/home/misti/.cargo/bin/wp mode random >/dev/null 2>&1 || true
swaync-client -df -sw >/dev/null 2>&1 || true

if [ "$(cat "$LLAMA_STATE" 2>/dev/null)" = active ]; then
    /usr/bin/systemctl --user start llama-swap.service >/dev/null 2>&1 || true
fi
rm -f "$LLAMA_STATE"
