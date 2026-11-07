#!/bin/bash
# release.sh — pack DynaNotch.app into the zip the Homebrew cask downloads, and point Casks/dynanotch.rb at it.
#
# Usage: scripts/release.sh [--publish]
#
#   (no flag)   build (ad hoc, no tests, no install), write build/DynaNotch-<version>.zip, update the cask's version
#               and sha256
#   --publish   also create GitHub release v<version> with the zip and WhatsNew.json (needs `gh` signed in; push the
#               cask change after)
#
# The version comes from CFBundleShortVersionString in Packaging/Info.plist — bump it there first and describe the new
# features in Packaging/WhatsNew.json (the What's New story; `swift test` checks the two match).

set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"

PUBLISH=0
case "${1:-}" in
    --publish) PUBLISH=1 ;;
    "") ;;
    *) echo "usage: scripts/release.sh [--publish]" >&2; exit 64 ;;
esac

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Packaging/Info.plist)"
ZIP="build/DynaNotch-$VERSION.zip"
CASK="Casks/dynanotch.rb"
NOTES_JSON="Packaging/WhatsNew.json"
NOTES_MD="build/release-notes.md"

# Release text from this version's WhatsNew.json entry ("- **Title**: text" lines).
/usr/bin/python3 -I - "$NOTES_JSON" "$VERSION" >"$NOTES_MD" <<'PY'
import json, sys
notes = json.load(open(sys.argv[1]))
entry = next((n for n in notes if n.get("version") == sys.argv[2]), None)
if entry is None:
    sys.exit("error: Packaging/WhatsNew.json has no entry for %s" % sys.argv[2])
if entry.get("headline"):
    print("## " + entry["headline"] + "\n")
for feature in entry["features"]:
    print("- **%s**: %s" % (feature["title"], feature.get("text", "")))
print("\nInstall: `brew install --cask tanim-ics/dyna-notch/dynanotch` — or click Update in DynaNotch.")
PY

# Ad hoc unless a Developer ID is available (docs/SECURITY.md). With RELEASE_IDENTITY (or a "Developer ID Application"
# identity in the Keychain) the app is signed with it; with NOTARY_PROFILE (an `xcrun notarytool store-credentials`
# profile) it is also notarised and stapled, and the updater then pins your team ID.
IDENTITY="${RELEASE_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep '"Developer ID Application' \
        | grep -oE '[0-9A-Fa-f]{40}' | head -n 1 || true)"
fi
SIGN_IDENTITY="${IDENTITY:--}" ./build.sh --skip-tests --no-install
if [ -n "$IDENTITY" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    NZIP="build/notarize-$VERSION.zip"
    ditto -c -k --keepParent build/DynaNotch.app "$NZIP"
    xcrun notarytool submit "$NZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple build/DynaNotch.app
    rm -f "$NZIP"
    echo "==> notarised and stapled"
fi

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/DynaNotch.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

# Sign the zip with the release key from the login Keychain (scripts/release-key.sh); installed apps refuse updates
# without a valid signature (docs/SECURITY.md).
SIG="$ZIP.sig"
security find-generic-password -s com.tanim.dynanotch.release-signing -a ed25519 >/dev/null 2>&1 \
    || { echo "error: no release signing key in the Keychain (run scripts/release-key.sh)" >&2; exit 1; }
security find-generic-password -s com.tanim.dynanotch.release-signing -a ed25519 -w \
    | swift scripts/release-tools/release-key.swift sign "$ZIP" >"$SIG"
echo "==> $SIG"

sed -i '' -E \
    -e "s/^(  version )\".*\"/\1\"$VERSION\"/" \
    -e "s/^(  sha256 )\".*\"/\1\"$SHA\"/" \
    "$CASK"
echo "==> $ZIP"
echo "    version $VERSION  sha256 $SHA  ($CASK updated)"

if [ "$PUBLISH" -eq 1 ]; then
    gh release create "v$VERSION" "$ZIP" "$SIG" "$NOTES_JSON" --title "DynaNotch $VERSION" --notes-file "$NOTES_MD"
    echo "==> published v$VERSION — commit and push $CASK so brew sees the new version"
fi
