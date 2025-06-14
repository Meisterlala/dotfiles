#/bin/bash

socket='/run/user/1000/wallpaperd'


if wp -s $socket get wp-dir| grep -q 'nsfw'; then
	wp -s $socket wp-dir "/home/ninja/Wallpapers/sfw/"
	dunstify -h string:x-dunst-stack-tag:wallpaper -a "Wallpaper" "Displaying SFW Wallpapers" 
else
	wp -s $socket wp-dir "/home/ninja/Wallpapers/nsfw/"
	dunstify -h string:x-dunst-stack-tag:wallpaper -a "Wallpaper" "Displaying NSFW Wallpapers" 
fi
