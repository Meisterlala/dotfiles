#/bin/bash
if wp get mode | grep -q 'Random'; then
	wp mode static
	dunstify -h string:x-dunst-stack-tag:wallpaper -a "Wallpaper" "Wallpaper locked" 
else
	wp mode random
	dunstify -h string:x-dunst-stack-tag:wallpaper -a "Wallpaper" "Wallpaper unlocked" 
fi
