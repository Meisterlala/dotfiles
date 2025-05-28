#/bin/bash

# Calc Frequency average
freq=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq)
formular="($(echo $freq | tr -s ' ' '+')) / $(echo $freq | wc -w) / 1000"
avr=$(echo $formular | bc -l)
round=$(printf %.0f $avr)

# output Mhz
echo $round

# Exit with 1 if load average to big
load=$(cat /proc/loadavg | awk '{print $1}')
# Max load in percent
max_load=0.8
core_count=$(nproc --all)
if (( $(echo "$load > ($max_load * $core_count)" |bc -l) )); then
	exit 1
fi
