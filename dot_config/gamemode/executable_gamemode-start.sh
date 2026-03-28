#!/bin/sh

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/gamemode-inhibit.pid"

if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        :
    else
        rm -f "$PID_FILE"
    fi
fi

if [ ! -f "$PID_FILE" ] && command -v systemd-inhibit >/dev/null 2>&1; then
    systemd-inhibit --what=idle:sleep --who="gamemode" --why="GameMode active" /usr/bin/sleep infinity >/dev/null 2>&1 &
    pid=$!
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        printf '%s\n' "$pid" > "$PID_FILE"
    fi
fi

/home/misti/.cargo/bin/wp mode static >/dev/null 2>&1 || true
swaync-client -dn -sw >/dev/null 2>&1 || true
