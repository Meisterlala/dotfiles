#!/bin/sh

# Online Check
nm-online -q
if [ $? -ne 0 ]; then
    exit
fi

# Popop
if [[ "$1" == "--popup" ]]; then
	pop=$(gcalcli agenda today 11:55pm --tsv --details=end --details=location | awk -F'\t' '{print $2 "-"$4 "  " $5 " " $6}')
	notify-send "${pop}"
	exit
fi


agenda=$(gcalcli agenda today 11:55pm --tsv --nostarted --details=end --details=location)

#echo $agenda

if [[ -z "$agenda" ]]; then
   exit
fi

echo "${agenda}" | awk -F'\t' 'NR==1{if($6==""){print $2 " " $5}{print $2 " " $5 "|"$6}}'
