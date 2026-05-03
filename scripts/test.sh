#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"

bash -n build.sh
bash -n scripts/test.sh
bash -n scripts/build_dmg.sh

plutil -lint Info.plist >/dev/null

if rg -n 'NSMenu\(title: "(View|Window)"|Start Dictation|Emoji and Symbols|Autofill|AutoFill' Sources; then
  echo "Unexpected default editable-text or window/view menu item found." >&2
  exit 1
fi

mkdir -p "$ROOT/build"
mkdir -p "$ROOT/.build/module-cache"
xcrun swiftc \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$ROOT/.build/module-cache" \
  -framework AppKit \
  "$ROOT/Sources/TranscriptFormatting.swift" \
  "$ROOT/Tests/main.swift" \
  -o "$ROOT/build/CaptionCrunchTests"
"$ROOT/build/CaptionCrunchTests"

./build.sh

APP="$ROOT/build/Caption Crunch.app"
EXECUTABLE="$APP/Contents/MacOS/CaptionCrunch"
ICON="$APP/Contents/Resources/AppIcon.icns"

test -d "$APP"
test -x "$EXECUTABLE"
test -f "$ICON"

/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist" | grep -qx "AppIcon"
sips -g hasAlpha "$ROOT/Resources/AppIconSource.png" | grep -q "hasAlpha: yes"
rm -rf "$ROOT/build/AppIcon.verify.iconset"
iconutil -c iconset "$ICON" -o "$ROOT/build/AppIcon.verify.iconset"

codesign --verify --deep --strict "$APP"

echo "All checks passed."
