#!/bin/bash
# release.sh — pack DynaNotch.app into the zip the Homebrew cask downloads, and point Casks/dynanotch.rb at it.
#
# Usage: scripts/release.sh [--publish]
#
#   (no flag)   build (ad hoc, no tests, no install), write build/DynaNotch-<version>.zip, update the cask's version
#               and sha256
#   --publish   also create GitHub release v<version> with the zip (needs `gh` signed in; push the cask change after)
#
# The version comes from CFBundleShortVersionString in Packaging/Info.plist — bump it there first.

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
    gh release create "v$VERSION" "$ZIP" --title "DynaNotch $VERSION" \
        --notes "Install: brew install --cask tanim-ics/dyna-notch/dynanotch"
    echo "==> published v$VERSION — commit and push $CASK so brew sees the new version"
fi
