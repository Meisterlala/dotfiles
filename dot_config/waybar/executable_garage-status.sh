#!/bin/bash
set -Eeuo pipefail

BUCKET=${1:?bucket required}
ICON=${2:?icon required}
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-garage"
STATE_FILE="$STATE_DIR/${BUCKET}.count"

json_escape() {
    local value=${1//\\/\\\\}
    value=${value//"/\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

trim_leading() {
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    printf '%s' "$value"
}

mkdir -p "$STATE_DIR"

INFO=$(garage bucket info "$BUCKET" 2>/dev/null || true)
if [[ -z "$INFO" ]]; then
    printf '{"text":"","tooltip":"Bucket not found"}\n'
    exit 0
fi

OBJECTS=""
SIZE=""
while IFS= read -r line; do
    case "$line" in
        Objects:*)
            OBJECTS=${line#Objects:}
            OBJECTS=$(trim_leading "$OBJECTS")
            ;;
        Size:*)
            SIZE=${line#Size:}
            SIZE=$(trim_leading "$SIZE")
            ;;
    esac
done <<< "$INFO"

if [[ ! "$OBJECTS" =~ ^[0-9]+$ ]]; then
    printf '{"text":"","tooltip":"Failed to parse bucket stats"}\n'
    exit 0
fi

# First run uses the current count so the widget doesn't flash a bogus delta.
PREV_OBJECTS=$OBJECTS
if [[ -f "$STATE_FILE" ]]; then
    read -r PREV_OBJECTS < "$STATE_FILE" || PREV_OBJECTS=$OBJECTS
    [[ "$PREV_OBJECTS" =~ ^[0-9]+$ ]] || PREV_OBJECTS=$OBJECTS
fi

printf '%s\n' "$OBJECTS" > "$STATE_FILE"
DELTA=$((OBJECTS - PREV_OBJECTS))

if (( DELTA == 0 )); then
    printf '{"text":"","tooltip":""}\n'
    exit 0
fi

if (( DELTA > 0 )); then
    CHANGE_TEXT="+$DELTA"
    ACTIVITY="Uploading"
    CLASS="upload"
else
    CHANGE_TEXT="$DELTA"
    ACTIVITY="Deleting"
    CLASS="delete"
fi

TOOLTIP=$(printf 'Bucket: %s\nActivity: %s\nChange: %s objects\nTotal Objects: %s\nSize: %s' \
    "$BUCKET" "$ACTIVITY" "$CHANGE_TEXT" "$OBJECTS" "$SIZE")

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
    "$(json_escape "$ICON")" \
    "$(json_escape "$TOOLTIP")" \
    "$(json_escape "$CLASS")"
