#!/bin/bash

# Terminate already running bar instances
polybar-msg cmd quit 
killall -q polybar
# If all your bars have ipc enabled, you can also use 

# Launch Polybar, using default config location ~/.config/polybar/config.ini
polybar --config="~/.config/polybar/config.ini" bar1 2>&1 | tee -a /tmp/polybar.log & disown

echo "Polybar launched..."
