import AppKit
import AVFoundation
import Combine
import Speech
import SwiftUI
import UniformTypeIdentifiers

struct InputDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

private enum TranscriptMode {
    case empty
    case recording
    case importing
}

@MainActor
final class CaptionTranscriber: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var devices: [InputDevice] = []
    @Published var selectedDeviceID: String {
        didSet {
            UserDefaults.standard.set(selectedDeviceID, forKey: Self.selectedDeviceKey)
        }
    }
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: Double = 0
    @Published private(set) var importStatusText = ""
    @Published var transcriptActions: [TranscriptAction] {
        didSet {
            TranscriptActionStore.save(transcriptActions)
        }
    }
    @Published private(set) var isRunningTranscriptAction = false
    @Published private(set) var runningTranscriptActionID: UUID?
    @Published private(set) var isRunningTranscriptActionTest = false
    @Published var showingAlert = false
    @Published var alertMessage = ""
    @Published var showOverlayWhenMinimized: Bool {
        didSet {
            UserDefaults.standard.set(showOverlayWhenMinimized, forKey: Self.showOverlayKey)
            updateOverlayVisibility()
        }
    }
    @Published private var listeningNote = ""

    private static let selectedDeviceKey = "selectedInputDeviceID"
    private static let showOverlayKey = "showOverlayWhenMinimized"
    private static let recognitionRollInterval: TimeInterval = 45
    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    private static let importableContentTypes: [UTType] = [
        "m4a", "mp3", "wav", "aiff", "aif", "caf", "mov", "mp4", "m4v"
    ].compactMap { UTType(filenameExtension: $0) }
    private let captureQueue = DispatchQueue(label: "CaptionCrunch.CaptureQueue")
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioOutputDelegate = AudioSampleDelegate()
    private let overlayController = CaptionOverlayController()
    private let dockIconController = DockIconController()

    private var session: AVCaptureSession?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var committedTranscript = ""
    private var currentPartialTranscript = ""
    private var recognitionRollTask: Task<Void, Never>?
    private var isRestartingRecognition = false
    private var lastRecognitionRecoveryAt: CFTimeInterval = 0
    private var ignoredRecognitionTaskIDs = Set<UUID>()
    private var activeRecognitionTaskID: UUID?
    private var savedTranscriptSnapshot = ""
    private var isMainWindowMinimized = false
    private var transcriptMode: TranscriptMode = .empty
    private var importDuration: TimeInterval = 0
    private var importPauseBreaks: [TimeInterval] = []
    private var latestImportSegments: [TranscriptSegment] = []
    private var latestImportFallbackText = ""
    private var importBaseTranscript = ""
    private var currentAudioURL: URL?
    private var temporaryRecordingURL: URL?
    private var liveAudioRecorder: SampleBufferAudioRecorder?
    private var importTranscriptionTask: Task<Void, Never>?
    private var importStreamTask: Task<Void, Never>?
    private var importPauseScanTask: Task<Void, Never>?
    private var importWasStopped = false

    var statusText: String {
        if isImporting { return isPaused ? "Importing audio - paused" : "Importing audio" }
        if isPaused { return "Paused" }
        if isRecording {
            let base = "Listening from \(selectedDeviceName)"
            return listeningNote.isEmpty ? base : "\(base) - \(listeningNote)"
        }
        return "Ready"
    }

    private var selectedDeviceName: String {
        devices.first(where: { $0.id == selectedDeviceID })?.name ?? "selected input"
    }

    override init() {
        selectedDeviceID = UserDefaults.standard.string(forKey: Self.selectedDeviceKey) ?? ""
        showOverlayWhenMinimized = UserDefaults.standard.object(forKey: Self.showOverlayKey) as? Bool ?? true
        transcriptActions = TranscriptActionStore.load()
        super.init()
        refreshDevices()
    }

    func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        )

        let found = discovery.devices
            .map { InputDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        devices = found
        if selectedDeviceID.isEmpty || !found.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = found.first?.id ?? ""
        }
    }

    func start() {
        guard !isRecording, !isImporting else { return }
        guard prepareForMode(.recording) else { return }

        Task {
            do {
                try await requestPermissions()
                try startCapture()
            } catch {
                present(error.localizedDescription)
            }
        }
    }

    func togglePause() {
        guard isRecording || isImporting else { return }
        isPaused.toggle()
        if isRecording {
            audioOutputDelegate.setPaused(isPaused)
            dockIconController.setMode(isPaused ? .idle : .recording)
        } else if isImporting {
            dockIconController.setMode(isPaused ? .idle : .importing)
        }
    }

    func stop() {
        if isImporting {
            stopImport()
            return
        }

        recognitionRollTask?.cancel()
        recognitionRollTask = nil
        recognitionRequest?.endAudio()
        if let activeRecognitionTaskID {
            ignoredRecognitionTaskIDs.insert(activeRecognitionTaskID)
        }
        recognitionTask?.finish()
        session?.stopRunning()
        audioOutputDelegate.setRecorder(nil)
        liveAudioRecorder?.finish()
        liveAudioRecorder = nil
        audioOutputDelegate.setRequest(nil)
        audioOutputDelegate.setPaused(false)
        session = nil
        recognitionRequest = nil
        recognitionTask = nil
        activeRecognitionTaskID = nil
        ignoredRecognitionTaskIDs.removeAll()
        commitCurrentPartial(addParagraphBreak: false)
        isRecording = false
        isPaused = false
        listeningNote = ""
        dockIconController.setMode(.idle)
    }

    func stopIfNeededBeforeClosing() {
        overlayController.hide()
        if isRecording {
            stop()
        } else if isImporting {
            stopImport()
        }
    }

    func setMainWindowMinimized(_ minimized: Bool) {
        isMainWindowMinimized = minimized
        updateOverlayVisibility()
    }

    func importAudio() {
        guard !isRecording, !isImporting else { return }
        guard prepareForMode(.importing) else { return }

        let panel = NSOpenPanel()
        panel.title = "Import Audio"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.importableContentTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }

        importTranscriptionTask = Task {
            await transcribeImportedFile(url)
        }
    }

    func copyAll() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clearTranscript() {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Clear transcript?"
        alert.informativeText = "This will erase the current transcript and reset Caption Crunch as if no recording or import has been started."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if isRecording {
            stop()
        } else if isImporting {
            stopImport()
        }

        resetTranscriptState()
    }

    func runTranscriptAction(id: UUID) {
        guard !isRunningTranscriptAction else { return }
        guard let action = transcriptActions.first(where: { $0.id == id }) else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        runTranscriptAction(action, transcript: text, audioURL: currentAudioURL, title: action.displayName, isTest: false)
    }

    func testTranscriptAction(id: UUID) {
        guard !isRunningTranscriptAction else { return }
        guard let action = transcriptActions.first(where: { $0.id == id }) else { return }
        let text = Self.sampleTranscript()
        runTranscriptAction(action, transcript: text, audioURL: nil, title: "Test: \(action.displayName)", isTest: true)
    }

    func isTestingTranscriptAction(id: UUID) -> Bool {
        runningTranscriptActionID == id && isRunningTranscriptActionTest
    }

    private func runTranscriptAction(
        _ action: TranscriptAction,
        transcript text: String,
        audioURL: URL?,
        title: String,
        isTest: Bool
    ) {
        let commandText = action.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandText.isEmpty else {
            present("That transcript action does not have a command.")
            return
        }

        isRunningTranscriptAction = true
        runningTranscriptActionID = action.id
        isRunningTranscriptActionTest = isTest
        Task {
            do {
                let output = try await runAction(action, transcript: text, audioURL: audioURL)
                TranscriptActionResultWindowController.shared.show(
                    title: title,
                    output: output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(No output)" : output
                )
            } catch {
                present("Could not run \(action.displayName): \(error.localizedDescription)")
            }
            isRunningTranscriptAction = false
            runningTranscriptActionID = nil
            isRunningTranscriptActionTest = false
        }
    }

    private func runAction(_ action: TranscriptAction, transcript: String, audioURL: URL?) async throws -> String {
        let prepared = try TranscriptActionCommand.make(
            action: action,
            transcript: transcript,
            audioURL: audioURL
        )
        defer {
            if let tempFileURL = prepared.tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }

        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", prepared.command]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanError = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)

            if process.terminationStatus != 0 {
                let combined = [cleanOutput, cleanError]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                throw NSError(
                    domain: "CaptionCrunch.TranscriptAction",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: combined.isEmpty ? "Command exited with status \(process.terminationStatus)." : combined]
                )
            }

            return cleanOutput
        }.value
    }

    private static func sampleTranscript() -> String {
        guard let url = Bundle.main.url(forResource: "SampleTranscript", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return """
            Alex: Before we start, we need to decide whether to follow the river road or cut through the old orchard.

            Morgan: The orchard is faster, but the map says people hear bells there after sunset.

            Mara: I saw lanterns moving between the trees. One of them stopped when I said the miller's name.
            """
        }
        return text
    }

    @discardableResult
    func saveTranscript() -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }

        let panel = NSSavePanel()
        panel.title = "Save Transcript"
        panel.nameFieldStringValue = defaultTranscriptFilename()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedTranscriptSnapshot = normalizedTranscriptSnapshot()
            return true
        } catch {
            present("Could not save transcript: \(error.localizedDescription)")
            return false
        }
    }

    func confirmClose() -> Bool {
        guard hasUnsavedTranscript else { return true }

        let alert = NSAlert()
        alert.messageText = "Save transcript before closing?"
        alert.informativeText = "Your transcript has not been saved as a text file."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveTranscript()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func requestPermissions() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard microphoneAllowed else {
                throw CaptionError.microphoneDenied
            }
        default:
            throw CaptionError.microphoneDenied
        }

        try await requestSpeechPermission()
    }

    private func transcribeImportedFile(_ url: URL) async {
        isImporting = true
        importProgress = 0
        importStatusText = "Preparing audio..."
        listeningNote = ""
        importBaseTranscript = transcriptMode == .importing
            ? transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        currentAudioURL = url
        temporaryRecordingURL = nil
        committedTranscript = importBaseTranscript
        currentPartialTranscript = ""
        importDuration = 0
        importPauseBreaks = []
        latestImportSegments = []
        latestImportFallbackText = ""
        isPaused = false
        importWasStopped = false
        dockIconController.setMode(.importing)

        do {
            try await requestSpeechPermission()
            let transcriptionURL = try await preparedAudioURL(for: url)
            defer {
                if transcriptionURL != url {
                    try? FileManager.default.removeItem(at: transcriptionURL)
                }
            }

            let importedText = try await transcribeFile(at: transcriptionURL)
            if !importWasStopped {
                appendImportedTranscript(importedText)
            }
        } catch {
            if !importWasStopped, !(error is CancellationError) {
                present(error.localizedDescription)
            }
        }

        importProgress = 0
        importStatusText = ""
        isImporting = false
        isPaused = false
        importDuration = 0
        importPauseBreaks = []
        latestImportSegments = []
        latestImportFallbackText = ""
        importBaseTranscript = ""
        importWasStopped = false
        importTranscriptionTask = nil
        importStreamTask = nil
        importPauseScanTask?.cancel()
        importPauseScanTask = nil
        recognitionRequest = nil
        recognitionTask = nil
        dockIconController.setMode(.idle)
    }

    private func requestSpeechPermission() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            let speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

            guard speechStatus == .authorized else {
                throw CaptionError.speechDenied
            }
        default:
            throw CaptionError.speechDenied
        }
    }

    private func preparedAudioURL(for url: URL) async throws -> URL {
        if Self.videoExtensions.contains(url.pathExtension.lowercased()) {
            importStatusText = "Extracting audio from video..."
            importProgress = 0.08
            return try await extractAudio(from: url)
        }
        return url
    }

    private func extractAudio(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw CaptionError.noAudioTrack
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CaptionError.cannotExtractAudio
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionCrunch-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? CaptionError.cannotExtractAudio)
                default:
                    continuation.resume(throwing: CaptionError.cannotExtractAudio)
                }
            }
        }

        return outputURL
    }

    private func transcribeFile(at url: URL) async throws -> String {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw CaptionError.speechUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        importDuration = await audioDuration(for: url)
        startImportPauseScan(for: url)
        recognitionRequest = request

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var bestText = ""
            importStatusText = "Transcribing audio..."
            importProgress = 0.02

            @MainActor
            func resume(_ result: Result<String, Error>) {
                guard !didResume else { return }
                didResume = true
                self.importStreamTask?.cancel()
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    let segments = result.bestTranscription.segments.map {
                        TranscriptSegment(
                            text: $0.substring,
                            timestamp: $0.timestamp,
                            duration: $0.duration
                        )
                    }
                    Task { @MainActor in
                        let displayText = self.updateImportedPartial(
                            segments: segments,
                            fallbackText: text,
                            result: result
                        )
                        bestText = displayText

                        if result.isFinal {
                            resume(.success(displayText))
                        }
                    }
                } else if let error {
                    if !bestText.isEmpty {
                        Task { @MainActor in
                            resume(.success(bestText))
                        }
                    } else {
                        Task { @MainActor in
                            resume(.failure(error))
                        }
                    }
                }
            }

            importStreamTask = Task { [weak self] in
                do {
                    try await self?.streamAudioFile(at: url, into: request)
                    request.endAudio()
                } catch {
                    request.endAudio()
                    if let self, self.importWasStopped || error is CancellationError {
                        resume(.success(bestText))
                    } else {
                        resume(.failure(error))
                    }
                }
            }
        }
    }

    private func stopImport() {
        importWasStopped = true
        importStreamTask?.cancel()
        importPauseScanTask?.cancel()
        importTranscriptionTask?.cancel()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        importStreamTask = nil
        importPauseScanTask = nil
        importTranscriptionTask = nil
        isImporting = false
        isPaused = false
        importProgress = 0
        importStatusText = ""
        importDuration = 0
        importPauseBreaks = []
        latestImportSegments = []
        latestImportFallbackText = ""
        importBaseTranscript = ""
        dockIconController.setMode(.idle)
    }

    private func startImportPauseScan(for url: URL) {
        importPauseScanTask?.cancel()
        importPauseScanTask = Task { [weak self] in
            let breaks = (try? await Task.detached {
                try Self.detectPauseBreaks(at: url)
            }.value) ?? []

            guard !Task.isCancelled else { return }
            guard let self, self.isImporting, !self.importWasStopped else { return }
            self.importPauseBreaks = breaks
            self.refreshImportedTranscriptWithPauseBreaks()
        }
    }

    private func streamAudioFile(
        at url: URL,
        into request: SFSpeechAudioBufferRecognitionRequest
    ) async throws {
        let file = try AVAudioFile(forReading: url)
        let frameCapacity: AVAudioFrameCount = 8192

        while file.framePosition < file.length {
            try Task.checkCancellation()

            while isPaused {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            let remainingFrames = file.length - file.framePosition
            let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(frameCapacity), remainingFrames))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: framesToRead
            ) else {
                throw CaptionError.cannotReadAudioFile
            }

            try file.read(into: buffer, frameCount: framesToRead)
            guard buffer.frameLength > 0 else { break }

            request.append(buffer)
            await Task.yield()
        }
    }

    private func audioDuration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            return seconds.isFinite && seconds > 0 ? seconds : 0
        } catch {
            return 0
        }
    }

    nonisolated private static func detectPauseBreaks(at url: URL) throws -> [TimeInterval] {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = max(file.processingFormat.sampleRate, 1)
        let frameCapacity: AVAudioFrameCount = 4096
        let silenceThreshold: Float = 0.012
        let minimumPauseDuration: TimeInterval = 1.1

        var pauseBreaks: [TimeInterval] = []
        var hasHeardSpeech = false
        var silenceStartedAt: TimeInterval?
        var didEmitCurrentPause = false

        while file.framePosition < file.length {
            let bufferStart = Double(file.framePosition) / sampleRate
            let remainingFrames = file.length - file.framePosition
            let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(frameCapacity), remainingFrames))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: framesToRead
            ) else {
                throw CaptionError.cannotReadAudioFile
            }

            try file.read(into: buffer, frameCount: framesToRead)
            guard buffer.frameLength > 0 else { break }

            let bufferDuration = Double(buffer.frameLength) / sampleRate
            let rms = rmsLevel(from: buffer)

            if rms > silenceThreshold {
                hasHeardSpeech = true
                silenceStartedAt = nil
                didEmitCurrentPause = false
            } else if hasHeardSpeech {
                let start = silenceStartedAt ?? bufferStart
                silenceStartedAt = start
                if !didEmitCurrentPause, bufferStart + bufferDuration - start >= minimumPauseDuration {
                    pauseBreaks.append(start + minimumPauseDuration)
                    didEmitCurrentPause = true
                }
            }
        }

        return pauseBreaks
    }

    nonisolated private static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        if let channels = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var sum: Float = 0
            var count = 0
            for channelIndex in 0..<channelCount {
                let channel = channels[channelIndex]
                for frameIndex in 0..<frameLength {
                    let sample = channel[frameIndex]
                    sum += sample * sample
                    count += 1
                }
            }
            return count > 0 ? sqrt(sum / Float(count)) : 0
        }

        if let channels = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var sum: Float = 0
            var count = 0
            for channelIndex in 0..<channelCount {
                let channel = channels[channelIndex]
                for frameIndex in 0..<frameLength {
                    let sample = Float(channel[frameIndex]) / Float(Int16.max)
                    sum += sample * sample
                    count += 1
                }
            }
            return count > 0 ? sqrt(sum / Float(count)) : 0
        }

        return 0
    }

    private func updateImportedPartial(
        segments: [TranscriptSegment],
        fallbackText: String,
        result: SFSpeechRecognitionResult
    ) -> String {
        latestImportSegments = segments
        latestImportFallbackText = fallbackText
        let text = displayedImportTranscript(
            formattedImportedTranscript(segments: segments, fallbackText: fallbackText)
        )
        let partial = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return "" }

        transcript = partial
        committedTranscript = partial
        currentPartialTranscript = ""
        transcriptMode = .importing
        updateImportProgress(from: result)
        overlayController.update(text: TranscriptFormatting.overlaySnippet(from: transcript))
        return partial
    }

    private func refreshImportedTranscriptWithPauseBreaks() {
        guard isImporting, !latestImportSegments.isEmpty else { return }
        let text = formattedImportedTranscript(
            segments: latestImportSegments,
            fallbackText: latestImportFallbackText
        )
        let displayText = displayedImportTranscript(text)
        guard !displayText.isEmpty, displayText != transcript else { return }
        transcript = displayText
        committedTranscript = displayText
        overlayController.update(text: TranscriptFormatting.overlaySnippet(from: transcript))
    }

    private func formattedImportedTranscript(
        segments: [TranscriptSegment],
        fallbackText: String
    ) -> String {
        let formatted = TranscriptFormatting.formattedImportedTranscript(
            segments: segments,
            pauseBreaks: importPauseBreaks
        )
        return formatted.isEmpty ? fallbackText : formatted
    }

    private func displayedImportTranscript(_ importedText: String) -> String {
        let imported = importedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !imported.isEmpty else { return importBaseTranscript }
        guard !importBaseTranscript.isEmpty else { return imported }
        return importBaseTranscript + "\n\n" + imported
    }

    private func updateImportProgress(from result: SFSpeechRecognitionResult) {
        guard importDuration > 0 else {
            importProgress = result.isFinal ? 1 : max(importProgress, 0.02)
            return
        }

        let lastSegmentEnd = result.bestTranscription.segments
            .map { $0.timestamp + $0.duration }
            .max() ?? 0
        let progress = lastSegmentEnd / importDuration
        importProgress = max(importProgress, min(max(progress, 0.02), result.isFinal ? 1 : 0.98))
    }

    private func appendImportedTranscript(_ importedText: String) {
        let text = importedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            present("No speech was detected in that file.")
            return
        }

        transcript = displayedImportTranscript(text)
        committedTranscript = transcript
        currentPartialTranscript = ""
        transcriptMode = .importing
        importProgress = 1
        importStatusText = "Import complete"
        overlayController.update(text: TranscriptFormatting.overlaySnippet(from: transcript))
    }

    private func startCapture() throws {
        refreshDevices()

        guard let device = AVCaptureDevice(uniqueID: selectedDeviceID) ?? AVCaptureDevice.default(for: .audio) else {
            throw CaptionError.noInputDevice
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw CaptionError.speechUnavailable
        }

        let recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionCrunch-Recording-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let recorder = SampleBufferAudioRecorder(outputURL: recordingURL)
        liveAudioRecorder = recorder
        temporaryRecordingURL = recordingURL
        currentAudioURL = recordingURL

        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw CaptionError.cannotUseInput
        }
        captureSession.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        output.setSampleBufferDelegate(audioOutputDelegate, queue: captureQueue)
        audioOutputDelegate.setRecorder(recorder)
        guard captureSession.canAddOutput(output) else {
            throw CaptionError.cannotUseInput
        }
        captureSession.addOutput(output)
        captureSession.commitConfiguration()

        recognitionRequest = nil
        recognitionTask = nil
        audioOutputDelegate.setPaused(false)
        audioOutputDelegate.onPauseDetected = { [weak self] in
            Task { @MainActor in
                self?.commitPauseBreak()
            }
        }
        committedTranscript = transcript
        currentPartialTranscript = ""
        transcriptMode = .recording

        try startRecognitionTask(using: speechRecognizer)

        session = captureSession
        isRecording = true
        isPaused = false
        listeningNote = ""
        dockIconController.setMode(.recording)

        captureQueue.async {
            captureSession.startRunning()
        }

        scheduleRecognitionRolling()
    }

    private func handleRecognition(taskID: UUID, result: SFSpeechRecognitionResult?, error: Error?) {
        if ignoredRecognitionTaskIDs.contains(taskID) {
            if error != nil {
                ignoredRecognitionTaskIDs.remove(taskID)
            }
            return
        }

        if let result {
            currentPartialTranscript = result.bestTranscription.formattedString
            refreshDisplayedTranscript()

            if result.isFinal {
                commitCurrentPartial(addParagraphBreak: false)
                if isRecording, !isPaused, !isRestartingRecognition {
                    rollRecognitionTask(addParagraphBreak: false)
                }
            }
        }

        if let error {
            guard !isRestartingRecognition else { return }
            if TranscriptFormatting.isRecoverableRecognitionError(error) {
                recoverRecognitionAfterNoSpeech()
                return
            }
            if isRecording {
                let now = CACurrentMediaTime()
                if now - lastRecognitionRecoveryAt > 2 {
                    lastRecognitionRecoveryAt = now
                    rollRecognitionTask(addParagraphBreak: false)
                    return
                }
            }
            stop()
            present(error.localizedDescription)
        }
    }

    private func startRecognitionTask(using speechRecognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        recognitionRequest = request
        audioOutputDelegate.setRequest(request)
        let taskID = UUID()
        activeRecognitionTaskID = taskID

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognition(taskID: taskID, result: result, error: error)
            }
        }
    }

    private func scheduleRecognitionRolling() {
        recognitionRollTask?.cancel()
        recognitionRollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.recognitionRollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.rollRecognitionTask(addParagraphBreak: false)
            }
        }
    }

    private func commitPauseBreak() {
        guard isRecording, !isPaused else { return }
        rollRecognitionTask(addParagraphBreak: true)
    }

    private func rollRecognitionTask(addParagraphBreak: Bool) {
        guard isRecording, let speechRecognizer, speechRecognizer.isAvailable else { return }

        commitCurrentPartial(addParagraphBreak: addParagraphBreak)
        isRestartingRecognition = true
        recognitionRequest?.endAudio()
        if let activeRecognitionTaskID {
            ignoredRecognitionTaskIDs.insert(activeRecognitionTaskID)
        }
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        activeRecognitionTaskID = nil
        audioOutputDelegate.setRequest(nil)

        do {
            try startRecognitionTask(using: speechRecognizer)
        } catch {
            isRestartingRecognition = false
            stop()
            present(error.localizedDescription)
            return
        }

        isRestartingRecognition = false
    }

    private func recoverRecognitionAfterNoSpeech() {
        guard isRecording else { return }

        let now = CACurrentMediaTime()
        guard now - lastRecognitionRecoveryAt > 1 else { return }

        lastRecognitionRecoveryAt = now
        listeningNote = "waiting for speech"
        rollRecognitionTask(addParagraphBreak: false)
    }

    private func commitCurrentPartial(addParagraphBreak: Bool) {
        let partial = currentPartialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        committedTranscript = TranscriptFormatting.commitPartial(
            committed: committedTranscript,
            partial: currentPartialTranscript,
            addParagraphBreak: addParagraphBreak
        )
        currentPartialTranscript = ""
        transcript = committedTranscript
        overlayController.update(text: TranscriptFormatting.overlaySnippet(from: transcript))
        if !partial.isEmpty {
            listeningNote = ""
        }
    }

    private func refreshDisplayedTranscript() {
        transcript = TranscriptFormatting.displayedTranscript(
            committed: committedTranscript,
            partial: currentPartialTranscript
        )
        overlayController.update(text: TranscriptFormatting.overlaySnippet(from: transcript))
    }

    private func present(_ message: String) {
        alertMessage = message
        showingAlert = true
    }

    private func defaultTranscriptFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return "Caption Crunch \(formatter.string(from: Date())).txt"
    }

    private var hasUnsavedTranscript: Bool {
        let snapshot = normalizedTranscriptSnapshot()
        return !snapshot.isEmpty && snapshot != savedTranscriptSnapshot
    }

    private func normalizedTranscriptSnapshot() -> String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetTranscriptState() {
        transcript = ""
        committedTranscript = ""
        currentPartialTranscript = ""
        importBaseTranscript = ""
        importProgress = 0
        importStatusText = ""
        listeningNote = ""
        savedTranscriptSnapshot = ""
        transcriptMode = .empty
        clearTemporaryRecording()
        currentAudioURL = nil
        overlayController.update(text: "")
    }

    private func prepareForMode(_ newMode: TranscriptMode) -> Bool {
        let existing = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            transcriptMode = newMode
            importBaseTranscript = ""
            return true
        }

        if transcriptMode == newMode {
            if newMode == .importing {
                importBaseTranscript = existing
            }
            return true
        }

        if transcriptMode == .empty {
            transcriptMode = newMode
            return true
        }

        if !hasUnsavedTranscript {
            transcript = ""
            committedTranscript = ""
            currentPartialTranscript = ""
            importBaseTranscript = ""
            clearTemporaryRecording()
            currentAudioURL = nil
            transcriptMode = newMode
            return true
        }

        let action = newMode == .recording ? "Recording" : "Importing audio"
        let previous = transcriptMode == .recording ? "recording" : "import"

        let alert = NSAlert()
        alert.messageText = "Replace current transcript?"
        alert.informativeText = "\(action) will erase the current \(previous) transcript."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        transcript = ""
        committedTranscript = ""
        currentPartialTranscript = ""
        importBaseTranscript = ""
        clearTemporaryRecording()
        currentAudioURL = nil
        transcriptMode = newMode
        return true
    }

    private func clearTemporaryRecording() {
        if let temporaryRecordingURL {
            try? FileManager.default.removeItem(at: temporaryRecordingURL)
        }
        temporaryRecordingURL = nil
    }

    private func updateOverlayVisibility() {
        if showOverlayWhenMinimized, isMainWindowMinimized {
            overlayController.update(text: TranscriptFormatting.overlaySnippet(from: transcript))
            overlayController.show()
        } else {
            overlayController.hide()
        }
    }

}

final class AudioSampleDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recorder: SampleBufferAudioRecorder?
    private var paused = false
    private var hasRecentSpeech = false
    private var quietStartedAt: CFTimeInterval?
    private var lastPauseNotificationAt: CFTimeInterval = 0
    var onPauseDetected: (() -> Void)?

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock {
            self.request = request
        }
    }

    func setRecorder(_ recorder: SampleBufferAudioRecorder?) {
        lock.withLock {
            self.recorder = recorder
        }
    }

    func setPaused(_ paused: Bool) {
        lock.withLock {
            self.paused = paused
            if paused {
                hasRecentSpeech = false
                quietStartedAt = nil
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        var currentRequest: SFSpeechAudioBufferRecognitionRequest?
        var currentRecorder: SampleBufferAudioRecorder?
        var shouldSkip = true
        var pauseHandler: (() -> Void)?
        let now = CACurrentMediaTime()
        let level = Self.rmsLevel(from: sampleBuffer)

        lock.withLock {
            currentRequest = request
            currentRecorder = recorder
            shouldSkip = paused

            if !paused {
                if level > 0.012 {
                    hasRecentSpeech = true
                    quietStartedAt = nil
                } else if hasRecentSpeech {
                    quietStartedAt = quietStartedAt ?? now
                    if now - (quietStartedAt ?? now) > 0.75,
                       now - lastPauseNotificationAt > 1.15 {
                        hasRecentSpeech = false
                        quietStartedAt = nil
                        lastPauseNotificationAt = now
                        pauseHandler = onPauseDetected
                    }
                }
            }
        }

        currentRecorder?.append(sampleBuffer)
        guard !shouldSkip else { return }
        currentRequest?.appendAudioSampleBuffer(sampleBuffer)
        pauseHandler?()
    }

    private static func rmsLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let dataPointer, length >= MemoryLayout<Int16>.size else {
            return 0
        }

        let sampleCount = length / MemoryLayout<Int16>.size
        let samples = UnsafeRawPointer(dataPointer).bindMemory(to: Int16.self, capacity: sampleCount)
        var sum: Float = 0

        for index in 0..<sampleCount {
            let sample = Float(samples[index]) / Float(Int16.max)
            sum += sample * sample
        }

        return sqrt(sum / Float(sampleCount))
    }
}

final class SampleBufferAudioRecorder {
    let outputURL: URL

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var isFinished = false

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard !isFinished else { return }

        do {
            if writer == nil {
                try start(with: sampleBuffer)
            }

            guard let input, input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        } catch {
            isFinished = true
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        input?.markAsFinished()

        guard let writer else { return }
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    private func start(with sampleBuffer: CMSampleBuffer) throws {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .caf)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: CMSampleBufferGetFormatDescription(sampleBuffer)
        )
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw CaptionError.cannotRecordAudioFile
        }

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

        self.writer = writer
        self.input = input
    }
}

enum CaptionError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case noInputDevice
    case speechUnavailable
    case cannotUseInput
    case noAudioTrack
    case cannotExtractAudio
    case cannotReadAudioFile
    case cannotRecordAudioFile

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required in System Settings."
        case .speechDenied:
            "Speech recognition permission is required in System Settings."
        case .noInputDevice:
            "No audio input device is available."
        case .speechUnavailable:
            "Speech recognition is not available right now."
        case .cannotUseInput:
            "The selected input device could not be used."
        case .noAudioTrack:
            "That file does not appear to contain an audio track."
        case .cannotExtractAudio:
            "The audio could not be extracted from that file."
        case .cannotReadAudioFile:
            "That audio file could not be read."
        case .cannotRecordAudioFile:
            "The temporary recording file could not be created."
        }
    }
}
