import AppKit

@MainActor
final class CaptionOverlayController {
    private let captionView = CaptionOverlayView()
    private var window: NSWindow?

    func show() {
        if window == nil {
            window = makeWindow()
        }
        positionWindow()
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func update(text: String) {
        captionView.text = text
        positionWindow()
    }

    private func makeWindow() -> NSWindow {
        let frame = overlayFrame()
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.contentView = captionView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return window
    }

    private func positionWindow() {
        guard let window else { return }
        window.setFrame(overlayFrame(), display: true)
    }

    private func overlayFrame() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(screenFrame.width * 0.28, 360), 520)
        let height = min(max(screenFrame.height * 0.28, 220), 340)
        let margin: CGFloat = 28

        return NSRect(
            x: screenFrame.maxX - width - margin,
            y: screenFrame.minY + max(48, screenFrame.height * 0.18),
            width: width,
            height: height
        )
    }
}

final class CaptionOverlayView: NSView {
    var text = "" {
        didSet {
            needsDisplay = true
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !caption.isEmpty else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 4

        let font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -5.0,
            .paragraphStyle: paragraphStyle,
            .kern: 0.2
        ]

        let inset: CGFloat = 18
        let rect = bounds.insetBy(dx: inset, dy: inset)
        caption.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }
}
