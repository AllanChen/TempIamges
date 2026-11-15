import AppKit

// MARK: - Image compression dialog

enum ImageCompressionFormat {
    static func exportFormat(for sourceURL: URL) -> ImageExportFormat? {
        switch sourceURL.pathExtension.lowercased() {
        case "jpg", "jpeg", "jpe", "jfif": return .jpeg
        case "png", "apng": return .png
        case "webp": return .webP
        case "heic", "heif": return .heic
        case "tif", "tiff": return .tiff
        case "gif": return .gif
        default: return nil
        }
    }
}

enum ImageResizePlan {
    static func dimensions(sourceWidth: Int, sourceHeight: Int, scale: CGFloat) -> (width: Int, height: Int)? {
        guard sourceWidth > 0, sourceHeight > 0, scale > 0, scale < 1 else { return nil }
        let width = max(1, Int((Double(sourceWidth) * Double(scale)).rounded()))
        let height = max(1, Int((Double(sourceHeight) * Double(scale)).rounded()))
        guard width < sourceWidth || height < sourceHeight else { return nil }
        return (width, height)
    }

    static func estimatedByteCount(sourceByteCount: Int64, scale: CGFloat) -> Int64 {
        let clamped = max(0.0001, min(1, scale))
        return max(1, Int64((Double(max(1, sourceByteCount)) * clamped * clamped).rounded()))
    }
}

enum CompressionSizeEstimate {
    static func byteCount(sourceByteCount: Int64, quality: CGFloat) -> Int64 {
        let clampedQuality = max(0.1, min(1, quality))
        let factor = 0.18 + 0.82 * pow(Double(clampedQuality), 1.45)
        return max(1_024, Int64(Double(max(1, sourceByteCount)) * factor))
    }
}

final class CompressionSlider: NSView {
    var minimumValue: CGFloat = 0.1 { didSet { layoutLayers() } }
    var maximumValue: CGFloat = 1 { didSet { layoutLayers() } }
    var value: CGFloat = 0.7 {
        didSet {
            guard value != oldValue else { return }
            layoutLayers()
            valueChanged?(value)
        }
    }
    var valueChanged: ((CGFloat) -> Void)?

    private let track = NSView()
    private let fill = NSView()
    private let knob = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        // Figma `slider`: a 2 pt ink/4 track, text/1 fill and a 14 pt text/1 knob.
        track.wantsLayer = true
        track.layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.ink4)
        track.layer?.cornerRadius = 1
        addSubview(track)

        fill.wantsLayer = true
        fill.layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.text1)
        addSubview(fill)

        knob.wantsLayer = true
        knob.layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.text1)
        knob.layer?.cornerRadius = 7
        addSubview(knob)

        layoutLayers()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        let trackHeight: CGFloat = 2
        let knobSize: CGFloat = 14
        let y = (bounds.height - trackHeight) / 2
        track.frame = NSRect(x: 0, y: y, width: bounds.width, height: trackHeight)

        let fillWidth = bounds.width * max(0, min(1, value))
        fill.frame = NSRect(x: 0, y: y, width: fillWidth, height: trackHeight)

        let knobX = fillWidth - knobSize / 2
        knob.frame = NSRect(x: knobX, y: (bounds.height - knobSize) / 2, width: knobSize, height: knobSize)
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInSelf = convert(point, from: superview)
        return bounds.contains(pointInSelf) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handleMouse(event)
    }
    override func mouseDragged(with event: NSEvent) { handleMouse(event) }

    private func handleMouse(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let fraction = max(0, min(1, point.x / max(1, bounds.width)))
        value = minimumValue + (maximumValue - minimumValue) * fraction
    }
}

final class CompressionDimmerView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

final class CompressionCheckbox: NSControl {
    var isOn = true { didSet { refresh() } }

    private let box = NSView()
    private let checkmark = NSImageView()
    private let label = NSTextField(labelWithString: "Keep original dimensions".localized)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        box.wantsLayer = true
        box.layer?.cornerRadius = 4
        box.layer?.borderWidth = 1
        box.frame = NSRect(x: 0, y: 2, width: 16, height: 16)
        addSubview(box)

        checkmark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        checkmark.imageScaling = .scaleProportionallyUpOrDown
        checkmark.contentTintColor = PanelStyle.accentInk
        checkmark.image = checkmark.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        checkmark.imageScaling = .scaleNone
        checkmark.frame = NSRect(x: 2, y: 2, width: 12, height: 12)
        box.addSubview(checkmark)

        label.font = PanelStyle.inspectFont(ofSize: 13)
        label.textColor = InspectInk.text1
        label.frame = NSRect(x: 24, y: 1, width: 300, height: 17)
        addSubview(label)

        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("Keep original dimensions".localized)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isOn.toggle()
        sendAction(action, to: target)
    }

    override func accessibilityValue() -> Any? { isOn }

    private func refresh() {
        box.layer?.backgroundColor = PanelStyle.resolvedCG(isOn ? InspectInk.text1 : .clear)
        box.layer?.borderColor = PanelStyle.resolvedCG(isOn ? InspectInk.text1 : InspectInk.lineStrong)
        checkmark.isHidden = !isOn
    }
}

/// Figma `23 · Tool dialogs / Compress Image` (440 × 348): Mincho title,
/// caption, the quality slider, Original / Compressed size rows, the keep-size
/// check and Cancel / Compress. Positions are the Figma top-origin values.
final class CompressionDialogPanel: NSPanel {
    var onConfirm: ((CGFloat, Int64, Bool) -> Void)?
    var onCancel: (() -> Void)?

    private let qualityValueLabel = InspectTextLabel("70%", font: PanelStyle.monoFont(ofSize: 12),
                                                     color: InspectInk.text1, alignment: .right)
    private let slider = CompressionSlider()
    private let keepDimensionsCheckbox = CompressionCheckbox()
    private let originalRow = InspectDialogRow(key: "Original".localized)
    private let resultRow = InspectDialogRow(key: "Compressed size".localized)
    private let sourceByteCount: Int64
    private var targetByteCount: Int64 = 1_024

    private var keyMonitor: Any?
    private static let size = NSSize(width: 440, height: 348)

    init(sourceByteCount: Int64) {
        self.sourceByteCount = max(1, sourceByteCount)
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = PanelStyle.windowAppearance
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = InspectDialogContentView(frame: NSRect(origin: .zero, size: Self.size))
        InspectDialogLayout.styleCard(content)
        contentView = content
        InspectDialogLayout.addHeader(to: content, title: "Compress Image".localized,
                                      caption: "Lower quality means a smaller file.".localized)

        let qualityLabel = InspectTextLabel("Quality".localized, font: PanelStyle.inspectFont(ofSize: 12),
                                            color: InspectInk.text3)
        qualityLabel.frame = NSRect(x: 29, y: 109, width: 300, height: 15)
        content.addSubview(qualityLabel)
        qualityValueLabel.frame = NSRect(x: 311, y: 109, width: 100, height: 16)
        content.addSubview(qualityValueLabel)

        slider.value = 0.7
        slider.setAccessibilityRole(.slider)
        slider.setAccessibilityLabel("Quality".localized)
        slider.valueChanged = { [weak self] value in
            self?.updateValues(for: value)
        }
        slider.frame = NSRect(x: 29, y: 137, width: 384, height: 14)
        content.addSubview(slider)

        originalRow.value = ByteCountFormatter.string(fromByteCount: self.sourceByteCount, countStyle: .file)
        originalRow.frame = NSRect(x: 29, y: 171, width: 382, height: 33)
        content.addSubview(originalRow)
        resultRow.valueColor = PanelStyle.success
        resultRow.frame = NSRect(x: 29, y: 204, width: 382, height: 33)
        content.addSubview(resultRow)

        keepDimensionsCheckbox.target = self
        keepDimensionsCheckbox.action = #selector(keepDimensionsChanged)
        keepDimensionsCheckbox.frame = NSRect(x: 29, y: 249, width: 382, height: 20)
        content.addSubview(keepDimensionsCheckbox)

        InspectDialogLayout.addButtons(to: content, top: 291, rightEdge: 411, buttons: [
            InspectDialogButton.make("Cancel".localized, primary: false, target: self, action: #selector(cancelTapped)),
            InspectDialogButton.make("Compress".localized, primary: true, target: self, action: #selector(compressTapped))
        ])

        updateValues(for: slider.value)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancelTapped()
            return nil
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func updateValues(for quality: CGFloat) {
        qualityValueLabel.string = String(format: "%.0f%%", quality * 100)
        slider.setAccessibilityValue(qualityValueLabel.string)
        targetByteCount = CompressionSizeEstimate.byteCount(sourceByteCount: sourceByteCount,
                                                             quality: quality)
        let saving = Int((1 - Double(targetByteCount) / Double(sourceByteCount)) * 100)
        let size = ByteCountFormatter.string(fromByteCount: targetByteCount, countStyle: .file)
        resultRow.value = saving > 0 ? "\(size)  ·  −\(saving)%" : size
    }

    @objc private func keepDimensionsChanged() {
        updateValues(for: slider.value)
    }

    func present(over parent: NSWindow) {
        let parentFrame = parent.frame
        let origin = NSPoint(x: parentFrame.midX - frame.width / 2,
                             y: parentFrame.midY - frame.height / 2)
        setFrameOrigin(origin)
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        parent?.removeChildWindow(self)
        super.close()
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func compressTapped() {
        onConfirm?(slider.value, targetByteCount, keepDimensionsCheckbox.isOn)
    }
}

/// Figma `23 · Tool dialogs / Resize Image` (440 × 318): the scale slider,
/// Original / New size rows (with the estimated file size) and Cancel / Resize.
final class ResizeDialogPanel: NSPanel {
    var onConfirm: ((CGFloat) -> Void)?
    var onCancel: (() -> Void)?

    private let sourceImage: CGImage
    private let sourceByteCount: Int64
    private let scaleValueLabel = InspectTextLabel("70%", font: PanelStyle.monoFont(ofSize: 12),
                                                   color: InspectInk.text1, alignment: .right)
    private let slider = CompressionSlider()
    private let resultRow = InspectDialogRow(key: "New size".localized)
    private let resizeButton = InspectDialogButton.make("Resize".localized, primary: true, target: nil, action: nil)
    private var selectedScale: CGFloat = 0.7
    private var keyMonitor: Any?
    private static let size = NSSize(width: 440, height: 318)

    init(sourceImage: CGImage, sourceByteCount: Int64) {
        self.sourceImage = sourceImage
        self.sourceByteCount = max(1, sourceByteCount)
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = PanelStyle.windowAppearance
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = InspectDialogContentView(frame: NSRect(origin: .zero, size: Self.size))
        InspectDialogLayout.styleCard(content)
        contentView = content
        InspectDialogLayout.addHeader(to: content, title: "Resize Image".localized,
                                      caption: "Scale down proportionally.".localized)

        let scaleLabel = InspectTextLabel("Scale".localized, font: PanelStyle.inspectFont(ofSize: 12),
                                          color: InspectInk.text3)
        scaleLabel.frame = NSRect(x: 29, y: 109, width: 300, height: 15)
        content.addSubview(scaleLabel)
        scaleValueLabel.frame = NSRect(x: 311, y: 109, width: 100, height: 16)
        content.addSubview(scaleValueLabel)

        slider.minimumValue = 0.01
        slider.maximumValue = 0.99
        slider.value = 0.7
        slider.setAccessibilityRole(.slider)
        slider.setAccessibilityLabel("Scale".localized)
        slider.valueChanged = { [weak self] value in self?.updateValues(for: value) }
        slider.frame = NSRect(x: 29, y: 137, width: 384, height: 14)
        content.addSubview(slider)

        let originalRow = InspectDialogRow(key: "Original".localized)
        originalRow.value = "\(sourceImage.width) × \(sourceImage.height)"
        originalRow.frame = NSRect(x: 29, y: 171, width: 382, height: 33)
        content.addSubview(originalRow)
        resultRow.frame = NSRect(x: 29, y: 204, width: 382, height: 33)
        content.addSubview(resultRow)

        resizeButton.target = self
        resizeButton.action = #selector(resizeTapped)
        InspectDialogLayout.addButtons(to: content, top: 261, rightEdge: 411, buttons: [
            InspectDialogButton.make("Cancel".localized, primary: false, target: self, action: #selector(cancelTapped)),
            resizeButton
        ])

        updateValues(for: slider.value)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancelTapped()
            return nil
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func updateValues(for scale: CGFloat) {
        let percent = max(1, min(99, Int((scale * 100).rounded())))
        selectedScale = CGFloat(percent) / 100
        scaleValueLabel.string = "\(percent)%"
        slider.setAccessibilityValue(percent)
        if let dimensions = ImageResizePlan.dimensions(sourceWidth: sourceImage.width,
                                                       sourceHeight: sourceImage.height,
                                                       scale: selectedScale) {
            let byteCount = ImageResizePlan.estimatedByteCount(sourceByteCount: sourceByteCount, scale: selectedScale)
            let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            resultRow.value = "\(dimensions.width) × \(dimensions.height)  ·  \(size)"
            resizeButton.isEnabled = true
        } else {
            resultRow.value = "—"
            resizeButton.isEnabled = false
        }
    }

    func present(over parent: NSWindow) {
        let parentFrame = parent.frame
        setFrameOrigin(NSPoint(x: parentFrame.midX - frame.width / 2,
                               y: parentFrame.midY - frame.height / 2))
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        parent?.removeChildWindow(self)
        super.close()
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func resizeTapped() {
        onConfirm?(selectedScale)
    }
}

/// Shared Figma dialog card: ink/1, line/strong edge, 12 pt corners; title
/// (Mincho 22 / 30) at 29 / 29 and the 13 / 20 caption 6 pt below it.
enum InspectDialogLayout {
    static func styleCard(_ content: NSView) {
        content.wantsLayer = true
        content.layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.ink1)
        content.layer?.cornerRadius = PanelStyle.Radius.window
        content.layer?.borderWidth = 1
        content.layer?.borderColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
    }

    static func addHeader(to content: NSView, title: String, caption: String) {
        let width = content.bounds.width - 58
        let titleLabel = InspectTextLabel(title, font: PanelStyle.titleFont(ofSize: 22), color: InspectInk.text1)
        titleLabel.frame = NSRect(x: 29, y: 29, width: width, height: 30)
        content.addSubview(titleLabel)
        let captionLabel = InspectTextLabel(caption, font: PanelStyle.inspectFont(ofSize: 13), color: InspectInk.text2)
        captionLabel.frame = NSRect(x: 29, y: 65, width: width, height: 20)
        content.addSubview(captionLabel)
    }

    /// Right-aligned 32 pt buttons with 8 pt gaps; their labels are centred by PanelButton.
    static func addButtons(to content: NSView, top: CGFloat, rightEdge: CGFloat, buttons: [PanelButton]) {
        var x = rightEdge
        for button in buttons.reversed() {
            let width = InspectDialogButton.width(button.title)
            x -= width
            button.frame = NSRect(x: x, y: top, width: width, height: 32)
            content.addSubview(button)
            x -= 8
        }
    }
}
