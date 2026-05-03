import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptAction: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var symbolName: String
    var command: String

    init(id: UUID = UUID(), name: String = "", symbolName: String = "", command: String = "") {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.command = command
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Action" : trimmed
    }

    var displaySymbolName: String? {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case symbolName
        case command
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? ""
        command = try container.decode(String.self, forKey: .command)
    }
}

enum TranscriptActionStore {
    private static let key = "transcriptActions"

    static func load() -> [TranscriptAction] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let actions = try? JSONDecoder().decode([TranscriptAction].self, from: data) else {
            return []
        }
        return actions
    }

    static func save(_ actions: [TranscriptAction]) {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: .transcriptActionsChanged, object: nil)
    }
}

struct TranscriptActionCommand {
    let command: String
    let tempFileURL: URL?

    static func make(
        action: TranscriptAction,
        transcript: String,
        audioURL: URL?
    ) throws -> TranscriptActionCommand {
        var tempFileURL: URL?
        var command = action.command

        if command.contains("%a") {
            guard let audioURL else {
                throw NSError(
                    domain: "CaptionCrunch.TranscriptAction",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No audio file is available for %a."]
                )
            }
            command = command.replacingOccurrences(of: "%a", with: shellQuoted(audioURL.path))
        }

        if command.contains("%f") {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("CaptionCrunch-\(UUID().uuidString)")
                .appendingPathExtension("txt")
            try transcript.write(to: url, atomically: true, encoding: .utf8)
            tempFileURL = url
            command = command.replacingOccurrences(of: "%f", with: shellQuoted(url.path))
        }

        if command.contains("%t") {
            command = command.replacingOccurrences(of: "%t", with: shellQuoted(transcript))
        }

        return TranscriptActionCommand(command: command, tempFileURL: tempFileURL)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

@MainActor
final class TranscriptActionResultWindowController {
    static let shared = TranscriptActionResultWindowController()

    private var windows: [NSWindow] = []

    func show(title: String, output: String) {
        let view = TranscriptActionResultView(title: title, output: output)
            .frame(minWidth: 640, minHeight: 420)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct TranscriptActionResultView: View {
    let title: String
    let output: String

    var body: some View {
        VStack(spacing: 0) {
            SelectableOutputTextView(text: output)

            HStack {
                Spacer()
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.title = "Save Output"
        panel.nameFieldStringValue = "\(title).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct SelectableOutputTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.textView?.string = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: NSTextView?
    }
}

@MainActor
final class TranscriptActionsHelpWindowController {
    static let shared = TranscriptActionsHelpWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let text = """
            Transcript Actions

            Caption Crunch can run custom background commands against the current transcript. Add actions in Settings > Actions. Each action needs a name and a command.

            Placeholders:

            %f writes the current transcript to a temporary text file and inserts the shell-quoted file path.

            %t inserts the current transcript text directly as a shell-quoted string.

            %a inserts the shell-quoted audio file path. For recordings, Caption Crunch creates a temporary audio file. For imports, it uses the imported media file.

            Examples:

            open -a TextEdit %f

            python3 ~/scripts/summarize.py %f %a

            osascript ~/scripts/summarize.scpt %f

            Commands run in the background through the shell. When the command finishes, Caption Crunch opens a result window containing the command output so you can copy or save it.
            """
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window?.title = "Transcript Actions Help"
            window?.contentView = NSHostingView(rootView: TranscriptActionResultView(title: "Transcript Actions Help", output: text))
            window?.isReleasedWhenClosed = false
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
