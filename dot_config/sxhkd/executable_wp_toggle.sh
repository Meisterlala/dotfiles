#/bin/bash
if wp get wp-dir | grep -q 'nsfw'; then
	wp wp-dir "~/Wallpapers/sfw/"
	dunstify -h string:x-dunst-stack-tag:wallpaper -a "Wallpaper" "Displaying SFW Wallpapers" 
else
	wp wp-dir "~/Wallpapers/nsfw/"
	dunstify -h string:x-dunst-stack-tag:wallpaper -a "Wallpaper" "Displaying NSFW Wallpapers" 
fi
