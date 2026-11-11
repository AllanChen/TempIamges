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
        track.wantsLayer = true
        track.layer?.backgroundColor = PanelStyle.inspectLine.cgColor
        track.layer?.cornerRadius = 2
        addSubview(track)

        fill.wantsLayer = true
        fill.layer?.backgroundColor = PanelStyle.accent.cgColor
        fill.layer?.cornerRadius = 2
        addSubview(fill)

        knob.wantsLayer = true
        knob.layer?.backgroundColor = PanelStyle.textPrimary.cgColor
        knob.layer?.cornerRadius = 7
        knob.layer?.shadowColor = NSColor.black.cgColor
        knob.layer?.shadowOffset = NSSize(width: 0, height: 2)
        knob.layer?.shadowRadius = 4
        knob.layer?.shadowOpacity = 0.35
        addSubview(knob)

        layoutLayers()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        let trackHeight: CGFloat = 4
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
        checkmark.frame = NSRect(x: 2, y: 2, width: 12, height: 12)
        box.addSubview(checkmark)

        label.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        label.textColor = PanelStyle.textPrimary
        label.frame = NSRect(x: 26, y: 3, width: 284, height: 15)
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
        box.layer?.backgroundColor = (isOn ? PanelStyle.accent : PanelStyle.inspectChrome).cgColor
        box.layer?.borderColor = (isOn ? PanelStyle.accent : PanelStyle.inspectLine).cgColor
        checkmark.isHidden = !isOn
    }
}

final class CompressionDialogPanel: NSPanel {
    var onConfirm: ((CGFloat, Int64, Bool) -> Void)?
    var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Compress Image".localized)
    private let captionLabel = NSTextField(labelWithString: "Lower quality means a smaller file.".localized)
    private let qualityLabel = NSTextField(labelWithString: "Quality".localized)
    private let qualityValueLabel = NSTextField(labelWithString: "70%")
    private let slider = CompressionSlider()
    private let sliderHint = NSTextField(labelWithString: "10% – 100%")
    private let keepDimensionsCheckbox = CompressionCheckbox()
    private let resultCard = NSView()
    private let resultLabel = NSTextField(labelWithString: "Compressed size".localized)
    private let resultValueLabel = NSTextField(labelWithString: "")
    private let cancelButton = PanelButton(title: "Cancel".localized, target: nil, action: nil)
    private let compressButton = PanelButton(title: "Compress".localized, target: nil, action: nil)
    private let sourceByteCount: Int64
    private var targetByteCount: Int64 = 1_024

    private var keyMonitor: Any?

    init(sourceByteCount: Int64) {
        self.sourceByteCount = max(1, sourceByteCount)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 350, height: 280),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 280))
        content.wantsLayer = true
        content.layer?.backgroundColor = PanelStyle.inspectChrome.cgColor
        content.layer?.cornerRadius = 14
        content.layer?.borderWidth = 1
        content.layer?.borderColor = PanelStyle.inspectLine.cgColor
        contentView = content

        titleLabel.font = PanelStyle.inspectFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.frame = NSRect(x: 20, y: 242, width: 310, height: 18)
        content.addSubview(titleLabel)

        captionLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .regular)
        captionLabel.textColor = PanelStyle.textSecondary
        captionLabel.frame = NSRect(x: 20, y: 221, width: 310, height: 15)
        content.addSubview(captionLabel)

        qualityLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        qualityLabel.textColor = PanelStyle.textPrimary
        qualityLabel.frame = NSRect(x: 20, y: 187, width: 160, height: 15)
        content.addSubview(qualityLabel)

        qualityValueLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
        qualityValueLabel.textColor = PanelStyle.accent
        qualityValueLabel.alignment = .right
        qualityValueLabel.frame = NSRect(x: 268, y: 187, width: 62, height: 15)
        content.addSubview(qualityValueLabel)

        slider.value = 0.7
        slider.valueChanged = { [weak self] value in
            self?.updateValues(for: value)
        }
        slider.frame = NSRect(x: 20, y: 168, width: 310, height: 16)
        content.addSubview(slider)

        sliderHint.font = PanelStyle.inspectFont(ofSize: 11, weight: .regular)
        sliderHint.textColor = PanelStyle.textTertiary
        sliderHint.frame = NSRect(x: 20, y: 153, width: 310, height: 13)
        content.addSubview(sliderHint)

        keepDimensionsCheckbox.target = self
        keepDimensionsCheckbox.action = #selector(keepDimensionsChanged)
        keepDimensionsCheckbox.frame = NSRect(x: 20, y: 118, width: 310, height: 20)
        content.addSubview(keepDimensionsCheckbox)

        resultCard.wantsLayer = true
        resultCard.layer?.backgroundColor = NSColor(srgbRed: 17 / 255, green: 18 / 255, blue: 23 / 255, alpha: 1).cgColor
        resultCard.layer?.cornerRadius = 8
        resultCard.layer?.borderWidth = 1
        resultCard.layer?.borderColor = PanelStyle.inspectLine.cgColor
        resultCard.frame = NSRect(x: 20, y: 66, width: 310, height: 38)
        content.addSubview(resultCard)

        resultLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        resultLabel.textColor = PanelStyle.textSecondary
        resultLabel.frame = NSRect(x: 12, y: 12, width: 150, height: 15)
        resultCard.addSubview(resultLabel)

        resultValueLabel.font = PanelStyle.inspectFont(ofSize: 15, weight: .semibold)
        resultValueLabel.textColor = PanelStyle.textPrimary
        resultValueLabel.alignment = .right
        resultValueLabel.frame = NSRect(x: 212, y: 11, width: 86, height: 18)
        resultCard.addSubview(resultValueLabel)

        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.normalBackground = PanelStyle.inspectChrome
        cancelButton.hoverBackground = PanelStyle.inspectLine
        cancelButton.titleColor = PanelStyle.textPrimary
        cancelButton.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        cancelButton.layer?.borderColor = PanelStyle.inspectLine.cgColor
        cancelButton.frame = NSRect(x: 170, y: 12, width: 80, height: 32)
        content.addSubview(cancelButton)

        compressButton.target = self
        compressButton.action = #selector(compressTapped)
        compressButton.normalBackground = PanelStyle.accent
        compressButton.hoverBackground = PanelStyle.accentHover
        compressButton.titleColor = PanelStyle.accentInk
        compressButton.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
        compressButton.layer?.borderWidth = 0
        compressButton.frame = NSRect(x: 260, y: 12, width: 90, height: 32)
        content.addSubview(compressButton)

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
        qualityValueLabel.stringValue = String(format: "%.0f%%", quality * 100)
        targetByteCount = CompressionSizeEstimate.byteCount(sourceByteCount: sourceByteCount,
                                                             quality: quality)
        resultValueLabel.stringValue = ByteCountFormatter.string(fromByteCount: targetByteCount,
                                                                  countStyle: .file)
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

final class ResizeDialogPanel: NSPanel {
    var onConfirm: ((CGFloat) -> Void)?
    var onCancel: (() -> Void)?

    private let sourceImage: CGImage
    private let sourceByteCount: Int64
    private let scaleValueLabel = NSTextField(labelWithString: "70%")
    private let slider = CompressionSlider()
    private let resultValueLabel = NSTextField(labelWithString: "")
    private let resizeButton = PanelButton(title: "Resize".localized, target: nil, action: nil)
    private var selectedScale: CGFloat = 0.7
    private var keyMonitor: Any?

    init(sourceImage: CGImage, sourceByteCount: Int64) {
        self.sourceImage = sourceImage
        self.sourceByteCount = max(1, sourceByteCount)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 350, height: 248),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 248))
        content.wantsLayer = true
        content.layer?.backgroundColor = PanelStyle.inspectChrome.cgColor
        content.layer?.cornerRadius = 14
        content.layer?.borderWidth = 1
        content.layer?.borderColor = PanelStyle.inspectLine.cgColor
        contentView = content

        let titleLabel = NSTextField(labelWithString: "Resize Image".localized)
        titleLabel.font = PanelStyle.inspectFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.frame = NSRect(x: 20, y: 210, width: 310, height: 18)
        content.addSubview(titleLabel)

        let captionLabel = NSTextField(labelWithString: "Scale down proportionally.".localized)
        captionLabel.font = PanelStyle.inspectFont(ofSize: 12)
        captionLabel.textColor = PanelStyle.textSecondary
        captionLabel.frame = NSRect(x: 20, y: 189, width: 310, height: 15)
        content.addSubview(captionLabel)

        let scaleLabel = NSTextField(labelWithString: "Scale".localized)
        scaleLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        scaleLabel.textColor = PanelStyle.textPrimary
        scaleLabel.frame = NSRect(x: 20, y: 155, width: 160, height: 15)
        content.addSubview(scaleLabel)

        scaleValueLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
        scaleValueLabel.textColor = PanelStyle.accent
        scaleValueLabel.alignment = .right
        scaleValueLabel.frame = NSRect(x: 268, y: 155, width: 62, height: 15)
        content.addSubview(scaleValueLabel)

        slider.minimumValue = 0.01
        slider.maximumValue = 0.99
        slider.value = 0.7
        slider.setAccessibilityRole(.slider)
        slider.setAccessibilityLabel("Scale".localized)
        slider.valueChanged = { [weak self] value in self?.updateValues(for: value) }
        slider.frame = NSRect(x: 20, y: 136, width: 310, height: 16)
        content.addSubview(slider)

        let sliderHint = NSTextField(labelWithString: "1% – 99%")
        sliderHint.font = PanelStyle.inspectFont(ofSize: 11)
        sliderHint.textColor = PanelStyle.textTertiary
        sliderHint.frame = NSRect(x: 20, y: 121, width: 310, height: 13)
        content.addSubview(sliderHint)

        let resultCard = NSView()
        resultCard.wantsLayer = true
        resultCard.layer?.backgroundColor = NSColor(srgbRed: 17 / 255, green: 18 / 255, blue: 23 / 255, alpha: 1).cgColor
        resultCard.layer?.cornerRadius = 8
        resultCard.layer?.borderWidth = 1
        resultCard.layer?.borderColor = PanelStyle.inspectLine.cgColor
        resultCard.frame = NSRect(x: 20, y: 66, width: 310, height: 38)
        content.addSubview(resultCard)

        resultValueLabel.font = PanelStyle.inspectFont(ofSize: 15, weight: .semibold)
        resultValueLabel.textColor = PanelStyle.textPrimary
        resultValueLabel.alignment = .center
        resultValueLabel.frame = NSRect(x: 12, y: 11, width: 286, height: 18)
        resultCard.addSubview(resultValueLabel)

        let cancelButton = PanelButton(title: "Cancel".localized, target: nil, action: nil)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.normalBackground = PanelStyle.inspectChrome
        cancelButton.hoverBackground = PanelStyle.inspectLine
        cancelButton.titleColor = PanelStyle.textPrimary
        cancelButton.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        cancelButton.layer?.borderColor = PanelStyle.inspectLine.cgColor
        cancelButton.frame = NSRect(x: 170, y: 12, width: 80, height: 32)
        content.addSubview(cancelButton)

        resizeButton.target = self
        resizeButton.action = #selector(resizeTapped)
        resizeButton.normalBackground = PanelStyle.accent
        resizeButton.hoverBackground = PanelStyle.accentHover
        resizeButton.titleColor = PanelStyle.accentInk
        resizeButton.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .semibold)
        resizeButton.layer?.borderWidth = 0
        resizeButton.frame = NSRect(x: 260, y: 12, width: 90, height: 32)
        content.addSubview(resizeButton)

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
        scaleValueLabel.stringValue = "\(percent)%"
        slider.setAccessibilityValue(percent)
        if let dimensions = ImageResizePlan.dimensions(sourceWidth: sourceImage.width,
                                                       sourceHeight: sourceImage.height,
                                                       scale: selectedScale) {
            let byteCount = ImageResizePlan.estimatedByteCount(sourceByteCount: sourceByteCount, scale: selectedScale)
            let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            resultValueLabel.stringValue = "\(dimensions.width) × \(dimensions.height)  \(size)"
            resizeButton.isEnabled = true
        } else {
            resultValueLabel.stringValue = "—"
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
