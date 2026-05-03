import AppKit
import Foundation

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        fputs("FAIL: \(message)\n", stderr)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        failures += 1
        fputs("FAIL: \(message)\n  expected: \(expected)\n  actual:   \(actual)\n", stderr)
    }
}

private func testTranscriptFormatting() {
    expectEqual(
        TranscriptFormatting.displayedTranscript(committed: "hello", partial: "world"),
        "hello world",
        "partial speech stays on the same line"
    )

    expectEqual(
        TranscriptFormatting.displayedTranscript(committed: "first thought\n\n", partial: "second thought"),
        "first thought\n\nsecond thought",
        "partial speech starts after an existing paragraph break"
    )

    expectEqual(
        TranscriptFormatting.commitPartial(committed: "hello", partial: "world", addParagraphBreak: false),
        "hello world",
        "committed partials are separated by one space"
    )

    expectEqual(
        TranscriptFormatting.commitPartial(committed: "hello", partial: "world", addParagraphBreak: true),
        "hello world\n\n",
        "pause detection commits a paragraph break"
    )

    expectEqual(
        TranscriptFormatting.commitPartial(committed: "", partial: "", addParagraphBreak: true),
        "",
        "empty pauses do not create blank transcript blocks"
    )

    expectEqual(
        TranscriptFormatting.overlaySnippet(from: "older paragraph\n\nnew caption"),
        "new caption",
        "overlay uses the latest paragraph"
    )

    let imported = TranscriptFormatting.formattedImportedTranscript(
        segments: [
            TranscriptSegment(text: "Hello", timestamp: 0.0, duration: 0.2),
            TranscriptSegment(text: "there.", timestamp: 0.25, duration: 0.2),
            TranscriptSegment(text: "New", timestamp: 2.0, duration: 0.2),
            TranscriptSegment(text: "thought.", timestamp: 2.25, duration: 0.2)
        ]
    )
    expectEqual(
        imported,
        "Hello there.\n\nNew thought.",
        "imported transcripts add paragraph breaks at long audio gaps"
    )

    let detectedPauseImported = TranscriptFormatting.formattedImportedTranscript(
        segments: [
            TranscriptSegment(text: "Before", timestamp: 0.0, duration: 0.2),
            TranscriptSegment(text: "pause.", timestamp: 0.3, duration: 0.2),
            TranscriptSegment(text: "After", timestamp: 1.0, duration: 0.2),
            TranscriptSegment(text: "pause.", timestamp: 1.3, duration: 0.2)
        ],
        pauseBreaks: [0.8]
    )
    expectEqual(
        detectedPauseImported,
        "Before pause.\n\nAfter pause.",
        "imported transcripts add paragraph breaks at audio-detected pauses"
    )

    let longWords = (0..<80).map { "word\($0)" }.joined(separator: " ")
    let snippet = TranscriptFormatting.overlaySnippet(from: longWords)
    expect(snippet.count <= 280, "overlay snippet is capped")
    expect(!snippet.hasPrefix("word0 "), "overlay snippet prefers the recent tail")

    let noSpeech = NSError(domain: "kAFAssistantErrorDomain", code: 1110)
    expect(
        TranscriptFormatting.isRecoverableRecognitionError(noSpeech),
        "known no-speech recognition errors are recoverable"
    )

    let fatal = NSError(domain: "ExampleDomain", code: 1)
    expect(
        !TranscriptFormatting.isRecoverableRecognitionError(fatal),
        "unknown recognition errors are not treated as recoverable"
    )

}

private func testIconAsset() {
    let url = URL(fileURLWithPath: "Resources/AppIconSource.png")
    guard let image = NSImage(contentsOf: url),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        failures += 1
        fputs("FAIL: AppIconSource.png could not be loaded\n", stderr)
        return
    }

    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    expect(width >= 1024 && height >= 1024, "source icon is high resolution")
    expect(bitmap.hasAlpha, "source icon keeps transparent corners")

    let cornerPoints = [
        (0, 0),
        (width - 1, 0),
        (0, height - 1),
        (width - 1, height - 1)
    ]
    for point in cornerPoints {
        let color = bitmap.colorAt(x: point.0, y: point.1)?.usingColorSpace(.deviceRGB)
        expect((color?.alphaComponent ?? 1) < 0.05, "outer icon corner \(point) is transparent")
    }

    var brightOuterPixels = 0
    let bottomStart = Int(Double(height) * 0.86)
    let leftEnd = Int(Double(width) * 0.20)
    let rightStart = Int(Double(width) * 0.80)

    for y in bottomStart..<height {
        for x in 0..<leftEnd {
            if isBrightOpaquePixel(bitmap, x: x, y: y) {
                brightOuterPixels += 1
            }
        }
        for x in rightStart..<width {
            if isBrightOpaquePixel(bitmap, x: x, y: y) {
                brightOuterPixels += 1
            }
        }
    }

    expectEqual(
        brightOuterPixels,
        0,
        "outer lower icon corners do not contain a white antialias/bevel fringe"
    )
}

private func isBrightOpaquePixel(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> Bool {
    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          color.alphaComponent > 0.7 else {
        return false
    }

    let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
    return brightness > 0.55
}

testTranscriptFormatting()
testIconAsset()

if failures > 0 {
    exit(1)
}

print("Swift tests passed.")
