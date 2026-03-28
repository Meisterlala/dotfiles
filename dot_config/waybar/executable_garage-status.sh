#!/bin/bash
set -Eeuo pipefail

BUCKET=$1
ICON=$2
STATE_FILE="/tmp/garage_bucket_${BUCKET}.count"

# 1. Fetch bucket info
INFO=$(garage bucket info "$BUCKET" 2>/dev/null || true)

if [ -z "$INFO" ]; then
    echo '{"text": "", "tooltip": "Bucket not found"}'
    exit 0
fi

# 2. Extract Object count and Size
OBJECTS=$(echo "$INFO" | grep "Objects:" | awk '{print $2}')
SIZE=$(echo "$INFO" | grep "Size:" | sed -E 's/^Size:[[:space:]]*//')

# 3. Handle State (Previous Count)
if [ -f "$STATE_FILE" ]; then
    PREV_OBJECTS=$(cat "$STATE_FILE")
else
    # First run: set to current to avoid a massive initial spike/delta
    PREV_OBJECTS=$OBJECTS
fi

# Save current count immediately for the next run
echo "$OBJECTS" > "$STATE_FILE"

# 4. Calculate Delta
DELTA=$((OBJECTS - PREV_OBJECTS))

# 5. Display Logic
# Show if objects have changed (Positive OR Negative)
if [[ "$DELTA" -ne 0 ]]; then

    # Determine formatting based on direction
    if [[ "$DELTA" -gt 0 ]]; then
        CHANGE_TEXT="+$DELTA"
        ACTIVITY="Uploading"
        CLASS="upload"
    else
        CHANGE_TEXT="$DELTA" # Delta already contains the "-" sign
        ACTIVITY="Deleting"
        CLASS="delete"
    fi
    
    # Construct Tooltip
    TOOLTIP="Bucket: $BUCKET\nActivity: $ACTIVITY\nChange: $CHANGE_TEXT objects\nTotal Objects: $OBJECTS\nSize: $SIZE"
    
    # Escape newlines and quotes for JSON
    TOOLTIP_ESCAPED=$(echo -e "$TOOLTIP" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    
    # Output JSON with "class" for styling (upload vs delete)
    echo "{\"text\": \"$ICON\", \"tooltip\": \"$TOOLTIP_ESCAPED\", \"class\": \"$CLASS\"}"

else
    # Return empty JSON to hide the module when inactive
    echo '{"text": "", "tooltip": ""}'
fi
