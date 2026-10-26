#!/bin/bash
# measure.sh <ProcessName> [seconds=60] — average CPU %, idle wake-ups/s, POWER (energy impact) and RSS, via top (no sudo).
NAME="${1:?process name}"; P=$(pgrep -x "$NAME" | head -1); [ -n "$P" ] || { echo "$NAME not running"; exit 1; }
N=$(( ${2:-60} / 10 + 1 ))
top -l $N -s 10 -stats pid,cpu,idlew,power -pid "$P" 2>/dev/null | awk -v p="$P" '$1==p {gsub(/[+-]/,"",$3); c[n]=$2; w[n]=$3; pw[n]=$4; n++}
END { for(i=1;i<n;i++){cs+=c[i]; ps+=pw[i]}; printf "cpu_avg=%.2f%% wakeups_per_s=%.2f power_avg=%.2f samples=%d\n", cs/(n-1), (w[n-1]-w[0])/((n-1)*10), ps/(n-1), n-1 }'
echo "rss_mb=$(( $(ps -o rss= -p "$P") / 1024 )) threads=$(ps -M -p "$P" | tail -n +2 | wc -l | tr -d ' ')"
