import AppKit

enum CaptionOverlayAlignment: String, CaseIterable, Identifiable {
    case left
    case center
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }

    var paragraphAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

struct CaptionOverlayStyle: Equatable {
    var fontName: String
    var fontSize: Double
    var textColorHex: String
    var outlineColorHex: String
    var outlineThickness: Double
    var alignment: CaptionOverlayAlignment
    var widthPercent: Double
    var heightPercent: Double
    var fadeStartPercent: Double

    static let `default` = CaptionOverlayStyle(
        fontName: "System Semibold",
        fontSize: 16,
        textColorHex: "#FFFFFFBF",
        outlineColorHex: "#00000080",
        outlineThickness: 1.5,
        alignment: .right,
        widthPercent: 25,
        heightPercent: 80,
        fadeStartPercent: 70
    )

    static func load() -> CaptionOverlayStyle {
        let defaults = UserDefaults.standard
        var style = CaptionOverlayStyle.default
        style.fontName = defaults.string(forKey: "overlay.fontName") ?? style.fontName
        style.fontSize = defaults.object(forKey: "overlay.fontSize") as? Double ?? style.fontSize
        style.textColorHex = defaults.string(forKey: "overlay.textColorHex") ?? style.textColorHex
        style.outlineColorHex = defaults.string(forKey: "overlay.outlineColorHex") ?? style.outlineColorHex
        style.outlineThickness = defaults.object(forKey: "overlay.outlineThickness") as? Double ?? style.outlineThickness
        if let rawAlignment = defaults.string(forKey: "overlay.alignment"),
           let alignment = CaptionOverlayAlignment(rawValue: rawAlignment) {
            style.alignment = alignment
        }
        style.widthPercent = defaults.object(forKey: "overlay.widthPercent") as? Double ?? style.widthPercent
        style.heightPercent = defaults.object(forKey: "overlay.heightPercent") as? Double ?? style.heightPercent
        style.fadeStartPercent = defaults.object(forKey: "overlay.fadeStartPercent") as? Double ?? style.fadeStartPercent
        return style.clamped()
    }

    func save() {
        let defaults = UserDefaults.standard
        let style = clamped()
        defaults.set(style.fontName, forKey: "overlay.fontName")
        defaults.set(style.fontSize, forKey: "overlay.fontSize")
        defaults.set(style.textColorHex, forKey: "overlay.textColorHex")
        defaults.set(style.outlineColorHex, forKey: "overlay.outlineColorHex")
        defaults.set(style.outlineThickness, forKey: "overlay.outlineThickness")
        defaults.set(style.alignment.rawValue, forKey: "overlay.alignment")
        defaults.set(style.widthPercent, forKey: "overlay.widthPercent")
        defaults.set(style.heightPercent, forKey: "overlay.heightPercent")
        defaults.set(style.fadeStartPercent, forKey: "overlay.fadeStartPercent")
    }

    func clamped() -> CaptionOverlayStyle {
        var style = self
        style.fontSize = min(max(style.fontSize, 10), 72)
        style.outlineThickness = min(max(style.outlineThickness, 0), 12)
        style.widthPercent = min(max(style.widthPercent, 20), 90)
        style.heightPercent = min(max(style.heightPercent, 25), 95)
        style.fadeStartPercent = min(max(style.fadeStartPercent, 40), 100)
        return style
    }
}

@MainActor
final class CaptionOverlayController {
    private let captionView = CaptionOverlayView()
    private var window: NSWindow?

    var style = CaptionOverlayStyle.default {
        didSet {
            captionView.style = style
            positionWindow()
        }
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        positionWindow()
        guard let window else { return }
        window.level = .screenSaver
        window.orderFrontRegardless()
        window.displayIfNeeded()
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
        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        captionView.style = style
        window.contentView = captionView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return window
    }

    private func positionWindow() {
        guard let window else { return }
        window.setFrame(overlayFrame(), display: true)
    }

    private func overlayFrame() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let style = style.clamped()
        let width = screenFrame.width * CGFloat(style.widthPercent / 100)
        let height = screenFrame.height * CGFloat(style.heightPercent / 100)
        let margin: CGFloat = 28
        let x: CGFloat
        switch style.alignment {
        case .left:
            x = screenFrame.minX + margin
        case .center:
            x = screenFrame.midX - width / 2
        case .right:
            x = screenFrame.maxX - width - margin
        }

        return NSRect(
            x: x,
            y: screenFrame.minY + margin,
            width: width,
            height: height
        )
    }
}

final class CaptionOverlayView: NSView {
    var text = "" {
        didSet {
            setAccessibilityValue(text)
            needsDisplay = true
        }
    }

    var style = CaptionOverlayStyle.default {
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
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let style = style.clamped()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = style.alignment.paragraphAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 10

        let font = Self.font(named: style.fontName, size: style.fontSize)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.captionCrunchColor(hex: style.textColorHex, fallback: .white),
            .paragraphStyle: paragraphStyle,
            .kern: 0.2
        ]

        let inset = CGFloat(22 + style.outlineThickness * 2)
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let attributed = NSAttributedString(string: caption, attributes: baseAttributes)
        let maxSize = NSSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude)
        let measured = attributed.boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let verticalSafety = CGFloat(style.outlineThickness * 3 + 10)
        let drawHeight = ceil(measured.height) + verticalSafety
        let overflow = max(0, drawHeight - rect.height)
        let drawRect = NSRect(
            x: rect.minX,
            y: rect.minY - overflow + verticalSafety / 2,
            width: rect.width,
            height: drawHeight
        )

        context.saveGState()
        context.clip(to: rect)
        applyFadeMask(in: context, rect: rect, fadeStartPercent: style.fadeStartPercent)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        drawOutline(
            caption,
            in: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            baseAttributes: baseAttributes,
            color: NSColor.captionCrunchColor(hex: style.outlineColorHex, fallback: .black),
            thickness: style.outlineThickness
        )
        var knockoutAttributes = baseAttributes
        knockoutAttributes[.foregroundColor] = NSColor.white
        context.setBlendMode(.destinationOut)
        NSAttributedString(string: caption, attributes: knockoutAttributes)
            .draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        context.setBlendMode(.normal)
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawOutline(
        _ string: String,
        in rect: NSRect,
        options: NSString.DrawingOptions,
        baseAttributes: [NSAttributedString.Key: Any],
        color: NSColor,
        thickness: Double
    ) {
        let radius = Int(ceil(thickness))
        guard radius > 0 else { return }

        var attributes = baseAttributes
        attributes[.foregroundColor] = color

        for x in -radius...radius {
            for y in -radius...radius {
                guard x != 0 || y != 0 else { continue }
                let distance = sqrt(Double(x * x + y * y))
                guard distance <= Double(radius) else { continue }
                let offsetRect = rect.offsetBy(dx: CGFloat(x), dy: CGFloat(y))
                string.draw(with: offsetRect, options: options, attributes: attributes)
            }
        }
    }

    private func applyFadeMask(in context: CGContext, rect: NSRect, fadeStartPercent: Double) {
        let fadeStart = CGFloat(fadeStartPercent / 100)
        let locations: [CGFloat] = [0, max(0, min(1, fadeStart)), 1]
        let colors = [
            CGColor(gray: 1, alpha: 1),
            CGColor(gray: 1, alpha: 1),
            CGColor(gray: 1, alpha: 0)
        ] as CFArray

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceGray(),
            colors: colors,
            locations: locations
        ) else { return }

        context.clip(to: rect, mask: gradientImage(for: rect, gradient: gradient))
    }

    private func gradientImage(for rect: NSRect, gradient: CGGradient) -> CGImage {
        let width = max(1, Int(rect.width.rounded(.up)))
        let height = max(1, Int(rect.height.rounded(.up)))
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        guard let bitmap = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return CGImage.emptyMask
        }

        bitmap.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: height),
            options: []
        )
        return bitmap.makeImage() ?? CGImage.emptyMask
    }

    private static func font(named name: String, size: Double) -> NSFont {
        if name == "System Regular" {
            return .systemFont(ofSize: size, weight: .regular)
        }
        if name == "System Bold" {
            return .systemFont(ofSize: size, weight: .bold)
        }
        if name == "System Semibold" {
            return .systemFont(ofSize: size, weight: .semibold)
        }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }
}

extension NSColor {
    static func captionCrunchColor(hex: String, fallback: NSColor) -> NSColor {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 8, let value = UInt64(trimmed, radix: 16) else { return fallback }
        let red = CGFloat((value & 0xFF000000) >> 24) / 255
        let green = CGFloat((value & 0x00FF0000) >> 16) / 255
        let blue = CGFloat((value & 0x0000FF00) >> 8) / 255
        let alpha = CGFloat(value & 0x000000FF) / 255
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var captionCrunchHex: String {
        let color = usingColorSpace(.deviceRGB) ?? self
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        let alpha = Int(round(color.alphaComponent * 255))
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }
}

private extension CGImage {
    static var emptyMask: CGImage {
        let data = Data([255])
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: 1,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
