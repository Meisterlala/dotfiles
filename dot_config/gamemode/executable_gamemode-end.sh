#!/bin/sh

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/gamemode-inhibit.pid"
LLAMA_STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gamemode-llama-services"
LEGACY_LLAMA_MARKER="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/llama-swap-gamemode.was-active"

if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$PID_FILE"
fi

/home/misti/.cargo/bin/wp mode random >/dev/null 2>&1 || true
swaync-client -df -sw >/dev/null 2>&1 || true

# Restore only the router that GameMode stopped. Accept the old marker once so
# an upgrade performed during an active game still restores llama-swap on exit.
if [ -f "$LEGACY_LLAMA_MARKER" ]; then
    rm -f "$LEGACY_LLAMA_MARKER"
    if [ ! -f "$LLAMA_STATE" ]; then
        printf '%s\n' llama-swap.service > "$LLAMA_STATE"
    fi
fi

if [ -f "$LLAMA_STATE" ]; then
    services=$(cat "$LLAMA_STATE")
    rm -f "$LLAMA_STATE"
    for service in $services; do
        case "$service" in
            llama-swap.service|llama-server.service)
                /usr/bin/systemctl --user start "$service" >/dev/null 2>&1 || true
                ;;
        esac
    done
fi
