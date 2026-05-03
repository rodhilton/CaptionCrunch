import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var transcriber: CaptionTranscriber

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Caption Crunch")
                        .font(.system(size: 20, weight: .semibold))
                    HStack(spacing: 10) {
                        Text(transcriber.statusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if transcriber.isImporting {
                            ProgressView(value: transcriber.importProgress)
                                .controlSize(.small)
                                .frame(width: 180)
                        }
                    }
                }

                Spacer()

                Button {
                    transcriber.importAudio()
                } label: {
                    Label("Import Audio...", systemImage: "waveform")
                }
                .disabled(transcriber.isRecording || transcriber.isImporting)

                Button {
                    transcriber.saveTranscript()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if transcriber.isRecording || transcriber.isImporting {
                    Button {
                        transcriber.togglePause()
                    } label: {
                        Label(transcriber.isPaused ? "Resume" : "Pause",
                              systemImage: transcriber.isPaused ? "play.fill" : "pause.fill")
                    }
                    .keyboardShortcut(.space, modifiers: [])

                    Button(role: .destructive) {
                        transcriber.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        transcriber.start()
                    } label: {
                        Label("Record", systemImage: "record.circle")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(transcriber.isImporting)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(.bar)

            TranscriptTextView(text: transcriber.transcript)
        }
        .alert("Caption Crunch", isPresented: $transcriber.showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transcriber.alertMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveTranscriptRequested)) { _ in
            transcriber.saveTranscript()
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyAllRequested)) { _ in
            transcriber.copyAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importAudioRequested)) { _ in
            transcriber.importAudio()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsRequested)) { _ in
            PreferencesWindowController.shared.show(transcriber: transcriber)
        }
        .background(WindowCloseHandler(transcriber: transcriber))
    }
}

private struct TranscriptTextView: NSViewRepresentable {
    let text: String
    private let transcriptFont = NSFont.systemFont(ofSize: 15.5, weight: .regular)
    private let transcriptColor = NSColor.black
    private let transcriptBackground = NSColor.white

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = transcriptBackground
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = transcriptBackground
        textView.font = transcriptFont
        textView.textColor = transcriptColor
        textView.textContainerInset = NSSize(width: 24, height: 22)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        apply(text, to: textView)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            let shouldFollowBottom = context.coordinator.shouldFollowBottom(in: scrollView)
            apply(text, to: textView)
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)

            if shouldFollowBottom {
                context.coordinator.scrollToBottom(in: scrollView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: NSTextView?

        func shouldFollowBottom(in scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let visibleRect = scrollView.contentView.bounds
            let distanceFromBottom = documentView.bounds.maxY - visibleRect.maxY
            return distanceFromBottom < 40
        }

        func scrollToBottom(in scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else { return }
            let clipView = scrollView.contentView
            let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
            let target = NSPoint(x: clipView.bounds.origin.x, y: maxY)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                clipView.scroll(to: target)
                scrollView.reflectScrolledClipView(clipView)
            }
        }
    }

    private func apply(_ text: String, to textView: NSTextView) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 10
        paragraphStyle.lineBreakMode = .byWordWrapping
        let displayText = text.isEmpty ? "Transcript will appear here." : text
        let displayColor = text.isEmpty ? NSColor.secondaryLabelColor : transcriptColor

        let attributedText = NSAttributedString(
            string: displayText,
            attributes: [
                .font: transcriptFont,
                .foregroundColor: displayColor,
                .paragraphStyle: paragraphStyle,
                .kern: 0.1
            ]
        )

        textView.textStorage?.setAttributedString(attributedText)
        textView.typingAttributes = [
            .font: transcriptFont,
            .foregroundColor: transcriptColor,
            .paragraphStyle: paragraphStyle,
            .kern: 0.1
        ]
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var transcriber: CaptionTranscriber

    var body: some View {
        Form {
            Picker("Input device", selection: $transcriber.selectedDeviceID) {
                ForEach(transcriber.devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .disabled(transcriber.isRecording)

            HStack {
                Spacer()
                Button {
                    transcriber.refreshDevices()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(transcriber.isRecording)
            }

            Toggle("Show captions on screen when minimized", isOn: $transcriber.showOverlayWhenMinimized)
        }
        .formStyle(.grouped)
        .padding(18)
    }
}

private struct WindowCloseHandler: NSViewRepresentable {
    let transcriber: CaptionTranscriber

    func makeCoordinator() -> Coordinator {
        Coordinator(transcriber: transcriber)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.attach(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.transcriber = transcriber
        DispatchQueue.main.async {
            if let window = nsView.window {
                context.coordinator.attach(to: window)
            }
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var transcriber: CaptionTranscriber
        private weak var window: NSWindow?

        init(transcriber: CaptionTranscriber) {
            self.transcriber = transcriber
        }

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            let shouldClose = transcriber.confirmClose()
            if shouldClose {
                transcriber.stopIfNeededBeforeClosing()
            }
            return shouldClose
        }

        func windowWillClose(_ notification: Notification) {
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }

        func windowDidMiniaturize(_ notification: Notification) {
            transcriber.setMainWindowMinimized(true)
        }

        func windowDidDeminiaturize(_ notification: Notification) {
            transcriber.setMainWindowMinimized(false)
        }
    }
}
