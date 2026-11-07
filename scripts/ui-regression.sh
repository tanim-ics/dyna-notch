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

# Test hooks need the per-launch secret the app writes for this user (docs/SECURITY.md).
TOKEN=$(cat "$HOME/Library/Application Support/DynaNotch/test-token" 2>/dev/null)
[ -n "$TOKEN" ] || { echo "No test token (is this build running?)"; exit 1; }
u() {   # u <hook>[?query] [sleep] — appends the token
    local sep="?"; case "$1" in *\?*) sep="&" ;; esac
    open -g "dynanotch://$1${sep}token=$TOKEN"; sleep "${2:-0.7}"
}
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
    OLD_HD=$(pref dn.hiddenDisplays '')
    KEYS=$(state displayKeys | python3 -c "import ast,sys; print(','.join(ast.literal_eval(sys.stdin.read())))")
    LAST=${KEYS##*,}
    u "set?dn.hiddenDisplays=$LAST" 2.0
    check "every display: display switched off" "$(islands x | cut -d' ' -f1)" "$((EXTRA - 1))"
    u "set?dn.hiddenDisplays=$KEYS" 2.0
    check "every display: all off falls back to all" "$(islands x | cut -d' ' -f1)" "$EXTRA"
    u "set?dn.hiddenDisplays=$OLD_HD" 2.0
    check "every display: display choice restored" "$(islands x | cut -d' ' -f1)" "$EXTRA"
fi
if [ "$EXTRA" -gt 0 ]; then
    rm -f "$SNAP/reg-extra.png"; u "snapshot-extra/reg-extra" 1.2
    rendered "every display: extra renders" "$SNAP/reg-extra.png" 2000
fi
u "set?dn.displayMode=followMouse" 1.5
check "follow mouse: single island" "$(islands x)" "0 0"
u "set?dn.displayMode=$OLD_DM&dn.showOnNonNotchDisplays=$OLD_NN" 1.5
check "show on: restored" "$(state displayMode)" "$OLD_DM"

echo "==> Popups stay under the pointer: whole message, Dismiss / Open, no panel"
CX=$(python3 -c "print($(state canvasWidth) / 2)")
u "ui/pointer?x=10&y=400" 0.8
u "notify?title=Regression&body=held%20under%20the%20pointer&duration=3" 0.6
u "ui/pointer?x=$CX&y=16" 1.0
check "popup: held on hover" "$(state holdsPopup)" "True"
check "popup: panel stays closed" "$(state presentation | cut -c1-8)" "activity"
sleep 3
check "popup: outlives its duration while hovered" "$(state presentation | grep -o 'held under' | head -1)" "held under"
u "ui/click?window=island&id=popup-dismiss" 1.0
check "popup: Dismiss" "$(state presentation | grep -c 'held under')" "0"
u "ui/pointer?x=10&y=400" 0.8
u "simulate/calendar" 0.6
u "ui/pointer?x=$CX&y=16" 1.0
u "ui/click?window=island&id=popup-open" 1.2
check "popup: Open goes to its tab" "$(state presentation) $(state selectedTab)" "expanded calendar"
u collapse 0.6; u "ui/pointer?x=10&y=400" 0.8
u "notify?title=Regression&body=released&duration=10" 0.6
u "ui/pointer?x=$CX&y=16" 0.8; u "ui/pointer?x=10&y=400" 2.2
check "popup: released after the pointer leaves" "$(state presentation | grep -c released)" "0"
u "ui/pointer" 0.3

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

echo "==> Copy progress pill (simulated progress; setting restored)"
cpk() { rm -f "$STATE"; u state 0.4; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('copy',{}).get(sys.argv[2], ''))" "$STATE" "$1" 2>/dev/null; }
OLD_CP=$(b dn.copyProgress true)
u "set?dn.copyProgress=true" 0.8
check "copy: watching folders" "$(cpk watching)" "True"
u "copy?name=Regression.mov&fraction=0.42&left=95" 0.6
check "copy: pill shows progress" "$(state presentation | grep -o 'fraction: 0.42' | head -1)" "fraction: 0.42"
rm -f "$SNAP/reg-copy.png"; u "snapshot/reg-copy" 1.0
rendered "copy: pill renders" "$SNAP/reg-copy.png" 3000
u "copy?done=1&name=Regression.mov" 0.4
check "copy: done" "$(state presentation | grep -o 'fraction: 1.0' | head -1)" "fraction: 1.0"
sleep 2
u "set?dn.copyProgress=false" 0.8
check "copy: off stops watching" "$(cpk subscriptions)" "0"
u "copy?name=Regression.mov&fraction=0.5" 0.6
check "copy: off shows nothing" "$(state presentation | grep -c fileCopy)" "0"
u "set?dn.copyProgress=$OLD_CP" 0.8

echo "==> Smart Copy conversions (clipboard saved and restored; setting restored)"
export LC_ALL=en_US.UTF-8
OLD_SC=$(b dn.smartCopy true); CLIP_BACKUP=$(pbpaste)
u "collapse" 2.5   # let the previous section's popups run out
u "set?dn.smartCopy=true" 0.6
u "ui/pointer?x=360&y=300" 0.5
u "convert?text=0x1F" 0.6
check "smart copy: hex shown" "$(state presentation | grep -o 'result: "31"' | head -1)" 'result: "31"'
u "convert?text=5%20mi" 0.6
check "smart copy: miles shown" "$(state presentation | grep -o 'source: "5 mi"' | head -1)" 'source: "5 mi"'
rm -f "$SNAP/reg-convert.png"; u "snapshot/reg-convert" 1.0
rendered "smart copy: renders" "$SNAP/reg-convert.png" 3000
u "convert?text=0x40" 0.5
u "ui/pointer?x=360&y=12" 0.5
check "smart copy: hover keeps it closed" "$(state presentation | grep -c conversion)" "1"
# The closed island may sit below the notch (Floating pill): click where it is drawn, not where it is laid out.
TOP=$(python3 -c "print(round(float('$(state topInset)' or 0)))")
u "ui/click?window=island&x=360&y=$((12 + TOP))" 0.5
check "smart copy: click copies result" "$(pbpaste)" "64"
check "smart copy: shows Copied" "$(state presentation | grep -o 'Copied' | head -1)" "Copied"
u "ui/pointer?x=360&y=300" 1.5
u "set?dn.smartCopy=false" 0.6
u "convert?text=0x1F" 0.6
check "smart copy: off shows nothing" "$(state presentation | grep -c conversion)" "0"
u "set?dn.smartCopy=$OLD_SC" 0.6
u "ui/pointer" 0.3
printf '%s' "$CLIP_BACKUP" | pbcopy
check "smart copy: clipboard restored" "$(pbpaste)" "$CLIP_BACKUP"

echo "==> Agent Island (installer on a copy; fake Claude Code requests; settings restored)"
agk() { rm -f "$STATE"; u state 0.4; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('agent',{}).get(sys.argv[2], ''))" "$STATE" "$1" 2>/dev/null; }
OLD_AI=$(b dn.agentIsland true); OLD_AS2=$(b dn.agentStatus true)
AGTMP=$(mktemp -d); cp ~/.claude/settings.json "$AGTMP/settings.json" 2>/dev/null || echo '{}' > "$AGTMP/settings.json"
u "set?dn.agentIsland=true&dn.agentStatus=true" 0.6
u "agent/install-test?settings=$AGTMP/settings.json" 1.0
check "agent: installer on a copy" "$(agk installTest)" "ok=true installed=true removed=true"
# Same content (the installer rewrites the copy with sorted keys, so bytes may differ).
check "agent: copy restored" "$(python3 -c "import json,sys,os; r=os.path.expanduser('~/.claude/settings.json'); print('same' if not os.path.exists(r) or json.load(open(sys.argv[1])) == json.load(open(r)) else 'differs')" "$AGTMP/settings.json" 2>/dev/null)" "same"
HOOK="$HOME/Library/Application Support/DynaNotch/hooks/agent-hook.pl"
check "agent: hook script runs" "$("$HOOK" check < /dev/null)" "ok"   # also warms up a freshly written script
REQ='{"session_id":"reg","cwd":"/tmp/regression","tool_name":"Bash","tool_input":{"command":"echo regression"}}'
# Wait until the card (and its button frames) are on screen: requests queue, the island shows the oldest.
agent_card() {   # waits until the card has finished opening (same frame twice); leaves state.json current
    local last="" now
    for _ in $(seq 1 20); do
        rm -f "$STATE"; u state 0.3; now="$(center agent-allow)"
        [ "$now" != "0 0" ] && [ "$now" = "$last" ] && return 0
        last="$now"
    done
    return 1
}
pkill -f "agent-hook.pl permission" 2>/dev/null; sleep 2.5   # start from an empty queue (the app drops dead hooks' requests)
for decision in allow deny terminal; do
    ( echo "$REQ" | "$HOOK" permission > "$AGTMP/out-$decision" ) &
    agent_card
    check "agent: $decision request shown" "$(state presentation | grep -o 'agentRequest' | head -1)" "agentRequest"
    u "ui/click?window=island&id=agent-$decision" 1.0
    if [ "$decision" = terminal ]; then
        check "agent: terminal hands back to Claude" "$(cat "$AGTMP/out-$decision")$(agk pending | grep -c regression)" "0"
    else
        check "agent: $decision reaches Claude" "$(grep -o "\"behavior\":\"$decision\"" "$AGTMP/out-$decision")" "\"behavior\":\"$decision\""
    fi
    sleep 2.6   # the short "Allowed" / "Denied" status
done
echo '{"session_id":"reg","cwd":"/tmp/regression","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift test"}}' | "$HOOK" status
sleep 0.6
check "agent: status in pill" "$(state presentation | grep -o 'Running swift test' | head -1)" "Running swift test"
u "set?dn.agentIsland=false" 0.6
check "agent: off answers nothing" "$(echo "$REQ" | "$HOOK" permission)" ""
u "set?dn.agentIsland=$OLD_AI&dn.agentStatus=$OLD_AS2" 0.6
u "ui/pointer" 0.3
rm -rf "$AGTMP"

echo "==> Drop Alchemy (files made in a temp folder, taken off the shelf afterwards)"
alk() { rm -f "$STATE"; u state 0.4; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('alchemy',{}).get(sys.argv[2], ''))" "$STATE" "$1" 2>/dev/null; }
alwait() { for _ in $(seq 1 30); do [ "$(alk running)" = "0" ] && return 0; sleep 0.5; done; return 1; }
OLD_AZ=$(b dn.alchemyZones true); ALTMP=$(mktemp -d); cp "/Library/User Pictures/Animals/Owl.heic" "$ALTMP/Owl.heic"
enc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1"; }
u "alchemy?action=png&path=$(enc "$ALTMP/Owl.heic")" 0.5; alwait
check "alchemy: png made" "$([ -f "$ALTMP/Owl.png" ] && echo yes)" "yes"
u "alchemy?action=cutout&path=$(enc "$ALTMP/Owl.heic")" 0.5; alwait
check "alchemy: cutout has transparency" "$(sips -g hasAlpha "$ALTMP/Owl (cutout).png" 2>/dev/null | grep -o 'yes')" "yes"
u "alchemy?action=shrink&path=$(enc "$ALTMP/Owl.png")" 0.5; alwait
SMALL=$(ls "$ALTMP" | grep '(small)' | head -1)
check "alchemy: shrink is smaller" "$(python3 -c "import os,sys;print('yes' if os.path.getsize(sys.argv[1])<os.path.getsize(sys.argv[2]) else 'no')" "$ALTMP/$SMALL" "$ALTMP/Owl.png" 2>/dev/null)" "yes"
u "alchemy?action=png&path=$(enc "$ALTMP/notes.txt")" 0.5
check "alchemy: wrong type refused" "$(alk last)" "failed png"
u "pin/shelf" 1.0
zones() { rm -f "$STATE"; u state 0.4; [ "$(center alchemy-cutout)" = "0.0 0.0" ] && echo hidden || echo shown; }
check "alchemy: zones on the shelf" "$(zones)" "shown"
u "set?dn.alchemyZones=false" 0.8
check "alchemy: zones off" "$(zones)" "hidden"
u "set?dn.alchemyZones=$OLD_AZ" 0.5
for f in "Owl.png" "Owl (cutout).png" "$SMALL"; do u "shelf/remove?path=$(enc "$ALTMP/$f")" 0.3; done
u "unpin" 0.5
rm -rf "$ALTMP"

echo "==> Camera Guard+ / Meeting Meter (simulated sensors; settings restored)"
prv() { rm -f "$STATE"; u state 0.4; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('privacy',{}).get(sys.argv[2], ''))" "$STATE" "$1" 2>/dev/null; }
OLD_MM=$(b dn.meetingMeter true); OLD_SD=$(b dn.sensorDot true)
u "set?dn.meetingMeter=true&dn.sensorDot=true" 0.5
u "sensor?kind=microphone&active=1&app=Regression" 0.6
check "sensor: popup names the app" "$(state presentation | grep -o 'app: "Regression"' | head -1)" 'app: "Regression"'
check "sensor: dot state" "$(prv inUse)" "['microphone']"
sleep 15.5
check "meeting: call after 15 s" "$(prv call)" "Regression since"
check "meeting: call in the pill" "$(state presentation | grep -o 'call(app: "Regression"' | head -1)" 'call(app: "Regression"'
u "sensor?kind=microphone&active=0" 0.6
check "meeting: call ends" "$(prv call)" "none"
check "sensor: logged" "$(prv log | grep -o 'microphone Regression closed' | head -1)" "microphone Regression closed"
u "set?dn.meetingMeter=false" 0.5
u "sensor?kind=microphone&active=1&app=Regression" 0.6; sleep 15.5
check "meeting: off, no call" "$(prv call)" "none"
u "sensor?kind=microphone&active=0" 0.5
u "sensor/forget?app=Regression" 0.3   # keep the owner's log clean
u "set?dn.meetingMeter=$OLD_MM&dn.sensorDot=$OLD_SD" 0.5

echo "==> Focus Guard / Soundscapes (silent: volume 0; timer stopped; settings restored)"
fk() { rm -f "$STATE"; u state 0.4; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('focus',{}).get(sys.argv[2], ''))" "$STATE" "$1" 2>/dev/null; }
OLD_FG=$(b dn.focusGuard true); OLD_SWP=$(b dn.soundscapeWithPomodoro true); OLD_VOL=$(pref dn.soundscapeVolume 0.4); OLD_SC=$(pref dn.soundscape none)
u "set?dn.focusGuard=true&dn.soundscapeVolume=0&dn.soundscapeWithPomodoro=false" 0.5
S0=$(fk shakes)
u "focusguard?app=com.tinyspeck.slackmacgap&name=Slack" 0.6
check "focus guard: idle without Pomodoro" "$(fk shakes)" "$S0"
u "ui/action?name=startPomodoro" 1.0
check "focus guard: focusing" "$(fk focusing)" "True"
u "focusguard?app=com.tinyspeck.slackmacgap&name=Slack" 0.6
check "focus guard: shakes" "$(fk shakes)" "$((S0 + 1))"
check "focus guard: nudge" "$(state presentation | grep -o 'Back to focus' | head -1)" "Back to focus"
u "focusguard?app=com.apple.dt.Xcode&name=Xcode" 0.5
check "focus guard: other apps fine" "$(fk current)" ""
u "soundscape/rain" 0.8
check "soundscape: plays" "$(fk playing)" "rain"
u "soundscape/stop" 1.5
check "soundscape: stops" "$(fk playing)" "none"
u "timer/stop" 0.5; u "collapse" 0.5
u "set?dn.focusGuard=$OLD_FG&dn.soundscapeWithPomodoro=$OLD_SWP&dn.soundscapeVolume=$OLD_VOL&dn.soundscape=$OLD_SC" 0.5

echo "==> Mac Vitals (alerts shown through the hook; setting restored)"
OLD_MV=$(b dn.macVitals true)
u "set?dn.macVitals=true" 0.5
u "vitals/disk" 0.6
check "vitals: disk alert" "$(state presentation | grep -o 'Your disk is almost full' | head -1)" "Your disk is almost full"
u "vitals/thermal" 0.6
check "vitals: heat alert" "$(state presentation | grep -o 'running hot' | head -1)" "running hot"
sleep 8.5
u "set?dn.macVitals=false" 0.5
u "vitals/memory" 0.6
check "vitals: off shows nothing" "$(state presentation | grep -c 'Memory is')" "0"
u "set?dn.macVitals=$OLD_MV" 0.5

echo "==> Daily Wrap (shown on demand; nothing changed)"
wk() { rm -f "$STATE"; u state 0.4; python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('wrap',{}).get(sys.argv[2], ''))" "$STATE" "$1" 2>/dev/null; }
u "collapse" 0.5
u "wrap" 3.0
check "wrap: card shown" "$(state presentation | grep -o 'wrap(lines' | head -1)" "wrap(lines"
check "wrap: next one scheduled" "$([ "$(wk next)" -gt "$(date +%s)" ] 2>/dev/null && echo yes)" "yes"
rm -f "$SNAP/reg-wrap.png"; u "snapshot/reg-wrap" 1.0
rendered "wrap: renders" "$SNAP/reg-wrap.png" 5000

echo "==> Voice Notes (timer command only — notes / reminders would touch the owner's data; timer stopped)"
u "collapse" 0.5
u "voice?text=set%20a%20timer%20for%2025%20minutes" 0.6
check "voice: timer command" "$(state presentation | grep -o 'Timer 25 min' | head -1)" "Timer 25 min"
check "voice: timer runs" "$(rm -f "$STATE"; u state 0.4; python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('timer',''))" "$STATE")" "countdown"
u "timer/stop" 3.0
u "voice?text=" 0.6
check "voice: nothing heard" "$(state presentation | grep -o "Didn" | head -1)" "Didn"

echo "==> Updates + What's New story (local file feed; never downloads or installs; GitHub feed restored)"
upd() { rm -f "$STATE"; u state 0.4; python3 -c "
import json,sys; u=json.load(open(sys.argv[1])).get('update',{}); v=u.get(sys.argv[2], u.get('story',{}).get(sys.argv[2], ''))
print(v)" "$STATE" "$1" 2>/dev/null; }
u "story/close" 0.6
u "whatsnew" 1.2
check "story: shown" "$(upd shown)" "True"
check "story: mode whatsNew" "$(upd mode)" "whatsNew"
check "story: first slide" "$(upd index)" "0"
u "story/next" 0.5;     check "story: next" "$(upd index)" "1"
u "story/previous" 0.5; check "story: previous" "$(upd index)" "0"
u "story/pause" 0.3; sleep 6.5
check "story: hold pauses" "$(upd index) $(upd paused)" "0 True"
u "story/resume" 0.3
rm -f "$SNAP/reg-story.png"; u "snapshot-whatsnew/reg-story" 1.0
rendered "story: renders" "$SNAP/reg-story.png" 20000
u "ui/click?window=whatsnew&id=whatsnew.skip" 0.8
check "story: skip → closing card" "$(upd title)" "final"
u "ui/click?window=whatsnew&id=whatsnew.done" 1.0
check "story: Got it closes" "$(upd shown)" "False"
check "story: version marked seen" "$(upd lastSeen)" "$(upd current)"
FEED=$(mktemp -d)
cat >"$FEED/newer.json" <<JSON
{"tag_name":"v99.0.0","html_url":"https://github.com/tanim-ics/dyna-notch/releases","draft":false,"prerelease":false,
 "body":"- **Regression**: a fake release","assets":[{"name":"DynaNotch-99.0.0.zip","browser_download_url":"file://$FEED/none.zip"}]}
JSON
sed 's/v99.0.0/v0.1.0/; s/99.0.0.zip/0.1.0.zip/' "$FEED/newer.json" >"$FEED/older.json"
u "update/feed?url=file://$FEED/newer.json" 0.3; u "update/check" 1.5
check "update: newer release found" "$(upd status) $(upd latest)" "available 99.0.0"
u "pin/home" 1.0
check "update: header pill" "$(state frames | grep -o 'header.update' | head -1)" "header.update"
u "ui/click?window=island&id=header.update" 1.2
check "update: story in update mode" "$(upd mode) $(upd title)" "update Regression"
u "story/close" 0.8
u "update/feed?url=file://$FEED/older.json" 0.3; u "update/check" 1.5
check "update: older release = up to date" "$(upd status)" "upToDate"
check "update: pill gone" "$(state frames | grep -c 'header.update')" "0"
u "update/feed?url=file://$FEED/missing.json" 0.3; u "update/check" 1.5
check "update: broken feed reports" "$(upd status)" "failed"
u "update/feed" 0.3; u "update/check" 3.0
u unpin 0.8
rm -rf "$FEED"

echo "==> Security: hooks without the token are refused"
OLD_HUD=$(b dn.hudEnabled true)
open -g "dynanotch://set?dn.hudEnabled=false"; sleep 0.8
check "security: set without token refused" "$(b dn.hudEnabled true)" "$OLD_HUD"
open -g "dynanotch://set?dn.hudEnabled=false&token=wrong"; sleep 0.8
check "security: set with wrong token refused" "$(b dn.hudEnabled true)" "$OLD_HUD"
rm -f "$STATE"; open -g "dynanotch://state"; sleep 0.8
check "security: state without token refused" "$([ -f "$STATE" ] && echo written || echo refused)" "refused"
u "ui/pointer?x=10&y=400" 0.6
open -g "dynanotch://notify?title=Public&body=hook&duration=3"; sleep 0.8
check "security: notify stays public" "$(state presentation | grep -o 'Public' | head -1)" "Public"
rm -f "$SNAP/evil.png" "$SNAP/../evil.png"; u "snapshot/..%2Fevil" 1.5
check "security: snapshot name can't leave Snapshots" "$([ -f "$SNAP/../evil.png" ] && echo escaped || echo kept)" "kept"
rm -f "$SNAP/evil.png" "$SNAP/.evil.png" "$SNAP/..evil.png"
check "security: token file private" "$(stat -f %Lp "$HOME/Library/Application Support/DynaNotch/test-token")" "600"
check "security: data folder private" "$(stat -f %Lp "$HOME/Library/Application Support/DynaNotch")" "700"

echo "==> Settings pages"
PAGES="general appearance behavior popups allTools tabs home lockScreen knock nowPlaying calendar activity aiUsage timer clipboard quickSearch files screenshots hud battery connectivity permissions about"
u "settings" 2.0   # open the Settings window once before the first snapshot
for p in $PAGES; do
    rm -f "$SNAP/settings-$p.png"; u "snapshot-settings/$p" 1.4
    rendered "settings $p: renders" "$SNAP/settings-$p.png" 40000
done

echo
echo "ui-regression: $PASS passed, $FAIL failed"
exit $FAIL
