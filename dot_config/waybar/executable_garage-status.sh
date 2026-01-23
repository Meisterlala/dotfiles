#!/bin/bash
set -Eeuo pipefail

BUCKET=$1
ICON=$2

# Fetch bucket info
INFO=$(garage bucket info "$BUCKET" 2>/dev/null || true)

if [ -z "$INFO" ]; then
    echo '{"text": "", "tooltip": "Bucket not found"}'
    exit 0
fi

# Extract the number of unfinished uploads including regular uploads
# The line looks like: "                                       3 including regular uploads"
UPLOADS=$(echo "$INFO" | grep "including regular uploads" | sed -E 's/^[[:space:]]*([0-9]+).*/\1/')

if [[ "$UPLOADS" -gt 0 ]]; then
    # Create a nice tooltip with more info
    SIZE=$(echo "$INFO" | grep "Size:" | sed -E 's/^Size:[[:space:]]*//')
    OBJECTS=$(echo "$INFO" | grep "Objects:" | sed -E 's/^Objects:[[:space:]]*//')
    
    TOOLTIP="Bucket: $BUCKET\nStatus: Active Access\nUploads: $UPLOADS\nSize: $SIZE\nObjects: $OBJECTS"
    
    # Escape for JSON
    TOOLTIP_ESCAPED=$(echo -e "$TOOLTIP" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    
    echo "{\"text\": \"$ICON\", \"tooltip\": \"$TOOLTIP_ESCAPED\"}"
else
    echo '{"text": "", "tooltip": ""}'
fi
