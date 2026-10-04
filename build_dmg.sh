#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

APP_NAME="DynaNotch"
BUILD_DIR="$(pwd)/build"
DMG_NAME="$(pwd)/DynaNotch.dmg"
STAGING="$BUILD_DIR/dmg_staging"

echo "🔨 Building $APP_NAME (this takes 2–4 min on first run)…"

xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  clean build

APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "${APP_NAME}.app" -maxdepth 8 | head -1)

if [ -z "$APP_PATH" ]; then
  echo "❌ Build failed — .app not found. See errors above."
  exit 1
fi

echo "✅ Built: $APP_PATH"
echo "📦 Packaging DMG…"

rm -rf "$STAGING" "$DMG_NAME"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

TMP_DMG="$BUILD_DIR/tmp.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDRW "$TMP_DMG" -quiet
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME" -quiet
rm -f "$TMP_DMG"
rm -rf "$STAGING"

echo ""
echo "🎉 DMG ready → $DMG_NAME"
echo ""
echo "Installing to /Applications…"
hdiutil attach "$DMG_NAME" -quiet -mountpoint /tmp/DynaNotchMount
rm -rf /Applications/DynaNotch.app
cp -R /tmp/DynaNotchMount/DynaNotch.app /Applications/
hdiutil detach /tmp/DynaNotchMount -quiet
echo "✅ Installed → /Applications/DynaNotch.app"
echo ""
echo "Launching…"
open /Applications/DynaNotch.app
echo "✅ DynaNotch is running. Check the top of your screen and the menu bar."
