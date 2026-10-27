#!/bin/bash
# scripts/ui-regression.sh — scripted user scenarios against the installed, running DynaNotch (macOS only).
#
# Drives the app through dynanotch:// test hooks (see CLAUDE.md §5 "Test hooks") and asserts on
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

echo "==> Floating pill width / height (restores the owner's shape and sizes)"
pref() { defaults read com.tanim.dynanotch "$1" 2>/dev/null || echo "$2"; }
if [ "$(state isOnNotchDisplay)" = "True" ]; then SHAPE=dn.notchDisplayStyle; SHAPE_DEF=notch; else SHAPE=dn.nonNotchStyle; SHAPE_DEF=pill; fi
OLD_SHAPE=$(pref $SHAPE $SHAPE_DEF); OLD_PW=$(pref dn.pillWidth 185); OLD_PH=$(pref dn.pillHeight 36); OLD_PS=$(pref dn.pillScale 1)
u "set?$SHAPE=pill&dn.pillWidth=185&dn.pillHeight=36&dn.pillScale=1" 1.0
MIN=$(state pillMinWidth); MINI=${MIN%.*}
check "pill: is pill" "$(state isPill)" "True"
check "pill: default height 36" "$(state notchHeight)" "36"
check "pill: default width = notch" "$(state notchWidth)" "$((MINI - 12))"
u "set?dn.pillWidth=100&dn.pillHeight=10" 1.0
check "pill: width floor = notch" "$(state notchWidth)" "$((MINI - 12))"
check "pill: height floor 28" "$(state notchHeight)" "28"
u "set?dn.pillWidth=300&dn.pillHeight=42" 1.0
check "pill: custom width 300" "$(state notchWidth)" "288"
check "pill: custom height 42" "$(state notchHeight)" "42"
rm -f "$SNAP/reg-pill-custom.png"; u "snapshot/reg-pill-custom" 1.2
rendered "pill: custom renders" "$SNAP/reg-pill-custom.png" 2000
u "set?dn.pillScale=0.85" 1.0
REST=$(state notchWidth); HGT=$(state notchHeight)
check "pill: content scale keeps outline" "$(python3 -c "print(round(($REST + 12) * 0.85), round($HGT * 0.85))")" "300 42"
u "set?$SHAPE=$OLD_SHAPE&dn.pillWidth=$OLD_PW&dn.pillHeight=$OLD_PH&dn.pillScale=$OLD_PS" 1.0

echo "==> Show On: Every display / Follow mouse (restores the owner's choice)"
OLD_DM=$(pref dn.displayMode notchOrMain); OLD_NN=$(pref dn.showOnNonNotchDisplays 1)
[ "$OLD_NN" = "1" ] && OLD_NN=true; [ "$OLD_NN" = "0" ] && OLD_NN=false
islands() { rm -f "$STATE"; u state 0.5; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); i=d.get('islands',[]); print(len(i), sum(1 for x in i if x.get('visible')), sum(1 for x in i if sys.argv[2] in x.get('presentation','')), sum(1 for x in i if x.get('isUserHidden')))" "$STATE" "$1" 2>/dev/null; }
SCREENS=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c "Resolution:")
EXTRA=$((SCREENS - 1)); [ "$EXTRA" -lt 0 ] && EXTRA=0
u "set?dn.displayMode=allDisplays&dn.showOnNonNotchDisplays=true" 2.0
check "every display: one island per extra display" "$(islands x)" "$EXTRA $EXTRA"
u "notify?title=Regression&body=every%20display" 1.0
check "every display: notify reaches all" "$(islands notification)" "$EXTRA $EXTRA $EXTRA"
u "ui/action?name=hide" 2.0; check "every display: hide hides all" "$(islands x | cut -d' ' -f4)" "$EXTRA"
u "ui/action?name=hide" 1.5; check "every display: show again" "$(islands x | cut -d' ' -f4)" "0"
if [ "$EXTRA" -gt 0 ]; then
    rm -f "$SNAP/reg-extra.png"; u "snapshot-extra/reg-extra" 1.2
    rendered "every display: extra renders" "$SNAP/reg-extra.png" 2000
fi
u "set?dn.displayMode=followMouse" 1.5
check "follow mouse: single island" "$(islands x)" "0 0"
u "set?dn.displayMode=$OLD_DM&dn.showOnNonNotchDisplays=$OLD_NN" 1.5
check "show on: restored" "$(state displayMode)" "$OLD_DM"

echo "==> Lock screen (simulated lock / unlock; never locks the Mac; sounds silenced, settings restored)"
lsk() { rm -f "$STATE"; u state 0.4; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); l=d.get('lockScreen',{}); print(l.get(sys.argv[2], ''))" "$STATE" "$1" 2>/dev/null; }
b() { v=$(pref "$1" "$2"); [ "$v" = "1" ] && v=true; [ "$v" = "0" ] && v=false; echo "$v"; }
OLD_AS=$(pref dn.alertSounds ""); OLD_LW=$(b dn.lockScreenWidgets true); OLD_UA=$(b dn.unlockActivity true)
u "set?dn.alertSounds=screenLock%3DNone%2CscreenUnlock%3DNone&dn.lockScreenWidgets=true&dn.unlockActivity=true" 0.8
u "lockscreen/lock" 1.5
check "lock screen: locked" "$(lsk locked)" "True"
check "lock screen: strip shown" "$(lsk shown)" "True"
rm -f "$SNAP/reg-lockscreen.png"; u "snapshot-lockscreen/reg-lockscreen" 1.0
rendered "lock screen: strip renders" "$SNAP/reg-lockscreen.png" 3000
u "lockscreen/unlock" 0.3
check "lock screen: unlocked popup" "$(state presentation | grep -o 'Unlocked' | head -1)" "Unlocked"
check "lock screen: strip hidden" "$(lsk shown)" "False"
u "lockscreen/lock" 0.3; u "lockscreen/lock" 0.3; u "lockscreen/unlock" 0.3
check "lock screen: double lock, one unlock" "$(lsk locked)" "False"
sleep 2.5
u "set?dn.lockScreenWidgets=false&dn.unlockActivity=false" 0.8
u "lockscreen/lock" 1.2
check "lock screen: strip off" "$(lsk shown)" "False"
u "lockscreen/unlock" 0.3
check "lock screen: popup off" "$(state presentation | grep -c 'Unlocked')" "0"
u "set?dn.alertSounds=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$OLD_AS")&dn.lockScreenWidgets=$OLD_LW&dn.unlockActivity=$OLD_UA" 0.8
check "lock screen: sounds restored" "$(pref dn.alertSounds '')" "$OLD_AS"

echo "==> Settings pages"
PAGES="general appearance behavior popups allTools tabs home lockScreen knock nowPlaying calendar activity aiUsage timer clipboard quickSearch files screenshots hud battery connectivity permissions about"
for p in $PAGES; do
    rm -f "$SNAP/settings-$p.png"; u "snapshot-settings/$p" 1.4
    rendered "settings $p: renders" "$SNAP/settings-$p.png" 40000
done

echo
echo "ui-regression: $PASS passed, $FAIL failed"
exit $FAIL
