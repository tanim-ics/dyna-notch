#!/bin/bash
# scripts/health.sh [days] — DynaNotch health report for the dogfood week (macOS, no sudo).
#
#   • crash and hang reports in ~/Library/Logs/DiagnosticReports (with the binary path, so sanitizer / test
#     builds outside /Applications are easy to tell apart) and why each one ended
#   • error / fault counts in DynaNotch's own log, plus the most frequent messages
#   • a 30 s idle measurement: CPU %, wake-ups per second, energy (top's POWER), memory
#
# Default window: the last 7 days. Paste the output back to Claude to review.

set -u
DAYS="${1:-7}"
REPORTS="$HOME/Library/Logs/DiagnosticReports"

echo "== DynaNotch health · last $DAYS day(s) · $(date '+%Y-%m-%d %H:%M')"
echo "   version: $(defaults read /Applications/DynaNotch.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo '?')"

echo
echo "-- Crash / hang reports"
found=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    found=$((found + 1))
    python3 - "$f" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path) as fh:
    header = json.loads(fh.readline())
    try:
        body = json.loads(fh.read())
    except ValueError:
        body = {}
reason = ""
term = body.get("termination", {})
if term.get("details"):
    reason = term["details"][0][:120]
exc = body.get("exception", {})
kind = exc.get("type", header.get("bug_type", "?"))
where = body.get("procPath", "?")
build = "installed" if where.startswith("/Applications/") else "test build"
print("  %s  %-11s %s  %s" % (os.path.basename(path), kind, build, reason or exc.get("signal", "")))
PY
done < <(find "$REPORTS" -maxdepth 1 \( -name 'DynaNotch*.ips' -o -name 'DynaNotch*.hang' -o -name 'DynaNotch*.spin' \) -mtime -"$DAYS" 2>/dev/null | sort)
[ "$found" -eq 0 ] && echo "  none"

echo
echo "-- Log errors / faults (subsystem com.tanim.dynanotch)"
LOG="$(log show --last "${DAYS}d" --style compact --predicate 'subsystem == "com.tanim.dynanotch" AND (messageType == error OR messageType == fault)' 2>/dev/null | grep -v '^Timestamp' | grep -v '^Filtering')"
if [ -z "$LOG" ]; then
    echo "  none"
else
    echo "  $(printf '%s\n' "$LOG" | wc -l | tr -d ' ') lines; most frequent:"
    printf '%s\n' "$LOG" | sed -E 's/^[0-9-]+ [0-9:.]+ +[A-Za-z]+ +[^ ]+ +//; s/[0-9]+/N/g' | sort | uniq -c | sort -rn | head -8 | sed 's/^/   /'
fi

echo
echo "-- Idle measurement (30 s; leave the Mac alone)"
P="$(pgrep -x DynaNotch | head -1)"
if [ -z "$P" ]; then
    echo "  DynaNotch is not running"
else
    top -l 4 -s 10 -stats pid,cpu,idlew,power -pid "$P" 2>/dev/null | awk -v p="$P" '$1==p {gsub(/[+-]/,"",$3); c[n]=$2; w[n]=$3; pw[n]=$4; n++}
    END { for(i=1;i<n;i++){cs+=c[i]; ps+=pw[i]}; printf "  cpu %.2f %%   wake-ups %.1f /s   energy %.2f\n", cs/(n-1), (w[n-1]-w[0])/((n-1)*10), ps/(n-1) }'
    echo "  memory $(( $(ps -o rss= -p "$P") / 1024 )) MB   threads $(ps -M -p "$P" | tail -n +2 | wc -l | tr -d ' ')"
fi
