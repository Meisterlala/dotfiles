#!/bin/bash
set -Eeuo pipefail

BUCKET=$1
ICON=$2

# Fetch bucket info
INFO=$(garage bucket info "$BUCKET" 2>/dev/null || true)

if [ -z "$INFO" ]; then
    exit 0
fi

# Extract the number of unfinished uploads including regular uploads
# The line looks like: "                                       3 including regular uploads"
UPLOADS=$(echo "$INFO" | grep "including regular uploads" | sed -E 's/^[[:space:]]*([0-9]+).*/\1/')

if [[ "$UPLOADS" -gt 0 ]]; then
    echo "$ICON"
else
    echo ""
fi
