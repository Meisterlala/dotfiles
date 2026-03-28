#!/bin/sh

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/gamemode-inhibit.pid"

if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$PID_FILE"
fi

/home/misti/.cargo/bin/wp mode random >/dev/null 2>&1 || true
swaync-client -df -sw >/dev/null 2>&1 || true
