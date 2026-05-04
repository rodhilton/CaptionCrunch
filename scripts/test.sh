#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"

bash -n build.sh
bash -n scripts/test.sh
bash -n scripts/build_dmg.sh

plutil -lint Info.plist >/dev/null

if grep -REn 'NSMenu\(title: "(View|Window)"|Start Dictation|Emoji and Symbols|Autofill|AutoFill' Sources; then
  echo "Unexpected default editable-text or window/view menu item found." >&2
  exit 1
fi

if ! grep -q 'clearTranscriptRequested' Sources/CaptionCrunchApp.swift || ! grep -q 'func clearTranscript' Sources/CaptionTranscriber.swift; then
  echo "Edit > Clear must be wired through the transcriber." >&2
  exit 1
fi

if grep -En 'Menu \{' Sources/ContentView.swift; then
  echo "Save action dropdown must use the AppKit popup button to avoid duplicate carets and preserve menu icons." >&2
  exit 1
fi

if ! grep -q 'allowsHitTesting(isEnabled)' Sources/ContentView.swift; then
  echo "Save action split control must not open its dropdown when no transcript is available." >&2
  exit 1
fi

if ! grep -q 'window.representedURL = Bundle.main.bundleURL' Sources/ContentView.swift; then
  echo "Main window should install the app icon next to the title with a titlebar proxy icon." >&2
  exit 1
fi

if ! grep -q 'private let buttonHeight: CGFloat = 34' Sources/TranscriptAction.swift || ! grep -q 'frame(height: buttonHeight)' Sources/TranscriptAction.swift; then
  echo "Transcript action result Save button should match the main Save button height." >&2
  exit 1
fi

if ! grep -q 'tabItem { Text("Overlay") }' Sources/ContentView.swift || ! grep -q 'showOverlayPreview' Sources/CaptionTranscriber.swift || ! grep -q 'CaptionOverlayStyle' Sources/CaptionOverlayController.swift; then
  echo "Overlay settings must expose previewable style controls in their own tab." >&2
  exit 1
fi

if ! grep -q 'func windowWillClose' Sources/PreferencesWindowController.swift || ! grep -q 'transcriber?.hideOverlayPreview()' Sources/PreferencesWindowController.swift; then
  echo "Closing Settings must hide the overlay preview." >&2
  exit 1
fi

if ! grep -q 'windowWillMiniaturize' Sources/ContentView.swift || ! grep -q 'NSWindow.didMiniaturizeNotification' Sources/ContentView.swift; then
  echo "Main window minimize detection must show the overlay reliably." >&2
  exit 1
fi

if ! grep -q 'beginActivity' Sources/CaptionTranscriber.swift || ! grep -q 'endActivity' Sources/CaptionTranscriber.swift; then
  echo "Recording/importing must hold a process activity assertion so minimized transcription keeps running." >&2
  exit 1
fi

if ! grep -q 'NSPanel' Sources/CaptionOverlayController.swift || ! grep -q 'canHide = false' Sources/CaptionOverlayController.swift || ! grep -q 'hidesOnDeactivate = false' Sources/CaptionOverlayController.swift; then
  echo "Overlay captions must use a non-hiding panel so they survive main-window minimization." >&2
  exit 1
fi

if ! grep -q 'rect.minY - overflow' Sources/CaptionOverlayController.swift; then
  echo "Overlay captions must anchor new text to the bottom and let older text move upward." >&2
  exit 1
fi

if ! grep -Eq 'NSMenuItem\(' Sources/ContentView.swift || ! grep -Eq 'item.image = NSImage\(systemSymbolName: symbolName' Sources/ContentView.swift; then
  echo "Transcript action dropdown must build NSMenuItems with SF Symbol images." >&2
  exit 1
fi

if ! grep -q 'setAccessibilityLabel("Transcript actions")' Sources/ContentView.swift || ! grep -q 'setAccessibilityLabel("Action icon")' Sources/ContentView.swift; then
  echo "Custom AppKit action controls must expose accessibility labels." >&2
  exit 1
fi

if ! grep -q 'testTranscriptAction' Sources/CaptionTranscriber.swift || ! grep -q 'SampleTranscript.txt' build.sh || ! test -f Resources/SampleTranscript.txt; then
  echo "Transcript action testing must use the bundled sample transcript." >&2
  exit 1
fi

if ! grep -q 'keyEquivalent: index < 9 ? String(index + 1)' Sources/CaptionCrunchApp.swift; then
  echo "Transcript actions in the File menu must receive Cmd-number shortcuts." >&2
  exit 1
fi

if ! grep -q 'maximumActions = 9' Sources/TranscriptAction.swift || ! grep -q 'count < TranscriptActionStore.maximumActions' Sources/ContentView.swift || ! grep -q 'transcriptActions.count > TranscriptActionStore.maximumActions' Sources/CaptionTranscriber.swift; then
  echo "Transcript actions must be capped at 9 so Cmd-1 through Cmd-9 remain exhaustive." >&2
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
SAMPLE_TRANSCRIPT="$APP/Contents/Resources/SampleTranscript.txt"

test -d "$APP"
test -x "$EXECUTABLE"
test -f "$ICON"
test -f "$SAMPLE_TRANSCRIPT"

/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist" | grep -qx "AppIcon"
sips -g hasAlpha "$ROOT/Resources/AppIconSource.png" | grep -q "hasAlpha: yes"
rm -rf "$ROOT/build/AppIcon.verify.iconset"
iconutil -c iconset "$ICON" -o "$ROOT/build/AppIcon.verify.iconset"

codesign --verify --deep --strict "$APP"

echo "All checks passed."
