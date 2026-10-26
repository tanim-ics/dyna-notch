#!/bin/bash
# scripts/ui-regression.sh — scripted user scenarios against the installed, running DynaNotch (macOS only).
#
# Drives the app through dynanotch:// test hooks (see CLAUDE.md §9 "Scripted UI tests") and asserts on
# Snapshots/state.json after each step; every tab and Settings page must also render a non-trivial snapshot.
# Live data (music, weather, clock) changes between runs, so it checks state + rendering, not exact pixels.
#
# Usage: scripts/ui-regression.sh            (the app must be running: ./build.sh installs and launches it)
# Exit code = number of failed checks (0 = all passed). Restores pin/hover state at the end.

set -u
SNAP="$HOME/Library/Application Support/DynaNotch/Snapshots"
STATE="$SNAP/state.json"
PASS=0
FAIL=0

pgrep -x DynaNotch >/dev/null || { echo "DynaNotch is not running (run ./build.sh first)"; exit 1; }

u() { open -g "dynanotch://$1"; sleep "${2:-0.7}"; }
state() { rm -f "$STATE"; u state 0.5; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2], ''))" "$STATE" "$1" 2>/dev/null; }
check() {   # check <name> <actual> <expected-prefix>
    case "$2" in
        "$3"*) PASS=$((PASS + 1)) ;;
        *) FAIL=$((FAIL + 1)); printf '  FAIL %-38s got "%s", want "%s…"\n' "$1" "$2" "$3" ;;
    esac
}
rendered() {   # rendered <name> <png> <min bytes>
    local size; size=$(stat -f %z "$2" 2>/dev/null || echo 0)
    if [ "$size" -ge "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); printf '  FAIL %-38s snapshot %s bytes\n' "$1" "$size"; fi
}

echo "==> Panel tabs (pinned so outside clicks can't close it)"
TABS="home nowPlaying timer clipboard shelf notes calculator emoji quickSearch launcher shortcuts reminders mirror system aiUsage calendar quickSettings"
for t in $TABS; do
    u "pin/$t" 1.0
    check "tab $t: visible" "$(state visibleTab)" "$t"
    check "tab $t: expanded" "$(state presentation)" "expanded"
    rm -f "$SNAP/reg-tab-$t.png"; u "snapshot/reg-tab-$t" 1.2
    rendered "tab $t: renders" "$SNAP/reg-tab-$t.png" 40000
done

echo "==> Header cards open on hover, close when the pointer leaves"
u "pin/home" 1.0
center() {   # center <uiTestID> → "x y" (frames are "x,y wxh", top-left origin)
    python3 -c "
import json,sys
f=json.load(open(sys.argv[1]))['frames'].get(sys.argv[2],'0,0 0x0')
xy,wh=f.split(); x,y=map(float,xy.split(',')); w,h=map(float,wh.split('x')); print(x+w/2, y+h/2)" "$STATE" "$1"
}
read -r BX BY <<<"$(center batteryPill)"
read -r SX SY <<<"$(center soundButton)"
u "ui/pointer?x=$BX&y=$BY" 0.8; check "battery card on hover" "$(state headerCard)" "battery"
u "ui/pointer?x=120&y=150" 0.9; check "battery card closes" "$(state headerCard)" "none"
u "ui/pointer?x=$SX&y=$SY" 0.8; check "sound card on hover" "$(state headerCard)" "sound"
u "ui/pointer?x=120&y=150" 0.9; check "sound card closes" "$(state headerCard)" "none"
u "ui/pointer" 0.3
u unpin 1.0

echo "==> Live activities"
for d in volume brightness charging lowBattery airpods focus calendar notification download camera capsLock; do
    u "simulate/$d" 0.6
    check "activity $d" "$(state presentation)" "activity"
done
u "simulate/peek" 0.6; check "track peek" "$(state presentation)" "peek"
sleep 3

echo "==> Command palette"
u "ui/action?name=commandPalette" 1.0; check "palette opens" "$(state palette)" "True"
u "ui/palette?query=timer" 0.6; check "palette search" "$(state paletteSelection)" "Open Timer"
u "ui/palette?key=escape" 0.6; check "palette closes on Esc" "$(state palette)" "False"

echo "==> Hide DynaNotch"
u "ui/action?name=hide" 3.0; check "hide: hidden" "$(state presentation)" "hidden"
u "ui/action?name=hide" 1.0; check "hide: back" "$(state isUserHidden)" "False"
u collapse 0.6

echo "==> Settings pages"
PAGES="general appearance behavior popups allTools tabs home knock nowPlaying calendar activity aiUsage timer clipboard quickSearch files screenshots hud battery connectivity permissions about"
for p in $PAGES; do
    rm -f "$SNAP/settings-$p.png"; u "snapshot-settings/$p" 1.4
    rendered "settings $p: renders" "$SNAP/settings-$p.png" 40000
done

echo
echo "ui-regression: $PASS passed, $FAIL failed"
exit $FAIL
