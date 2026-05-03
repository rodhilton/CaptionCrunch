# Caption Crunch

Caption Crunch is a small native macOS app for turning speech from a chosen audio input into live, readable captions. It is meant for tabletop sessions, calls, streams, accessibility experiments, or any situation where you want a quick local caption window without running a full meeting app.

The app uses macOS audio capture and Apple Speech recognition. It lets you choose an input device, start live transcription, pause or stop recording, copy/select the transcript, save it as plain text, and optionally show a transparent on-screen caption overlay when the main window is minimized.

## Features

- Native SwiftUI/AppKit macOS app
- Input-device picker in Settings
- Live transcription from the selected input
- Import common audio and video files for transcription
- Record, Pause, Resume, and Stop controls
- Read-only transcript view that stays copyable/selectable
- Auto-scrolling transcript without jostling on partial recognition updates
- Pause-based paragraph breaks for readability
- Plain-text transcript export
- Optional transparent caption overlay when minimized
- Animated red Dock icon waveform while actively recording
- GitHub Actions CI and tagged-release DMG publishing

## Requirements

- macOS 13 or newer
- Apple Speech recognition availability for your locale
- Xcode Command Line Tools or Xcode

On first use, macOS asks for microphone and speech recognition permissions. Development rebuilds can make macOS ask again because ad-hoc app signatures change.

## Build Locally

```sh
./build.sh
```

The built app is written to:

```sh
build/Caption Crunch.app
```

Run it with:

```sh
open "build/Caption Crunch.app"
```

## Test Locally

```sh
./scripts/test.sh
```

The test script performs the same practical checks used in CI:

- shell syntax checks
- plist validation
- transcript formatting unit tests
- minimized-overlay snippet unit tests
- recoverable speech-error unit tests
- menu regression checks for removed View/Window/editing items
- source icon transparency and outer-corner fringe checks
- app build
- icon presence and alpha check
- icon extraction sanity check
- ad-hoc code-signature verification

## Build a DMG

```sh
./scripts/build_dmg.sh
```

The DMG is written to `dist/`. It contains `Caption Crunch.app` and an `Applications` shortcut so installation is the usual drag-to-Applications flow.

## GitHub Automation

This repo includes two GitHub Actions workflows:

- `.github/workflows/ci.yml`
  Runs on pushes and pull requests. It builds the app and runs `./scripts/test.sh`.

- `.github/workflows/release.yml`
  Runs when a tag matching `v*` is pushed. It builds and tests the app, creates a DMG, and publishes a GitHub Release with the DMG attached.

To publish a release:

```sh
git tag v0.1.0
git push origin v0.1.0
```

GitHub will create the release entry and upload a downloadable DMG automatically.

## Notes

- Choose the input source in `Caption Crunch > Settings`.
- `Show captions on screen when minimized` controls the transparent on-screen caption overlay.
- `Record` starts live transcription.
- `Import Audio...` lets you pick common audio or video files. For video files, Caption Crunch extracts the audio track first.
- While recording, `Pause` temporarily stops sending audio to the recognizer and `Stop` ends the session.
- Use `Save` or `File > Save Transcript...` to save the transcript as UTF-8 text.
- Apple's Speech framework does not expose reliable live speaker diarization on macOS, so speaker changes are approximated when they include an audible pause.
- The app periodically rolls the Apple Speech streaming task so longer recording sessions continue transcribing instead of ending when the framework times out.

## Repository Hygiene

Generated build outputs, DMGs, module caches, local environment files, and common AI-tool scratch folders are ignored in `.gitignore`.
