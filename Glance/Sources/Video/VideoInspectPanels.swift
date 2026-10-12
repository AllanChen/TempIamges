import AppKit
import AVFoundation
import AVKit
import Network
import WebKit

final class VideoTitlebar: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) }
        else { window?.performDrag(with: event) }
    }
}

final class VideoInformationView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Video Information".localized)
    private let keys = ["Dimensions", "Duration", "Codec", "Frame rate", "Audio", "Bitrate"]
    private var keyLabels: [NSTextField] = []
    private var valueLabels: [NSTextField] = []
    private var dividers: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectChrome)
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        addSubview(titleLabel)
        for key in keys {
            let label = NSTextField(labelWithString: key.localized)
            label.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
            label.textColor = PanelStyle.textTertiary
            addSubview(label)
            keyLabels.append(label)
            let value = NSTextField(labelWithString: "—")
            value.font = PanelStyle.inspectFont(ofSize: 13)
            value.textColor = PanelStyle.textPrimary
            value.lineBreakMode = .byTruncatingMiddle
            value.isSelectable = true
            addSubview(value)
            valueLabels.append(value)
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
            addSubview(line)
            dividers.append(line)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let sx = bounds.width / 434, sy = bounds.height / 847
        let scale = min(sx, sy)
        layer?.borderWidth = max(1, scale)
        func topFrame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * sx, y: bounds.height - (y + h) * sy,
                   width: w * sx, height: h * sy)
        }
        titleLabel.font = PanelStyle.inspectFont(ofSize: 17 * scale, weight: .semibold)
        titleLabel.frame = topFrame(36, 24, 362, 21)
        for index in keys.indices {
            let y = CGFloat(84 + index * 38)
            keyLabels[index].font = PanelStyle.inspectFont(ofSize: 13 * scale, weight: .medium)
            valueLabels[index].font = PanelStyle.inspectFont(ofSize: 13 * scale)
            keyLabels[index].frame = topFrame(36, y, 124, 16)
            valueLabels[index].frame = topFrame(174, y, 220, 16)
            dividers[index].frame = topFrame(36, y + 30, 362, 1)
        }
    }

    func update(info: MediaInfo, duration: Double, metadata: VideoTechnicalMetadata?) {
        let dimensions = info.dimensions.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "—"
        let time = duration > 0 ? String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60) : "—"
        let fps = metadata?.fps.map { String(format: "%g fps", Double($0)) } ?? "—"
        let audio = metadata?.audioCodec ?? "—"
        let bitrate: String
        if let value = metadata?.videoBitrate, value > 0 {
            bitrate = value >= 1_000_000
                ? String(format: "%.1f Mbps", Double(value) / 1_000_000)
                : String(format: "%.0f kbps", Double(value) / 1_000)
        } else { bitrate = "—" }
        let values = [dimensions, time, metadata?.videoCodec ?? "—", fps, audio, bitrate]
        for (label, value) in zip(valueLabels, values) { label.stringValue = value }
    }
}

/// A captured still that remains clickable until the ten-second timeout.
/// During dismissal the view's right edge stays fixed while its width shrinks;
/// drawing at a fixed content width clips the still from left to right.
final class CaptureThumbnailButton: NSButton {
    var contentWidth: CGFloat = 220 { didSet { needsDisplay = true } }
    var timecode = "" { didSet { needsDisplay = true } }
    var capturedImage: NSImage? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        imagePosition = .noImage
        setAccessibilityLabel("Open captured frame".localized)
        wantsLayer = true
        layer?.shadowColor = NSColor(srgbRed: 20 / 255, green: 23 / 255,
                                     blue: 26 / 255, alpha: 0.24).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        layer?.shadowRadius = 12
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let content = NSRect(x: bounds.maxX - contentWidth, y: 0,
                             width: contentWidth, height: bounds.height)
        NSGraphicsContext.saveGraphicsState()
        let outline = NSBezierPath(roundedRect: content, xRadius: 12, yRadius: 12)
        outline.addClip()
        PanelStyle.inspectCanvas.setFill()
        NSBezierPath(rect: content).fill()
        let footer = NSRect(x: content.minX, y: isFlipped ? content.maxY - 25 : content.minY,
                            width: content.width, height: 25)
        let imageArea = NSRect(x: content.minX, y: isFlipped ? content.minY : footer.maxY,
                               width: content.width, height: max(0, content.height - 25))
        if let image = capturedImage, image.size.width > 0, image.size.height > 0 {
            let fit = min(imageArea.width / image.size.width, imageArea.height / image.size.height)
            let size = NSSize(width: image.size.width * fit, height: image.size.height * fit)
            let destination = NSRect(x: imageArea.midX - size.width / 2,
                                     y: imageArea.midY - size.height / 2,
                                     width: size.width, height: size.height)
            // Keep the complete captured frame, upright, above the separate footer.
            image.draw(in: destination, from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        PanelStyle.inspectChrome.setFill()
        NSBezierPath(rect: footer).fill()
        let label = NSAttributedString(string: timecode, attributes: [
            .font: PanelStyle.inspectFont(ofSize: 12, weight: .medium),
            .foregroundColor: PanelStyle.textPrimary
        ])
        let textFrame = NSRect(x: footer.minX + 10, y: footer.minY + 5,
                               width: content.width - 20, height: 15)
        label.draw(at: NSPoint(x: textFrame.minX, y: textFrame.midY - label.size().height / 2))
        NSColor.white.withAlphaComponent(0.12).setStroke()
        NSBezierPath(roundedRect: content.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12).stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Small screenshot acknowledgement: a quiet white shutter flash instead of
/// a large modal notification, paired with macOS's familiar Grab sound.
final class CaptureFeedbackView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.cornerRadius = 10
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func flash() {
        alphaValue = 0
        isHidden = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.06
            animator().alphaValue = 1
        }) { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.24
                self?.animator().alphaValue = 0
            }) { self?.isHidden = true }
        }
    }
}
