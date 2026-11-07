#!/bin/bash
# sanitize.sh — run DynaNotch under Address Sanitizer and Thread Sanitizer through a scripted session
# (docs/SECURITY.md, CLAUDE.md §5). Builds each variant in its own scratch path, runs it as a copy of the app (the
# installed app is quit for the run and relaunched after), drives it through the control socket, and fails on any
# sanitizer report. Usage: scripts/sanitize.sh [address|thread] (default: both).
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
KINDS=("${1:-address}" ); [ -z "${1:-}" ] && KINDS=(address thread)
WORK="$(mktemp -d)"
SOCK="$HOME/Library/Application Support/DynaNotch/control.sock"
FAILED=0
u() { printf 'dynanotch://%s\n' "$1" | nc -U "$SOCK" >/dev/null 2>&1; sleep "${2:-0.6}"; }

relaunch_installed() { open -g -a /Applications/DynaNotch.app; }
trap relaunch_installed EXIT

for kind in "${KINDS[@]}"; do
    echo "==> $kind sanitizer: building"
    scratch=".build-${kind:0:1}san"
    swift build -c debug --scratch-path "$scratch" --product DynaNotch -Xswiftc "-sanitize=$kind" >"$WORK/build-$kind.log" 2>&1 \
        || { echo "  build failed (see $WORK/build-$kind.log)"; FAILED=1; continue; }
    swift build -c debug --scratch-path "$scratch" --product DynaNotchWorker >>"$WORK/build-$kind.log" 2>&1
    bin="$(swift build -c debug --scratch-path "$scratch" --show-bin-path)"
    app="$WORK/DynaNotch-$kind.app"
    ditto /Applications/DynaNotch.app "$app"
    cp "$bin/DynaNotch" "$app/Contents/MacOS/DynaNotch"
    cp "$bin/DynaNotchWorker" "$app/Contents/MacOS/DynaNotchWorker"
    # Test copy only: no hardened runtime, so the toolchain's sanitizer runtime may load.
    codesign --force -s - --identifier com.tanim.dynanotch.worker "$app/Contents/MacOS/DynaNotchWorker" 2>/dev/null
    codesign --force -s - --identifier com.tanim.dynanotch --requirements '=designated => identifier "com.tanim.dynanotch"' "$app" 2>/dev/null
    reports="$WORK/$kind-reports"; mkdir -p "$reports"
    osascript -e 'quit app "DynaNotch"' 2>/dev/null; pkill -x DynaNotch 2>/dev/null; sleep 1.5
    opts="log_path=$reports/report:halt_on_error=0"
    open -n -a "$app" --env ASAN_OPTIONS="$opts" --env TSAN_OPTIONS="$opts" --env UBSAN_OPTIONS="$opts"
    for _ in $(seq 1 40); do [ -S "$SOCK" ] && break; sleep 0.5; done
    echo "==> $kind sanitizer: driving a session"
    sleep 3
    for t in home nowPlaying timer clipboard shelf notes system calendar quickSettings; do u "pin/$t" 1.0; done
    u unpin 0.8
    for demo in volume brightness airpods lowBattery peek calendar notification; do u "simulate/$demo" 0.8; done
    u "notify?title=Sanitizer&body=hold%20me&duration=5" 0.5
    u "ui/pointer?x=360&y=16" 1.2; u "ui/pointer?x=10&y=400" 2.0; u "ui/pointer" 0.3
    u "convert?text=0x1F" 0.6; u "timer/1" 1.0; u "timer/stop" 0.5
    img="$WORK/shot.png"; cp "$HOME/Library/Application Support/DynaNotch/Snapshots/popup-held.png" "$img" 2>/dev/null \
        && { u "alchemy?action=png&path=$img" 4; u "alchemy?action=cutout&path=$img" 6; }
    u state 1.0; u "snapshot/sanitizer" 1.5
    pkill -x DynaNotch 2>/dev/null; sleep 2
    if ls "$reports"/report* >/dev/null 2>&1; then
        echo "  REPORTS:"; grep -hE "^(==|WARNING|SUMMARY)" "$reports"/report* | sort | uniq -c | head -20
        FAILED=1
    else
        echo "  clean (no $kind sanitizer reports)"
    fi
done
echo "==> logs and reports in $WORK"
exit $FAILED
