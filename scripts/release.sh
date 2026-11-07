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

# Always ad hoc: the stable identifier requirement is what keeps permissions across brew upgrades.
SIGN_IDENTITY="-" ./build.sh --skip-tests --no-install

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/DynaNotch.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

sed -i '' -E \
    -e "s/^(  version )\".*\"/\1\"$VERSION\"/" \
    -e "s/^(  sha256 )\".*\"/\1\"$SHA\"/" \
    "$CASK"
echo "==> $ZIP"
echo "    version $VERSION  sha256 $SHA  ($CASK updated)"

if [ "$PUBLISH" -eq 1 ]; then
    gh release create "v$VERSION" "$ZIP" "$NOTES_JSON" --title "DynaNotch $VERSION" --notes-file "$NOTES_MD"
    echo "==> published v$VERSION — commit and push $CASK so brew sees the new version"
fi
