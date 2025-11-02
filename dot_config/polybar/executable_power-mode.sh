#!/bin/bash
# u-mode-toggle.sh — toggle CPU modes or show current mode (Polybar-friendly + Dunstify)

GOV_PATH="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
EPP_PATH="/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"

# --- Define modes ---
declare -A MODE_VAR        # internal code name
declare -A MODE_BAR        # Polybar short name
declare -A MODE_NOTIFY     # Notification full name
declare -A MODE_COLOR      # Polybar color

# Internal names
MODE_VAR=( ["power"]="powersave|power" ["balanced"]="powersave|balance_power" ["performance"]="performance|performance" )

# Polybar short names
MODE_BAR=( ["power"]="P" ["balanced"]="B" ["performance"]="X" ["unknown"]="?")

# Dunst notification full names
MODE_NOTIFY=( ["power"]="Power-Saving" ["balanced"]="Balanced" ["performance"]="Full-Performance" )

# Polybar colors
MODE_COLOR=( ["power"]="%{F#00FF00}" ["balanced"]="%{F#FFFF00}" ["performance"]="%{F#FF0000}" )

# --- function to determine current mode ---
get_current_mode() {
    local gov=$1
    local epp=$2
    for mode in "${!MODE_VAR[@]}"; do
        IFS='|' read -r m_gov m_epp <<< "${MODE_VAR[$mode]}"
        if [[ "$gov" == "$m_gov" && "$epp" == "$m_epp" ]]; then
            echo "$mode"
            return
        fi
    done
    echo "unknown"
}

# --- status-only mode ---
if [[ "$1" == "status" ]]; then
    gov=$(cat "$GOV_PATH")
    epp=$(cat "$EPP_PATH")
    mode=$(get_current_mode "$gov" "$epp")
    echo "${MODE_COLOR[$mode]}${MODE_BAR[$mode]}%{F-}"
    exit 0
fi

# --- toggle mode ---
current_gov=$(cat "$GOV_PATH")
current_epp=$(cat "$EPP_PATH")
current_mode=$(get_current_mode "$current_gov" "$current_epp")

# determine next mode in cycle: power -> balanced -> performance -> power ...
case "$current_mode" in
    "power") new_mode="balanced" ;;
    "balanced") new_mode="performance" ;;
    *) new_mode="power" ;;
esac

# apply to all CPUs
IFS='|' read -r new_gov new_epp <<< "${MODE_VAR[$new_mode]}"
for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
    echo "$new_gov" > "$cpu_dir/cpufreq/scaling_governor"
    echo "$new_epp" > "$cpu_dir/cpufreq/energy_performance_preference"
done

# --- Dunstify notification ---
dunstify \
    -u normal \
    -h string:x-dunst-stack-tag:power-mode \
    -a "CPU Mode" \
    "> ${MODE_NOTIFY[$new_mode]}" \
    "Governor: $new_gov
     EPP: $new_epp"

# --- echo for Polybar ---
echo "${MODE_COLOR[$new_mode]}${MODE_BAR[$new_mode]}%{F-}"

