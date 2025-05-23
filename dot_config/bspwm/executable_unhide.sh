#!/bin/sh

hidden=$(bspc query -N -n .hidden -d focused)

if [ -z "$hidden" ]; then
	exit
fi


for nid in $hidden
do
	bspc node "$nid" -g hidden=off
done
