#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Caption Crunch.app"
STAGING="$BUILD_DIR/dmg-root"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
DMG="$DIST_DIR/CaptionCrunch-${VERSION}.dmg"

cd "$ROOT"

./build.sh

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING" "$DIST_DIR"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Caption Crunch" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

echo "Built $DMG"
