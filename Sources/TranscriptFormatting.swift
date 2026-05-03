import Foundation

struct TranscriptSegment {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
}

enum TranscriptFormatting {
    private static let paragraphGap: TimeInterval = 1.1

    static func displayedTranscript(committed: String, partial: String) -> String {
        let cleanPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPartial.isEmpty {
            return committed
        }
        if committed.isEmpty || committed.hasSuffix("\n\n") {
            return committed + cleanPartial
        }
        return committed + " " + cleanPartial
    }

    static func commitPartial(
        committed: String,
        partial: String,
        addParagraphBreak: Bool
    ) -> String {
        var result = committed
        let cleanPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanPartial.isEmpty {
            if !result.isEmpty, !result.hasSuffix(" "), !result.hasSuffix("\n\n") {
                result += " "
            }
            result += cleanPartial
        }

        if addParagraphBreak {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            result = trimmed.isEmpty ? "" : trimmed + "\n\n"
        }

        return result
    }

    static func overlaySnippet(from transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let candidate = paragraphs.last ?? trimmed
        if candidate.count <= 280 {
            return candidate
        }

        let suffix = String(candidate.suffix(280))
        if let firstSpace = suffix.firstIndex(where: { $0.isWhitespace }) {
            return String(suffix[suffix.index(after: firstSpace)...])
        }
        return suffix
    }

    static func formattedImportedTranscript(
        segments: [TranscriptSegment],
        pauseBreaks: [TimeInterval] = []
    ) -> String {
        var output = ""
        var previousEnd: TimeInterval?
        var pauseBreakIndex = 0

        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let previousEnd {
                while pauseBreakIndex < pauseBreaks.count,
                      pauseBreaks[pauseBreakIndex] <= previousEnd {
                    pauseBreakIndex += 1
                }

                let hasDetectedPause = pauseBreakIndex < pauseBreaks.count
                    && pauseBreaks[pauseBreakIndex] < segment.timestamp

                if hasDetectedPause || segment.timestamp - previousEnd >= paragraphGap {
                    output = output.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
                    if hasDetectedPause {
                        pauseBreakIndex += 1
                    }
                } else if !output.isEmpty, !output.hasSuffix(" "), !output.hasSuffix("\n\n") {
                    output += " "
                }
            }

            output += text
            previousEnd = segment.timestamp + segment.duration
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isRecoverableRecognitionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = nsError.localizedDescription.lowercased()

        if message.contains("no speech detected") {
            return true
        }

        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
            return true
        }

        if nsError.domain == "SFSpeechErrorDomain", nsError.code == 203 {
            return true
        }

        return false
    }
}
