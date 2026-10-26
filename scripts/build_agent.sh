#!/bin/bash
# build_agent.sh — lets Claude build, test and read logs on this Mac while you watch.
#
# Run it in Terminal:   ~/Desktop/dyna-notch/scripts/build_agent.sh
# Stop it with Ctrl-C.
#
# Claude cannot run macOS commands directly. Instead it drops a request file into
# .agent/request (inside this repo); this script picks it up, runs ONE of the fixed
# commands below (never arbitrary commands), and writes the output to .agent/.
#
#   build   swift build (debug)                 test    swift test --filter DynaNotchCoreTests
#   full    ./build.sh --no-dmg (installs+runs) logs    last 3 min of DynaNotch logs
#   crash   newest DynaNotch crash report       status  app running? permissions hints
#   quit    quits DynaNotch                    ourlogs only DynaNotch's own log lines
#   screen  screenshot of every display (needs Screen Recording for Terminal)
#   expand / collapse / settings / demo-<name>  drive the running app via dynanotch:// URLs

set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
AGENT="$ROOT/.agent"
mkdir -p "$AGENT"
echo "build_agent: watching $AGENT/request  (Ctrl-C to stop)"

run() {
  local mode="$1" out="$AGENT/result.log" code=0
  : > "$out"
  echo "== $mode @ $(date '+%H:%M:%S')" | tee -a "$out"
  case "$mode" in
    build)  swift build 2>&1 | tee -a "$out"; code=${PIPESTATUS[0]} ;;
    test)   swift test --filter DynaNotchCoreTests 2>&1 | tee -a "$out"; code=${PIPESTATUS[0]} ;;
    full)   ./build.sh --no-dmg 2>&1 | tee -a "$out"; code=${PIPESTATUS[0]} ;;
    logs)   log show --last 3m --style compact --info --debug \
              --predicate 'subsystem == "com.tanim.dynanotch" OR process == "DynaNotch"' 2>&1 | tail -400 | tee -a "$out" ;;
    crash)  f=$(ls -t "$HOME"/Library/Logs/DiagnosticReports/DynaNotch* 2>/dev/null | head -1)
            if [ -n "$f" ]; then echo "$f" >> "$out"; head -250 "$f" >> "$out"; else echo "no crash reports" >> "$out"; fi ;;
    status) { pgrep -lx DynaNotch || echo "DynaNotch not running"; pgrep -lf libMediaRemoteAdapter || echo "adapter not running";
              sw_vers; xcodebuild -version 2>/dev/null | head -2; swift --version 2>&1 | head -1; } >> "$out" 2>&1 ;;
    ourlogs) log show --last 5m --style compact --info --debug \
              --predicate 'subsystem == "com.tanim.dynanotch"' 2>&1 | tail -300 | tee -a "$out" ;;
    screen) rm -f "$AGENT"/screen*.png
            screencapture -x "$AGENT/screen1.png" "$AGENT/screen2.png" "$AGENT/screen3.png" >> "$out" 2>&1; code=$?
            ls -la "$AGENT"/screen*.png >> "$out" 2>&1 ;;
    expand|collapse|settings) open "dynanotch://$mode" >> "$out" 2>&1; code=$? ;;
    demo-*) name="$(echo "${mode#demo-}" | tr -cd 'a-zA-Z')"
            open "dynanotch://simulate/$name" >> "$out" 2>&1; code=$? ;;
    quit)   pkill -x DynaNotch && echo "quit" >> "$out" || echo "not running" >> "$out" ;;
    *)      echo "unknown mode: $mode" >> "$out"; code=2 ;;
  esac
  echo "$code" > "$AGENT/exit_code"
  echo "== done: $mode exit=$code" | tee -a "$out"
}

while true; do
  if [ -f "$AGENT/request" ]; then
    mode="$(tr -d '[:space:]' < "$AGENT/request")"
    rm -f "$AGENT/request" "$AGENT/exit_code"
    run "$mode"
  fi
  sleep 1
done
