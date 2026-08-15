#!/bin/sh

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/gamemode-inhibit.pid"
LLAMA_STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gamemode-llama-services"

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

# Remember the router that was running before GameMode, then stop every local
# llama router. Stopping (rather than freezing) unloads child models and frees VRAM.
if [ ! -f "$LLAMA_STATE" ]; then
    state_tmp="${LLAMA_STATE}.tmp"
    rm -f "$state_tmp"
    for service in llama-swap.service llama-server.service; do
        if /usr/bin/systemctl --user is-active --quiet "$service"; then
            printf '%s\n' "$service" >> "$state_tmp"
        fi
    done
    if [ -s "$state_tmp" ]; then
        mv "$state_tmp" "$LLAMA_STATE"
    else
        rm -f "$state_tmp"
    fi
fi

# The preset watcher can restart llama-server when models.ini changes.
/usr/bin/systemctl --user stop llama-server-models.path >/dev/null 2>&1 || true
/usr/bin/systemctl --user stop llama-server.service llama-swap.service >/dev/null 2>&1 || true
