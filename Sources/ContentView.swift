import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var transcriber: CaptionTranscriber
    private let toolbarButtonHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text(transcriber.statusText)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if transcriber.isImporting {
                        ProgressView(value: transcriber.importProgress)
                            .controlSize(.small)
                            .frame(width: 220)
                    }
                }
                .frame(minHeight: 30, alignment: .center)

                Spacer()

                if transcriber.isRecording || transcriber.isImporting {
                    Button {
                        transcriber.togglePause()
                    } label: {
                        Label(transcriber.isPaused ? "Resume" : "Pause",
                              systemImage: transcriber.isPaused ? "play.fill" : "pause.fill")
                    }
                    .controlSize(.large)
                    .frame(height: toolbarButtonHeight)
                    .keyboardShortcut(.space, modifiers: [])

                    Button(role: .destructive) {
                        transcriber.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .controlSize(.large)
                    .frame(height: toolbarButtonHeight)
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        transcriber.importAudio()
                    } label: {
                        Label("Import Audio...", systemImage: "waveform")
                    }
                    .controlSize(.large)
                    .frame(height: toolbarButtonHeight)

                    Button {
                        transcriber.start()
                    } label: {
                        Label("Record", systemImage: "record.circle")
                    }
                    .controlSize(.large)
                    .frame(height: toolbarButtonHeight)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                    .disabled(transcriber.isImporting)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 0.5)
            }

            TranscriptTextView(text: transcriber.transcript)

            HStack(spacing: 10) {
                Spacer()

                ProgressView()
                    .controlSize(.small)
                    .opacity(transcriber.isRunningTranscriptAction ? 1 : 0)
                    .frame(width: 20, height: 20)

                SaveActionControl()
                    .environmentObject(transcriber)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 0.5)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .clearTranscriptRequested)) { _ in
            transcriber.clearTranscript()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importAudioRequested)) { _ in
            transcriber.importAudio()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordRequested)) { _ in
            transcriber.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runTranscriptActionRequested)) { notification in
            if let id = notification.object as? UUID {
                transcriber.runTranscriptAction(id: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsRequested)) { _ in
            PreferencesWindowController.shared.show(transcriber: transcriber)
        }
        .background(WindowCloseHandler(transcriber: transcriber))
    }
}

private struct SaveActionControl: View {
    @EnvironmentObject private var transcriber: CaptionTranscriber
    private let buttonHeight: CGFloat = 34

    private var hasTranscript: Bool {
        !transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isEnabled: Bool {
        hasTranscript && !transcriber.isRunningTranscriptAction
    }

    var body: some View {
        if transcriber.transcriptActions.isEmpty {
            Button {
                transcriber.saveTranscript()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .controlSize(.regular)
            .frame(height: buttonHeight)
            .disabled(!hasTranscript)
        } else {
            HStack(spacing: 0) {
                Button {
                    transcriber.saveTranscript()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save")
                    }
                    .font(.system(size: 13.5, weight: .medium))
                    .frame(height: buttonHeight)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .disabled(!hasTranscript)

                Divider()
                    .frame(height: 18)
                    .overlay(isEnabled ? Color.white.opacity(0.35) : Color(nsColor: .separatorColor))

                ActionPopupButton(
                    actions: transcriber.transcriptActions,
                    isEnabled: isEnabled,
                    runAction: { id in
                        transcriber.runTranscriptAction(id: id)
                    }
                )
                .frame(width: 26, height: buttonHeight)
            }
            .frame(height: buttonHeight)
            .clipped()
            .allowsHitTesting(isEnabled)
            .accessibilityElement(children: isEnabled ? .contain : .ignore)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isEnabled ? Color.accentColor.opacity(0.9) : Color(nsColor: .separatorColor), lineWidth: 0.75)
            )
            .shadow(color: isEnabled ? Color.black.opacity(0.16) : .clear, radius: 1, y: 1)
        }
    }
}

private struct ActionPopupButton: NSViewRepresentable {
    let actions: [TranscriptAction]
    let isEnabled: Bool
    let runAction: (UUID) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Show transcript actions")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.toolTip = "Show transcript actions"
        button.setAccessibilityLabel("Transcript actions")
        button.setAccessibilityHelp("Shows custom transcript actions.")
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.actions = actions
        context.coordinator.runAction = runAction
        button.isEnabled = isEnabled
        button.contentTintColor = isEnabled ? .white : .secondaryLabelColor
        button.setAccessibilityEnabled(isEnabled)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(actions: actions, runAction: runAction)
    }

    final class Coordinator: NSObject {
        var actions: [TranscriptAction]
        var runAction: (UUID) -> Void

        init(actions: [TranscriptAction], runAction: @escaping (UUID) -> Void) {
            self.actions = actions
            self.runAction = runAction
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            for (index, action) in actions.enumerated() {
                let item = NSMenuItem(
                    title: action.displayName,
                    action: #selector(runMenuAction(_:)),
                    keyEquivalent: Self.keyEquivalent(for: index)
                )
                item.keyEquivalentModifierMask = Self.keyEquivalentModifierMask(for: index)
                item.target = self
                item.representedObject = action.id
                if let symbolName = action.displaySymbolName {
                    item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: action.displayName)
                }
                menu.addItem(item)
            }

            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
                in: sender
            )
        }

        @objc private func runMenuAction(_ sender: NSMenuItem) {
            if let id = sender.representedObject as? UUID {
                runAction(id)
            }
        }

        private static func keyEquivalent(for index: Int) -> String {
            index < 9 ? String(index + 1) : ""
        }

        private static func keyEquivalentModifierMask(for index: Int) -> NSEvent.ModifierFlags {
            index < 9 ? [.command] : []
        }
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
    @State private var selectedTab = PreferencesTab.general

    var body: some View {
        TabView(selection: $selectedTab) {
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
            }
            .formStyle(.grouped)
            .padding(18)
            .tabItem { Text("General") }
            .tag(PreferencesTab.general)

            OverlayPreferencesView(selectedTab: $selectedTab)
                .environmentObject(transcriber)
                .padding(18)
                .tabItem { Text("Overlay") }
                .tag(PreferencesTab.overlay)

            TranscriptActionsPreferencesView()
                .environmentObject(transcriber)
                .padding(18)
                .tabItem { Text("Actions") }
                .tag(PreferencesTab.actions)
        }
        .onChange(of: selectedTab) { newTab in
            if newTab != .overlay {
                transcriber.hideOverlayPreview()
            } else if transcriber.showOverlayWhenMinimized {
                transcriber.showOverlayPreview()
            }
        }
        .onDisappear {
            transcriber.hideOverlayPreview()
        }
    }
}

private struct OverlayPreferencesView: View {
    @EnvironmentObject private var transcriber: CaptionTranscriber
    @Binding var selectedTab: PreferencesTab

    private let fontChoices = [
        "System Semibold",
        "System Regular",
        "System Bold",
        "Avenir Next",
        "Helvetica Neue",
        "Menlo",
        "Georgia"
    ]

    var body: some View {
        Form {
            Toggle("Show captions on screen when minimized", isOn: $transcriber.showOverlayWhenMinimized)
                .onChange(of: transcriber.showOverlayWhenMinimized) { enabled in
                    if selectedTab == .overlay, enabled {
                        transcriber.showOverlayPreview()
                    } else {
                        transcriber.hideOverlayPreview()
                    }
                }

            Section("Text") {
                Picker("Font", selection: overlayBinding(\.fontName)) {
                    ForEach(fontChoices, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }

                labeledSlider(
                    title: "Font size",
                    value: overlayBinding(\.fontSize),
                    range: 10...72,
                    step: 1,
                    format: "%.0f"
                )

                ColorPicker("Text color", selection: colorBinding(\.textColorHex), supportsOpacity: true)

                Picker("Alignment", selection: overlayBinding(\.alignment)) {
                    ForEach(CaptionOverlayAlignment.allCases) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Outline") {
                ColorPicker("Outline color", selection: colorBinding(\.outlineColorHex), supportsOpacity: true)

                labeledSlider(
                    title: "Outline thickness",
                    value: overlayBinding(\.outlineThickness),
                    range: 0...12,
                    step: 0.5,
                    format: "%.1f"
                )
            }

            Section("Screen Area") {
                labeledSlider(
                    title: "Width",
                    value: overlayBinding(\.widthPercent),
                    range: 20...90,
                    step: 1,
                    format: "%.0f%%"
                )

                labeledSlider(
                    title: "Height",
                    value: overlayBinding(\.heightPercent),
                    range: 25...95,
                    step: 1,
                    format: "%.0f%%"
                )

                labeledSlider(
                    title: "Fade starts",
                    value: overlayBinding(\.fadeStartPercent),
                    range: 40...100,
                    step: 1,
                    format: "%.0f%%"
                )
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if transcriber.showOverlayWhenMinimized {
                transcriber.showOverlayPreview()
            }
        }
    }

    private func overlayBinding<Value>(_ keyPath: WritableKeyPath<CaptionOverlayStyle, Value>) -> Binding<Value> {
        Binding(
            get: { transcriber.overlayStyle[keyPath: keyPath] },
            set: { newValue in
                var style = transcriber.overlayStyle
                style[keyPath: keyPath] = newValue
                transcriber.overlayStyle = style
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<CaptionOverlayStyle, String>) -> Binding<Color> {
        Binding(
            get: {
                Color(nsColor: NSColor.captionCrunchColor(
                    hex: transcriber.overlayStyle[keyPath: keyPath],
                    fallback: .white
                ))
            },
            set: { color in
                var style = transcriber.overlayStyle
                style[keyPath: keyPath] = NSColor(color).captionCrunchHex
                transcriber.overlayStyle = style
            }
        )
    }

    private func labeledSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        HStack(spacing: 12) {
            Slider(value: value, in: range, step: step) {
                Text(title)
            } minimumValueLabel: {
                Text(String(format: format, range.lowerBound))
            } maximumValueLabel: {
                Text(String(format: format, range.upperBound))
            }

            Text(String(format: format, value.wrappedValue))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

private enum PreferencesTab: Hashable {
    case general
    case overlay
    case actions
}

private struct TranscriptActionsPreferencesView: View {
    @EnvironmentObject private var transcriber: CaptionTranscriber
    private let symbolChoices = [
        "",
        "sparkles",
        "wand.and.stars",
        "text.quote",
        "doc.text",
        "brain",
        "list.bullet",
        "checklist",
        "book.closed",
        "pencil.and.outline",
        "lightbulb",
        "magnifyingglass",
        "arrow.triangle.2.circlepath",
        "terminal",
        "gearshape"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript Actions")
                    .font(.headline)
                Spacer()
                Button {
                    guard transcriber.transcriptActions.count < TranscriptActionStore.maximumActions else { return }
                    transcriber.transcriptActions.append(
                        TranscriptAction(name: "New Action", command: "")
                    )
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(transcriber.transcriptActions.count >= TranscriptActionStore.maximumActions)
                .help(transcriber.transcriptActions.count >= TranscriptActionStore.maximumActions
                      ? "Delete an action before adding another."
                      : "Add a transcript action")
            }

            Text("Actions appear in the Save dropdown and File menu. You can create up to 9 actions, assigned Cmd-1 through Cmd-9. Use %f for a transcript file, %t for transcript text, or %a for the audio file.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if transcriber.transcriptActions.isEmpty {
                Spacer()
                Text("No custom actions yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($transcriber.transcriptActions) { $action in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    IconSymbolPicker(symbolName: $action.symbolName, choices: symbolChoices)
                                        .frame(width: 42, height: 26)

                                    TextField("Name", text: $action.name)

                                    ProgressView()
                                        .controlSize(.small)
                                        .opacity(transcriber.isTestingTranscriptAction(id: action.id) ? 1 : 0)
                                        .frame(width: 18, height: 18)

                                    Button {
                                        transcriber.testTranscriptAction(id: action.id)
                                    } label: {
                                        Label("Test", systemImage: "play.circle")
                                    }
                                    .disabled(
                                        transcriber.isRunningTranscriptAction ||
                                        action.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    )
                                    .help("Run this action with the sample transcript")

                                    Button(role: .destructive) {
                                        transcriber.transcriptActions.removeAll { $0.id == action.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("Delete action")
                                    .help("Delete action")
                                }

                                TextField("Command", text: $action.command, axis: .vertical)
                                    .lineLimit(5...10)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 120, alignment: .top)

                                Text("Choose an icon for menus and the Save dropdown.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }
}

private struct IconSymbolPicker: NSViewRepresentable {
    @Binding var symbolName: String
    let choices: [String]

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.imagePosition = .imageOnly
        button.bezelStyle = .rounded
        button.toolTip = "Choose an action icon"
        button.setAccessibilityLabel("Action icon")
        button.setAccessibilityHelp("Chooses the icon shown for this transcript action.")
        context.coordinator.configure(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.symbolName = $symbolName
        context.coordinator.choices = choices
        context.coordinator.configure(button)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(symbolName: $symbolName, choices: choices)
    }

    final class Coordinator: NSObject {
        var symbolName: Binding<String>
        var choices: [String]

        init(symbolName: Binding<String>, choices: [String]) {
            self.symbolName = symbolName
            self.choices = choices
        }

        func configure(_ button: NSPopUpButton) {
            button.removeAllItems()

            for symbol in choices {
                let item = NSMenuItem(title: " ", action: nil, keyEquivalent: "")
                item.representedObject = symbol
                item.image = image(for: symbol)
                item.toolTip = accessibilityName(for: symbol)
                item.setAccessibilityLabel(accessibilityName(for: symbol))
                button.menu?.addItem(item)
            }

            let selected = choices.contains(symbolName.wrappedValue) ? symbolName.wrappedValue : ""
            if let item = button.itemArray.first(where: { ($0.representedObject as? String) == selected }) {
                button.select(item)
            }
        }

        @objc func changed(_ sender: NSPopUpButton) {
            symbolName.wrappedValue = sender.selectedItem?.representedObject as? String ?? ""
        }

        private func image(for symbol: String) -> NSImage? {
            let name = symbol.isEmpty ? "nosign" : symbol
            return NSImage(systemSymbolName: name, accessibilityDescription: symbol.isEmpty ? "No Icon" : symbol)
        }

        private func accessibilityName(for symbol: String) -> String {
            if symbol.isEmpty { return "No icon" }
            return symbol
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
        }
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
        private var miniaturizeObserver: NSObjectProtocol?
        private var deminiaturizeObserver: NSObjectProtocol?
        private var willCloseObserver: NSObjectProtocol?

        init(transcriber: CaptionTranscriber) {
            self.transcriber = transcriber
        }

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            window.delegate = self
            installTitlebarProxyIcon(in: window)
            installWindowObservers(for: window)
        }

        private func installTitlebarProxyIcon(in window: NSWindow) {
            window.representedURL = Bundle.main.bundleURL
            window.title = "Caption Crunch"
        }

        private func installWindowObservers(for window: NSWindow) {
            removeWindowObservers()
            miniaturizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let transcriber = self?.transcriber else { return }
                Task { @MainActor in
                    transcriber.setMainWindowMinimized(true)
                }
            }
            deminiaturizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let transcriber = self?.transcriber else { return }
                Task { @MainActor in
                    transcriber.setMainWindowMinimized(false)
                }
            }
            willCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let transcriber = self?.transcriber else { return }
                Task { @MainActor in
                    transcriber.setMainWindowMinimized(false)
                }
            }
        }

        private func removeWindowObservers() {
            for observer in [miniaturizeObserver, deminiaturizeObserver, willCloseObserver].compactMap({ $0 }) {
                NotificationCenter.default.removeObserver(observer)
            }
            miniaturizeObserver = nil
            deminiaturizeObserver = nil
            willCloseObserver = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            let shouldClose = transcriber.confirmClose()
            if shouldClose {
                transcriber.stopIfNeededBeforeClosing()
            }
            return shouldClose
        }

        func windowWillClose(_ notification: Notification) {
            removeWindowObservers()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }

        func windowWillMiniaturize(_ notification: Notification) {
            transcriber.setMainWindowMinimized(true)
        }

        func windowDidMiniaturize(_ notification: Notification) {
            transcriber.setMainWindowMinimized(true)
        }

        func windowDidDeminiaturize(_ notification: Notification) {
            transcriber.setMainWindowMinimized(false)
        }
    }
}
