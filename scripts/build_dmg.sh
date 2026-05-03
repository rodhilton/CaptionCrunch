#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Caption Crunch.app"
STAGING="$BUILD_DIR/dmg-root"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")}"
VERSION="${VERSION#v}"
DMG="$DIST_DIR/CaptionCrunch-${VERSION}.dmg"
LATEST_DMG="$DIST_DIR/CaptionCrunch-latest.dmg"

cd "$ROOT"

./build.sh

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-$VERSION}" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

rm -rf "$STAGING" "$DMG" "$LATEST_DMG"
mkdir -p "$STAGING" "$DIST_DIR"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Caption Crunch" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

cp "$DMG" "$LATEST_DMG"

echo "Built $DMG"
echo "Built $LATEST_DMG"
