#!/bin/bash
# battery-time.sh — remaining battery time for BAT0 + BAT1 (Polybar-friendly)

BAT_PATH="/sys/class/power_supply"
BATTERIES=(BAT0 BAT1)

total_energy=0
total_power=0

for bat in "${BATTERIES[@]}"; do
    if [[ -f "$BAT_PATH/$bat/energy_now" && -f "$BAT_PATH/$bat/power_now" ]]; then
        energy=$(cat "$BAT_PATH/$bat/energy_now")
        power=$(cat "$BAT_PATH/$bat/power_now")
    elif [[ -f "$BAT_PATH/$bat/charge_now" && -f "$BAT_PATH/$bat/current_now" ]]; then
        # Convert Ah/A to Wh assuming voltage in volts (approx 1 V = 1 W/A for rough estimate)
        energy=$(cat "$BAT_PATH/$bat/charge_now")
        power=$(cat "$BAT_PATH/$bat/current_now")
    else
        continue
    fi

    # Sum up
    total_energy=$((total_energy + energy))
    total_power=$((total_power + power))
done

# Avoid division by zero
if (( total_power == 0 )); then
    total_sec=0
else
    # remaining time in seconds = total stored / total draw
    total_sec=$(( total_energy * 3600 / total_power ))
fi

hours=$(( total_sec / 3600 ))
minutes=$(( (total_sec % 3600) / 60 ))

# determine color
if (( total_sec <= 1800 )); then
    color="%{F#FF0000}"   # red
elif (( total_sec <= 7200 )); then
    color="%{F#FFFF00}"   # yellow
else
    color="%{}"
fi

# output for Polybar
echo "${color}${hours}h ${minutes}m%{F-}"

