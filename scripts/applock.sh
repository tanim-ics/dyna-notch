# scripts/applock.sh — a lock around "build.sh + install + UI test" so parallel agents don't drive the one installed
# app at the same time.   Usage: source scripts/applock.sh; applock <name>; ./build.sh; …tests…; appunlock
LOCKDIR="${TMPDIR:-/tmp}/app-under-test.lock"
applock() {
  local waited=0
  until mkdir "$LOCKDIR" 2>/dev/null; do
    # a lock older than 15 min is stale (its owner died) and is broken
    if [ -n "$(find "$LOCKDIR" -maxdepth 0 -mmin +15 2>/dev/null)" ]; then rm -rf "$LOCKDIR"; continue; fi
    sleep 5; waited=$((waited + 5))
    [ $waited -ge 1200 ] && { echo "applock: gave up after 20 min (held by $(cat "$LOCKDIR/owner" 2>/dev/null))"; return 1; }
  done
  echo "${1:-agent} $(date +%T)" > "$LOCKDIR/owner"; echo "applock: acquired by ${1:-agent}"
}
appunlock() { rm -rf "$LOCKDIR"; echo "applock: released"; }
