#!/bin/sh

if xrandr | grep "HDMI-2 connected ("; then
	xrandr --output HDMI-2 --mode 1920x1080 --same-as eDP-1
fi
