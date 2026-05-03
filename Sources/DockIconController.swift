import AppKit

@MainActor
final class DockIconController: NSObject {
    enum Mode {
        case idle
        case recording
        case importing
    }

    private let baseIcon: NSImage
    private var timer: Timer?
    private var frameIndex = 0
    private var mode: Mode = .idle

    override init() {
        if let url = Bundle.main.url(forResource: "AppIconSource", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            baseIcon = image
        } else {
            baseIcon = NSApp.applicationIconImage
        }
        super.init()
    }

    func setMode(_ mode: Mode) {
        guard self.mode != mode else { return }
        self.mode = mode

        switch mode {
        case .idle:
            stopAnimating()
        case .recording, .importing:
            startAnimating()
        }
    }

    private func startAnimating() {
        frameIndex = 0
        NSApp.applicationIconImage = makeAnimatedIcon(frame: frameIndex, mode: mode)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            timeInterval: 0.38,
            target: self,
            selector: #selector(timerDidFire(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
        NSApp.applicationIconImage = baseIcon
    }

    private func advanceFrame() {
        frameIndex = (frameIndex + 1) % 6
        NSApp.applicationIconImage = makeAnimatedIcon(frame: frameIndex, mode: mode)
    }

    @objc private func timerDidFire(_ timer: Timer) {
        advanceFrame()
    }

    private func makeAnimatedIcon(frame: Int, mode: Mode) -> NSImage {
        let size = baseIcon.size
        let image = NSImage(size: size)

        image.lockFocus()
        baseIcon.draw(in: NSRect(origin: .zero, size: size))

        let scaleX = size.width / 1254
        let scaleY = size.height / 1254
        let mouthMidY = 430 * scaleY
        let startX = 320 * scaleX
        let spacing = 37 * scaleX
        let barWidth = 18 * scaleX
        let dotSize = 14 * scaleX
        let baseHeight = 42 * scaleY
        let pulse = [0, 2, 4, 1, 3, 5]
        let heights: [CGFloat] = [18, 28, 44, 72, 118, 64, 40, 28, 54, 112, 58, 38, 36, 104, 62, 42, 30, 20]

        NSGraphicsContext.current?.shouldAntialias = true
        NSColor(calibratedWhite: 0.015, alpha: 0.94).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 286 * scaleX, y: 332 * scaleY, width: 682 * scaleX, height: 192 * scaleY),
            xRadius: 56 * scaleX,
            yRadius: 56 * scaleY
        ).fill()

        let waveformColor: NSColor
        switch mode {
        case .recording:
            waveformColor = NSColor(calibratedRed: 1.0, green: 0.03, blue: 0.02, alpha: 1.0)
        case .importing:
            waveformColor = NSColor(calibratedRed: 0.45, green: 1.0, blue: 1.0, alpha: 1.0)
        case .idle:
            waveformColor = NSColor(calibratedRed: 0.45, green: 1.0, blue: 1.0, alpha: 1.0)
        }
        let shadow = NSShadow()
        shadow.shadowColor = waveformColor.withAlphaComponent(0.95)
        shadow.shadowBlurRadius = 16 * scaleX
        shadow.shadowOffset = .zero
        shadow.set()

        waveformColor.setFill()

        for index in heights.indices {
            let phaseBoost = CGFloat(pulse[(index + frame) % pulse.count]) * 7 * scaleY
            let height = max(baseHeight, heights[index] * scaleY + phaseBoost)
            let x = startX + CGFloat(index) * spacing

            if index == 0 || index == heights.count - 1 {
                NSBezierPath(ovalIn: NSRect(x: x, y: mouthMidY - dotSize / 2, width: dotSize, height: dotSize)).fill()
            } else {
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: mouthMidY - height / 2, width: barWidth, height: height),
                    xRadius: barWidth / 2,
                    yRadius: barWidth / 2
                ).fill()
            }
        }

        NSShadow().set()
        image.unlockFocus()
        return image
    }
}
