#!/bin/bash
# scripts/check.sh — fast verification that runs on Linux and macOS.
#
#   1. swift build (DynaNotchCore on Linux; whole package on macOS)
#   2. swift test
#   3. swiftc -parse on every app source file and Packaging/make_icon.swift
#   4. clang -fsyntax-only on the MediaRemote adapter (only when Foundation headers exist, i.e. macOS)
#   5. bash -n on the shell scripts
#   6. Info.plist validation (python3 plistlib, plus plutil on macOS)
#
# Exits non-zero if any check fails. Compatible with bash 3.2.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

if [ -f /home/claude/swiftenv.sh ]; then
    # shellcheck disable=SC1091
    . /home/claude/swiftenv.sh
fi

PASSED=""
FAILED=""
SKIPPED=""
LOG_DIR="$ROOT/build/check-logs"
mkdir -p "$LOG_DIR"

section() { printf '\n==> %s\n' "$*"; }
pass()    { printf '    PASS  %s\n' "$1"; PASSED="$PASSED
  $1"; }
fail()    { printf '    FAIL  %s\n' "$1"; FAILED="$FAILED
  $1"; }
skip()    { printf '    SKIP  %s (%s)\n' "$1" "$2"; SKIPPED="$SKIPPED
  $1 ($2)"; }

# Runs "$@" with output captured to a log; prints the tail on failure.
run_logged() {
    name="$1"; log="$2"; shift 2
    if "$@" >"$log" 2>&1; then
        pass "$name"
        return 0
    fi
    fail "$name"
    echo "    ---- last 30 lines of $log ----"
    tail -n 30 "$log" | sed 's/^/    | /'
    return 1
}

HAVE_SWIFT=0
if command -v swift >/dev/null 2>&1; then
    HAVE_SWIFT=1
    printf 'Toolchain: %s\n' "$(swift --version 2>&1 | head -n 1)"
fi

# ---------------------------------------------------------------------------
section "Swift package build and tests"
if [ "$HAVE_SWIFT" -eq 1 ]; then
    if run_logged "swift build" "$LOG_DIR/build.log" swift build; then
        if run_logged "swift test" "$LOG_DIR/test.log" swift test; then
            EXECUTED="$(grep -E 'Executed [0-9]+ tests?' "$LOG_DIR/test.log" | tail -n 1 | sed 's/^ *//')"
            [ -n "$EXECUTED" ] && printf '          %s\n' "$EXECUTED"
        fi
    else
        skip "swift test" "build failed"
    fi
else
    skip "swift build" "swift not found"
    skip "swift test" "swift not found"
fi

# ---------------------------------------------------------------------------
section "swiftc -parse on app sources"
if command -v swiftc >/dev/null 2>&1; then
    PARSE_LIST="$LOG_DIR/parse-files.txt"
    {
        if [ -d Sources/DynaNotch ]; then
            find Sources/DynaNotch -type f -name '*.swift' | LC_ALL=C sort
        fi
        [ -f Packaging/make_icon.swift ] && echo Packaging/make_icon.swift
    } >"$PARSE_LIST"
    COUNT=0
    PARSE_FAIL=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        COUNT=$((COUNT + 1))
        if ! out="$(swiftc -parse "$f" 2>&1)"; then
            PARSE_FAIL=$((PARSE_FAIL + 1))
            printf '    parse error: %s\n' "$f"
            printf '%s\n' "$out" | head -n 20 | sed 's/^/    | /'
        fi
    done <"$PARSE_LIST"
    if [ "$COUNT" -eq 0 ]; then
        skip "swiftc -parse" "no app sources yet"
    elif [ "$PARSE_FAIL" -eq 0 ]; then
        pass "swiftc -parse ($COUNT files)"
    else
        fail "swiftc -parse ($PARSE_FAIL of $COUNT files)"
    fi
else
    skip "swiftc -parse" "swiftc not found"
fi

# ---------------------------------------------------------------------------
section "Objective-C adapter syntax"
ADAPTER="Adapter/MediaRemoteAdapter.m"
if [ ! -f "$ADAPTER" ]; then
    fail "adapter source missing ($ADAPTER)"
elif ! command -v clang >/dev/null 2>&1; then
    skip "clang -fsyntax-only" "clang not found"
elif ! printf '#import <Foundation/Foundation.h>\nint main(void){return 0;}\n' \
        | clang -x objective-c -fsyntax-only - >/dev/null 2>&1; then
    skip "clang -fsyntax-only" "Foundation headers unavailable (not macOS)"
else
    run_logged "clang -fsyntax-only $ADAPTER" "$LOG_DIR/adapter.log" \
        clang -fsyntax-only -fobjc-arc -mmacosx-version-min=14.0 "$ADAPTER"
fi

# ---------------------------------------------------------------------------
section "Shell script syntax"
for s in build.sh build_dmg.sh scripts/check.sh; do
    if [ ! -f "$s" ]; then
        fail "bash -n $s (missing)"
    elif out="$(bash -n "$s" 2>&1)"; then
        pass "bash -n $s"
    else
        fail "bash -n $s"
        printf '%s\n' "$out" | sed 's/^/    | /'
    fi
done
if command -v shellcheck >/dev/null 2>&1; then
    run_logged "shellcheck" "$LOG_DIR/shellcheck.log" shellcheck -S warning build.sh build_dmg.sh scripts/check.sh
else
    skip "shellcheck" "not installed"
fi

# ---------------------------------------------------------------------------
section "Info.plist"
PLIST="Packaging/Info.plist"
if [ ! -f "$PLIST" ]; then
    fail "$PLIST missing"
else
    if command -v python3 >/dev/null 2>&1; then
        if out="$(python3 -I - "$PLIST" 2>&1 <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as fh:
    p = plistlib.load(fh)
expected = {
    "CFBundleExecutable": "DynaNotch",
    "CFBundleIdentifier": "com.tanim.dynanotch",
    "CFBundleName": "DynaNotch",
    "CFBundleDisplayName": "DynaNotch",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "2.0.0",
    "CFBundleVersion": "200",
    "CFBundleIconFile": "AppIcon",
    "LSMinimumSystemVersion": "14.0",
    "LSUIElement": True,
    "NSPrincipalClass": "NSApplication",
    "NSHighResolutionCapable": True,
    "LSApplicationCategoryType": "public.app-category.utilities",
}
problems = []
for k, v in expected.items():
    if p.get(k) != v:
        problems.append("%s = %r (expected %r)" % (k, p.get(k), v))
for k in ("NSAppleEventsUsageDescription", "NSBluetoothAlwaysUsageDescription",
          "NSCalendarsFullAccessUsageDescription", "NSCalendarsUsageDescription",
          "NSHumanReadableCopyright"):
    if not isinstance(p.get(k), str) or not p.get(k):
        problems.append("%s missing" % k)
for k, v in p.items():
    if isinstance(v, str) and "$(" in v:
        problems.append("%s contains unexpanded variable %r" % (k, v))
if problems:
    print("\n".join(problems))
    sys.exit(1)
print("%d keys OK" % len(p))
PY
)"; then
            pass "plistlib $PLIST ($out)"
        else
            fail "plistlib $PLIST"
            printf '%s\n' "$out" | sed 's/^/    | /'
        fi
    else
        skip "plistlib" "python3 not found"
    fi
    if [ "$(uname -s)" = "Darwin" ] && command -v plutil >/dev/null 2>&1; then
        run_logged "plutil -lint $PLIST" "$LOG_DIR/plutil.log" plutil -lint "$PLIST"
    fi
fi

# ---------------------------------------------------------------------------
printf '\n================ Summary ================\n'
[ -n "$PASSED" ]  && printf 'Passed:%s\n' "$PASSED"
[ -n "$SKIPPED" ] && printf 'Skipped:%s\n' "$SKIPPED"
if [ -n "$FAILED" ]; then
    printf 'Failed:%s\n' "$FAILED"
    printf '\ncheck.sh: FAILED\n'
    exit 1
fi
printf '\ncheck.sh: all checks passed\n'
exit 0
