#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
APP="$BUILD_DIR/Caption Crunch.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
MODULE_CACHE="$ROOT/.build/module-cache"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES" "$MODULE_CACHE"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$ROOT/Resources/AppIconSource.png" "$RESOURCES/AppIconSource.png"
cp "$ROOT/Resources/SampleTranscript.txt" "$RESOURCES/SampleTranscript.txt"

xcrun swiftc \
  -target "$(uname -m)-apple-macosx13.0" \
  -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework Speech \
  "$ROOT"/Sources/*.swift \
  -o "$MACOS/CaptionCrunch"

codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
