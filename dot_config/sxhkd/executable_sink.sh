#!/bin/bash
#
# Switches the current default audio sink to the next available sink using pactl.

# Get all sinks via pactl
sinks=$(pactl list short sinks | cut -f 2)

# Get current default sink
current_sink=$(pactl info | grep "Default Sink" | cut -d ' ' -f 3)

# Get sink after current sink
next_sink=$(echo "$sinks" | grep -A1 "$current_sink" | tail -n1)
if [ "$next_sink" == "$current_sink" ]; then
    next_sink=$(echo "$sinks" | head -n1)
fi

# Set next sink as default
pactl set-default-sink "$next_sink"
