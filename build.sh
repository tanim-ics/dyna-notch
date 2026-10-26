#!/bin/bash
# build.sh — DynaNotch: test -> adapter -> build -> bundle -> icon -> sign -> install -> launch (DMG optional).
#
# Usage: ./build.sh [--no-install] [--dmg] [--debug] [--skip-tests] [--help]
#
# Environment:
#   SIGN_IDENTITY   codesign identity (name or SHA-1 hash). Default: first "Apple Development"
#                   identity in your keychain, otherwise ad-hoc ("-").
#
# Compatible with macOS /bin/bash 3.2.

set -euo pipefail

APP_NAME="DynaNotch"
BUNDLE_ID="com.tanim.dynanotch"
MIN_MACOS="14.0"

DO_INSTALL=1
DO_DMG=0
DO_TESTS=1
CONFIG="release"

usage() {
    cat <<EOF
Usage: ./build.sh [options]

Builds DynaNotch.app, signs it, installs it to /Applications and launches it.

Options:
  --no-install   Do not copy to /Applications or launch the app
  --dmg          Also create DynaNotch.dmg (to copy the app to another Mac)
  --debug        Build the debug configuration instead of release
  --skip-tests   Skip 'swift test'
  -h, --help     Show this help

Environment:
  SIGN_IDENTITY  Code-signing identity to use (default: first "Apple Development"
                 certificate, else ad-hoc). Example:
                 SIGN_IDENTITY="Apple Development: Jane Doe (ABCDE12345)" ./build.sh

Outputs:
  build/DynaNotch.app, build/logs/*.log, and DynaNotch.dmg with --dmg
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --no-install) DO_INSTALL=0 ;;
        --dmg)        DO_DMG=1 ;;
        --no-dmg)     DO_DMG=0 ;;   # default; kept for old habits
        --debug)      CONFIG="debug" ;;
        --skip-tests) DO_TESTS=0 ;;
        -h|--help)    usage; exit 0 ;;
        *)
            echo "error: unknown option '$1'" >&2
            echo "Run ./build.sh --help for usage." >&2
            exit 64
            ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Output helpers (no colours when not a terminal)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_BOLD="$(printf '\033[1m')"; C_YEL="$(printf '\033[33m')"; C_RED="$(printf '\033[31m')"
    C_GRN="$(printf '\033[32m')"; C_OFF="$(printf '\033[0m')"
else
    C_BOLD=""; C_YEL=""; C_RED=""; C_GRN=""; C_OFF=""
fi

STEP_NO=0
step() { STEP_NO=$((STEP_NO + 1)); printf '\n%s==> [%d] %s%s\n' "$C_BOLD" "$STEP_NO" "$*" "$C_OFF"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %sOK%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '    %sWARNING:%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '\n%sERROR:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

on_exit() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '\n%sBuild failed (exit %d) at step %d.%s Logs: %s\n' "$C_RED" "$rc" "$STEP_NO" "$C_OFF" "${LOG_DIR:-build/logs}" >&2
    fi
}
trap on_exit EXIT

# ---------------------------------------------------------------------------
# a. Environment
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR="$SCRIPT_DIR/build"
LOG_DIR="$BUILD_DIR/logs"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$SCRIPT_DIR/$APP_NAME.dmg"
mkdir -p "$LOG_DIR"

step "Checking toolchain"
if [ "$(uname -s)" != "Darwin" ]; then
    die "build.sh must run on macOS (found $(uname -s)). On Linux use scripts/check.sh."
fi
if ! command -v swift >/dev/null 2>&1; then
    die "'swift' not found. Install Xcode 16 from the App Store (recommended) or run: xcode-select --install"
fi
if ! command -v xcrun >/dev/null 2>&1; then
    die "'xcrun' not found. Install the Command Line Tools with: xcode-select --install"
fi
SWIFT_VERSION_LINE="$(swift --version 2>&1 | head -n 1 || true)"
info "$SWIFT_VERSION_LINE"
info "Developer dir: $(xcode-select -p 2>/dev/null || echo unknown)"
info "Configuration: $CONFIG    macOS $(sw_vers -productVersion 2>/dev/null || echo '?') on $(uname -m)"

# ---------------------------------------------------------------------------
# b. Tests
# ---------------------------------------------------------------------------
if [ "$DO_TESTS" -eq 1 ]; then
    step "Running unit tests (swift test --filter DynaNotchCoreTests)"
    TEST_LOG="$LOG_DIR/test.log"
    info "first run compiles the whole package in debug; this can take a minute (log: build/logs/test.log)"
    set +e
    swift test --filter DynaNotchCoreTests >"$TEST_LOG" 2>&1
    TEST_RC=$?
    set -e
    if [ "$TEST_RC" -eq 0 ]; then
        SUMMARY="$(grep -E 'Executed [0-9]+ tests?' "$TEST_LOG" | tail -n 1 || true)"
        ok "${SUMMARY:-tests passed}"
    elif grep -qE "no such module 'XCTest'|XCTest.*(not found|unavailable|not available)|(unable to find|could not find|cannot find).*XCTest" "$TEST_LOG"; then
        warn "XCTest is not available with this toolchain (Command Line Tools only?)."
        warn "Skipping tests. Install full Xcode to run them, or pass --skip-tests to silence this."
    else
        echo "----- last 40 lines of $TEST_LOG -----" >&2
        tail -n 40 "$TEST_LOG" >&2 || true
        echo "--------------------------------------" >&2
        die "Unit tests failed (see $TEST_LOG). Fix them or re-run with --skip-tests."
    fi
else
    step "Skipping unit tests (--skip-tests)"
fi

# ---------------------------------------------------------------------------
# c. MediaRemote adapter dylib
# ---------------------------------------------------------------------------
step "Building MediaRemote adapter (libMediaRemoteAdapter.dylib)"
ADAPTER_SRC="Adapter/MediaRemoteAdapter.m"
ADAPTER_OUT="$BUILD_DIR/libMediaRemoteAdapter.dylib"
ADAPTER_LOG="$LOG_DIR/adapter.log"
ADAPTER_FALLBACK="Packaging/libMediaRemoteAdapter.dylib"
rm -f "$ADAPTER_OUT"
: >"$ADAPTER_LOG"

build_adapter() {
    # $@ = arch flags
    xcrun clang -dynamiclib -fobjc-arc -O2 "$@" -mmacosx-version-min="$MIN_MACOS" \
        -framework Foundation -o "$ADAPTER_OUT" "$ADAPTER_SRC" >>"$ADAPTER_LOG" 2>&1
}

if [ ! -f "$ADAPTER_SRC" ]; then
    warn "$ADAPTER_SRC is missing."
    ADAPTER_BUILT=0
elif build_adapter -arch arm64 -arch x86_64; then
    ok "universal (arm64 + x86_64)"
    ADAPTER_BUILT=1
else
    warn "universal build failed, retrying for $(uname -m) only"
    if build_adapter -arch "$(uname -m)"; then
        ok "$(uname -m) only"
        ADAPTER_BUILT=1
    else
        ADAPTER_BUILT=0
    fi
fi
if [ "$ADAPTER_BUILT" -eq 0 ]; then
    if [ -f "$ADAPTER_FALLBACK" ]; then
        warn "Could not compile the adapter (see $ADAPTER_LOG); using prebuilt $ADAPTER_FALLBACK."
        cp "$ADAPTER_FALLBACK" "$ADAPTER_OUT"
        chmod u+w "$ADAPTER_OUT"
    else
        die "Could not compile the adapter and $ADAPTER_FALLBACK is missing (see $ADAPTER_LOG)."
    fi
fi

# ---------------------------------------------------------------------------
# d. Swift build
# ---------------------------------------------------------------------------
step "Building $APP_NAME (swift build -c $CONFIG)"
SWIFT_LOG="$LOG_DIR/swift-build.log"
set +e
swift build -c "$CONFIG" --product "$APP_NAME" 2>&1 | tee "$SWIFT_LOG" | sed 's/^/    /'
BUILD_RC=${PIPESTATUS[0]}
set -e
if [ "$BUILD_RC" -ne 0 ]; then
    echo "----- errors from $SWIFT_LOG -----" >&2
    grep -E 'error:' "$SWIFT_LOG" | head -n 40 >&2 || tail -n 40 "$SWIFT_LOG" >&2 || true
    echo "----------------------------------" >&2
    die "swift build failed (full log: $SWIFT_LOG). If the error mentions a stale module or cache, try: rm -rf .build"
fi
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
if [ ! -x "$BINARY" ]; then
    die "Expected binary not found at $BINARY"
fi
ok "$BINARY"

# ---------------------------------------------------------------------------
# f. Icon (done before bundling so it can be copied in)
# ---------------------------------------------------------------------------
step "App icon"
ICON_SCRIPT="Packaging/make_icon.swift"
ICONSET="$BUILD_DIR/AppIcon.iconset"
ICNS="$BUILD_DIR/AppIcon.icns"
ICON_LOG="$LOG_DIR/icon.log"
if [ -f "$ICNS" ] && [ -f "$ICON_SCRIPT" ] && [ "$ICNS" -nt "$ICON_SCRIPT" ]; then
    ok "cached ($ICNS is newer than $ICON_SCRIPT)"
elif [ ! -f "$ICON_SCRIPT" ]; then
    warn "$ICON_SCRIPT missing; the app will use the generic icon."
else
    rm -rf "$ICONSET" "$ICNS"
    : >"$ICON_LOG"
    ICON_OK=0
    if swift "$ICON_SCRIPT" "$ICONSET" >>"$ICON_LOG" 2>&1; then
        ICON_OK=1
    else
        # Fallback: compile the script instead of interpreting it.
        info "interpreting make_icon.swift failed, trying swiftc"
        if xcrun swiftc -O -o "$BUILD_DIR/make_icon" "$ICON_SCRIPT" >>"$ICON_LOG" 2>&1 \
            && "$BUILD_DIR/make_icon" "$ICONSET" >>"$ICON_LOG" 2>&1; then
            ICON_OK=1
        fi
    fi
    if [ "$ICON_OK" -eq 1 ] && iconutil -c icns "$ICONSET" -o "$ICNS" >>"$ICON_LOG" 2>&1; then
        ok "$ICNS"
    else
        rm -f "$ICNS"
        warn "Icon generation failed (see $ICON_LOG); the app will use the generic icon."
    fi
fi

# ---------------------------------------------------------------------------
# e. Bundle
# ---------------------------------------------------------------------------
step "Assembling $APP_DIR"
[ -f "Packaging/Info.plist" ] || die "Packaging/Info.plist is missing."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod 644 "$APP_DIR/Contents/Info.plist"
printf 'APPL????' >"$APP_DIR/Contents/PkgInfo"
cp "$ADAPTER_OUT" "$APP_DIR/Contents/Resources/libMediaRemoteAdapter.dylib"
chmod 644 "$APP_DIR/Contents/Resources/libMediaRemoteAdapter.dylib"
if [ -f "$ICNS" ]; then
    cp "$ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
# SwiftPM resource bundles (none expected today; harmless).
for bundle in "$BIN_DIR"/*.bundle; do
    [ -d "$bundle" ] || continue
    info "resource bundle: $(basename "$bundle")"
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
if command -v plutil >/dev/null 2>&1; then
    plutil -lint -s "$APP_DIR/Contents/Info.plist" || die "Info.plist failed plutil -lint."
fi
ok "bundle assembled"

# ---------------------------------------------------------------------------
# g. Code signing
# ---------------------------------------------------------------------------
step "Code signing"
SIGN_LOG="$LOG_DIR/codesign.log"
: >"$SIGN_LOG"
IDENTITY="${SIGN_IDENTITY:-}"
IDENTITY_DESC=""
if [ -n "$IDENTITY" ]; then
    IDENTITY_DESC="\$SIGN_IDENTITY ($IDENTITY)"
else
    IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep '"Apple Development' | head -n 1 || true)"
    if [ -n "$IDENTITY_LINE" ]; then
        IDENTITY="$(printf '%s\n' "$IDENTITY_LINE" | grep -oE '[0-9A-Fa-f]{40}' | head -n 1 || true)"
        IDENTITY_NAME="$(printf '%s\n' "$IDENTITY_LINE" | sed -n 's/.*"\(.*\)".*/\1/p')"
        IDENTITY_DESC="$IDENTITY_NAME ($IDENTITY)"
    fi
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY="-"
    IDENTITY_DESC="ad-hoc (-)"
fi

sign_all() {
    # $1 = identity
    # Ad-hoc signatures default to a cdhash designated requirement, which changes on every build, so
    # macOS privacy permissions (Calendar, Reminders, Camera, Accessibility …) were forgotten after
    # each rebuild. An explicit identifier-only requirement keeps the app's identity stable.
    local req_args=()
    if [ "$1" = "-" ]; then
        req_args=(--requirements "=designated => identifier \"$BUNDLE_ID\"")
    fi
    codesign --force --sign "$1" --timestamp=none \
        "$APP_DIR/Contents/Resources/libMediaRemoteAdapter.dylib" >>"$SIGN_LOG" 2>&1 \
    && codesign --force --sign "$1" --identifier "$BUNDLE_ID" --timestamp=none ${req_args[@]+"${req_args[@]}"} \
        "$APP_DIR" >>"$SIGN_LOG" 2>&1
}

info "identity: $IDENTITY_DESC"
if ! sign_all "$IDENTITY"; then
    if [ "$IDENTITY" != "-" ]; then
        warn "Signing with $IDENTITY_DESC failed (see $SIGN_LOG; a locked keychain is a common cause)."
        warn "Falling back to ad-hoc signing."
        IDENTITY="-"
        IDENTITY_DESC="ad-hoc (-)"
        sign_all "-" || die "Ad-hoc signing failed too (see $SIGN_LOG)."
    else
        die "codesign failed (see $SIGN_LOG)."
    fi
fi
if codesign --verify --strict "$APP_DIR" >>"$SIGN_LOG" 2>&1; then
    ok "signed with $IDENTITY_DESC"
else
    warn "codesign --verify reported a problem (see $SIGN_LOG); continuing."
fi
if [ "$IDENTITY" = "-" ]; then
    info "Ad-hoc signed with a stable requirement: permissions granted once survive rebuilds."
fi

# ---------------------------------------------------------------------------
# h. DMG
# ---------------------------------------------------------------------------
if [ "$DO_DMG" -eq 1 ]; then
    step "Creating $APP_NAME.dmg"
    STAGING="$BUILD_DIR/dmg-staging"
    DMG_LOG="$LOG_DIR/dmg.log"
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    ditto "$APP_DIR" "$STAGING/$APP_NAME.app"
    ln -s /Applications "$STAGING/Applications"
    rm -f "$DMG_PATH"
    if hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >"$DMG_LOG" 2>&1; then
        ok "$DMG_PATH ($(du -h "$DMG_PATH" | cut -f1 | tr -d ' '))"
    else
        warn "hdiutil failed (see $DMG_LOG). The app itself is fine at $APP_DIR."
    fi
    rm -rf "$STAGING"
else
    :   # DMG only with --dmg
fi

# ---------------------------------------------------------------------------
# i. Install and launch
# ---------------------------------------------------------------------------
INSTALLED_APP=""
install_to() {
    # $1 = destination directory; returns non-zero if it cannot be used
    dest_dir="$1"
    mkdir -p "$dest_dir" 2>/dev/null || return 1
    [ -w "$dest_dir" ] || return 1
    if [ -e "$dest_dir/$APP_NAME.app" ]; then
        rm -rf "$dest_dir/$APP_NAME.app" 2>/dev/null || return 1
    fi
    ditto "$APP_DIR" "$dest_dir/$APP_NAME.app" || return 1
    INSTALLED_APP="$dest_dir/$APP_NAME.app"
    return 0
}

if [ "$DO_INSTALL" -eq 1 ]; then
    step "Installing and launching"
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        info "quitting the running $APP_NAME"
    fi
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5

    if install_to "/Applications"; then
        :
    else
        warn "/Applications is not writable (or the old app could not be removed); using ~/Applications."
        install_to "$HOME/Applications" || die "Could not install to ~/Applications either."
        if [ -e "/Applications/$APP_NAME.app" ]; then
            warn "An older /Applications/$APP_NAME.app still exists; delete it to avoid launching the wrong copy."
        fi
    fi
    xattr -dr com.apple.quarantine "$INSTALLED_APP" 2>/dev/null || true
    ok "installed to $INSTALLED_APP"
    open "$INSTALLED_APP" || die "Could not launch $INSTALLED_APP"
    ok "launched"
else
    step "Skipping install (--no-install)"
    info "Run it with: open \"$APP_DIR\""
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n%sDone.%s\n' "$C_BOLD" "$C_OFF"
info "App:      ${INSTALLED_APP:-$APP_DIR}"
if [ "$DO_DMG" -eq 1 ] && [ -f "$DMG_PATH" ]; then
    info "DMG:      $DMG_PATH"
fi
info "Signed:   $IDENTITY_DESC"
cat <<EOF

The island is at the top of your screen; settings are in the menu-bar icon.
macOS asks for permissions as features need them. For the volume/brightness HUD and
click-to-paste, enable DynaNotch in System Settings > Privacy & Security > Accessibility.
EOF
