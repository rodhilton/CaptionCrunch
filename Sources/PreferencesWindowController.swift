import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private var window: NSWindow?
    private weak var transcriber: CaptionTranscriber?

    func show(transcriber: CaptionTranscriber) {
        self.transcriber = transcriber
        if window == nil {
            let view = PreferencesView()
                .environmentObject(transcriber)
                .frame(width: 700, height: 540)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }

        guard let window else { return }
        center(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func center(_ window: NSWindow) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }

    func windowWillClose(_ notification: Notification) {
        transcriber?.hideOverlayPreview()
    }
}
