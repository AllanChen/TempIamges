import AppKit

/// Widget text outputs use the Figma side-window treatment so the source image
/// stays visible at its current size while the generated text remains readable.
final class WidgetTextResultWindow: NSPanel {
    private static let designSize = NSSize(width: 456, height: 720)
    private static let sideGap: CGFloat = 2
    private static let stackStep: CGFloat = 20

    var onDismiss: (() -> Void)?
    var onBecomeKey: (() -> Void)?

    private let rootView = WidgetTextResultRootView()
    private let titlebar = WidgetTextResultTitlebar()
    private lazy var closeTrafficButton = FigmaTrafficLightButton(
        color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1),
        target: self, action: #selector(closeTrafficTapped))
    private lazy var minimizeTrafficButton = FigmaTrafficLightButton(
        color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1),
        target: self, action: #selector(minimizeTrafficTapped))
    private lazy var zoomTrafficButton = FigmaTrafficLightButton(
        color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1),
        target: self, action: #selector(zoomTrafficTapped))
    private let titleLabel = PanelCenteredTextView()
    private let titlebarDivider = NSView()
    private let copyButton = WidgetTextCopyButton()
    private let widgetNameLabel = NSTextField(labelWithString: "")
    private let statusDot = PanelStyle.makeStatusDot(color: PanelStyle.success)
    private let statusLabel = NSTextField(labelWithString: "TEXT RESULT")
    private let inputPreview = WidgetTextInputPreviewView()
    private let inputLabel = NSTextField(labelWithString: "INPUT IMAGE".localized)
    private let filenameLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let contentDivider = NSView()
    private let resultScroll = NSScrollView()
    private let resultTextView = NSTextView()
    private let footerDivider = NSView()
    private let typeLabel = NSTextField(labelWithString: "Plain text".localized)
    private let characterCountLabel = NSTextField(labelWithString: "0 characters".localized)
    private var resultText = ""
    private var copyRevertWorkItem: DispatchWorkItem?

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.designSize),
                   styleMask: [.borderless, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 360, height: 520)
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeKey),
                                               name: NSWindow.didBecomeKeyNotification, object: self)

        let windowContainer = NSView()
        windowContainer.wantsLayer = true
        windowContainer.layer?.cornerRadius = 16
        windowContainer.layer?.cornerCurve = .continuous
        windowContainer.layer?.masksToBounds = true
        contentView = windowContainer
        windowContainer.superview?.wantsLayer = true
        windowContainer.superview?.layer?.cornerRadius = 16
        windowContainer.superview?.layer?.cornerCurve = .continuous
        windowContainer.superview?.layer?.masksToBounds = true

        let frost = PanelStyle.makeFrostedBase(cornerRadius: 16)
        frost.layer?.masksToBounds = true
        frost.layer?.borderWidth = 1
        frost.layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.textPrimary.withAlphaComponent(0.14))
        frost.frame = windowContainer.bounds
        frost.autoresizingMask = [.width, .height]
        windowContainer.addSubview(frost)
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 16
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.masksToBounds = true
        frost.addSubview(rootView)
        rootView.frame = frost.bounds
        rootView.autoresizingMask = [.width, .height]

        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = PanelStyle.resolvedCG(
            NSColor(srgbRed: 23 / 255, green: 24 / 255, blue: 29 / 255, alpha: 0.88))
        rootView.addSubview(titlebar)

        [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton].forEach(titlebar.addSubview)
        titleLabel.string = "Widget Result".localized
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.alignment = .center
        titlebar.addSubview(titleLabel)
        titlebarDivider.wantsLayer = true
        titlebarDivider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        titlebar.addSubview(titlebarDivider)
        copyButton.onPress = { [weak self] in self?.copyResult() }
        titlebar.addSubview(copyButton)

        widgetNameLabel.font = PanelStyle.inspectFont(ofSize: 17, weight: .semibold)
        widgetNameLabel.textColor = PanelStyle.textPrimary
        widgetNameLabel.lineBreakMode = .byTruncatingTail
        rootView.addSubview(widgetNameLabel)

        statusLabel.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        statusLabel.textColor = PanelStyle.success
        statusDot.layer?.cornerRadius = 4
        rootView.addSubview(statusDot)
        rootView.addSubview(statusLabel)

        rootView.addSubview(inputPreview)
        inputLabel.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        inputLabel.textColor = PanelStyle.textTertiary
        rootView.addSubview(inputLabel)
        filenameLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        filenameLabel.textColor = PanelStyle.textPrimary
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        rootView.addSubview(filenameLabel)
        metadataLabel.font = PanelStyle.inspectFont(ofSize: 11)
        metadataLabel.textColor = PanelStyle.textSecondary
        metadataLabel.lineBreakMode = .byTruncatingTail
        rootView.addSubview(metadataLabel)

        contentDivider.wantsLayer = true
        contentDivider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        rootView.addSubview(contentDivider)

        resultScroll.drawsBackground = false
        resultScroll.hasVerticalScroller = true
        resultScroll.autohidesScrollers = true
        resultScroll.scrollerStyle = .overlay
        resultScroll.borderType = .noBorder
        resultTextView.isEditable = false
        resultTextView.isSelectable = true
        resultTextView.drawsBackground = false
        resultTextView.isRichText = false
        resultTextView.isVerticallyResizable = true
        resultTextView.isHorizontallyResizable = false
        resultTextView.autoresizingMask = [.width]
        resultTextView.textContainer?.widthTracksTextView = true
        resultTextView.textContainer?.lineFragmentPadding = 0
        resultTextView.textContainerInset = .zero
        resultTextView.minSize = NSSize(width: 0, height: 0)
        resultTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                        height: CGFloat.greatestFiniteMagnitude)
        resultScroll.documentView = resultTextView
        rootView.addSubview(resultScroll)

        footerDivider.wantsLayer = true
        footerDivider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        rootView.addSubview(footerDivider)
        typeLabel.font = PanelStyle.inspectFont(ofSize: 11)
        typeLabel.textColor = PanelStyle.textTertiary
        rootView.addSubview(typeLabel)
        characterCountLabel.font = PanelStyle.inspectFont(ofSize: 11)
        characterCountLabel.textColor = PanelStyle.textTertiary
        characterCountLabel.alignment = .right
        rootView.addSubview(characterCountLabel)

        rootView.onLayout = { [weak self] bounds in self?.layoutContent(in: bounds) }
        layoutContent(in: rootView.bounds)
        setResultText("Waiting for Widget result…".localized,
                      color: PanelStyle.textTertiary, characterCount: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func layoutContent(in bounds: NSRect) {
        let width = bounds.width
        let height = bounds.height
        let titlebarHeight: CGFloat = 58
        titlebar.frame = NSRect(x: 0, y: height - titlebarHeight,
                                width: width, height: titlebarHeight)
        closeTrafficButton.frame = NSRect(x: 14, y: 19, width: 20, height: 20)
        minimizeTrafficButton.frame = NSRect(x: 34, y: 19, width: 20, height: 20)
        zoomTrafficButton.frame = NSRect(x: 54, y: 19, width: 20, height: 20)
        titleLabel.frame = NSRect(x: 0, y: 20, width: width, height: 18)
        titlebarDivider.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        copyButton.frame = NSRect(x: width - 102, y: 13, width: 82, height: 32)

        widgetNameLabel.frame = frameFromTop(x: 28, y: 82, width: max(0, width - 176),
                                             height: 22, containerHeight: height)
        statusDot.frame = frameFromTop(x: width - 105, y: 88, width: 8, height: 8,
                                       containerHeight: height)
        statusLabel.frame = frameFromTop(x: width - 89, y: 84, width: 61, height: 14,
                                         containerHeight: height)
        statusLabel.alignment = .right
        inputPreview.frame = frameFromTop(x: 28, y: 126, width: 128, height: 96,
                                          containerHeight: height)
        inputLabel.frame = frameFromTop(x: 176, y: 132, width: max(0, width - 204), height: 14,
                                        containerHeight: height)
        filenameLabel.frame = frameFromTop(x: 176, y: 157, width: max(0, width - 204), height: 18,
                                           containerHeight: height)
        metadataLabel.frame = frameFromTop(x: 176, y: 183, width: max(0, width - 204), height: 16,
                                           containerHeight: height)
        contentDivider.frame = frameFromTop(x: 28, y: 250, width: max(0, width - 56), height: 1,
                                            containerHeight: height)

        let footerY: CGFloat = 66
        footerDivider.frame = NSRect(x: 28, y: footerY, width: max(0, width - 56), height: 1)
        typeLabel.frame = NSRect(x: 28, y: 24, width: 120, height: 16)
        characterCountLabel.frame = NSRect(x: max(148, width - 178), y: 24,
                                           width: 150, height: 16)
        let resultTop = max(footerY + 14, height - 280)
        resultScroll.frame = NSRect(x: 28, y: footerY + 14, width: max(0, width - 56),
                                    height: max(0, resultTop - footerY - 14))
        layoutResultText()
    }

    private func frameFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                              containerHeight: CGFloat) -> NSRect {
        NSRect(x: x, y: containerHeight - y - height, width: width, height: height)
    }

    func showLoading(task: WidgetTaskRecord, source: MediaInfo,
                     sourceImage: NSImage?) {
        copyRevertWorkItem?.cancel()
        resultText = ""
        copyButton.isEnabled = false
        copyButton.setCopied(false)
        widgetNameLabel.stringValue = task.widgetName
        filenameLabel.stringValue = source.filename
        metadataLabel.stringValue = Self.metadataText(for: source)
        inputPreview.image = sourceImage
        characterCountLabel.stringValue = "0 characters".localized
        setResultText("Waiting for Widget result…".localized,
                      color: PanelStyle.textTertiary, characterCount: nil)
    }

    func updateSourceImage(_ image: NSImage) {
        inputPreview.image = image
    }

    func showResult(_ text: String) {
        resultText = text
        let displayed = text.isEmpty ? "No text returned".localized : text
        setResultText(displayed, color: PanelStyle.textPrimary,
                      characterCount: text.count)
        copyButton.isEnabled = !text.isEmpty
        resultTextView.scrollToBeginningOfDocument(nil)
    }

    func showError(_ message: String) {
        resultText = ""
        copyButton.isEnabled = false
        setResultText(message, color: PanelStyle.failure, characterCount: 0)
    }

    private func setResultText(_ text: String, color: NSColor, characterCount: Int?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 24
        paragraph.maximumLineHeight = 24
        paragraph.lineBreakMode = .byWordWrapping
        resultTextView.textStorage?.setAttributedString(NSAttributedString(
            string: text,
            attributes: [
                .font: PanelStyle.inspectFont(ofSize: 15),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]))
        if let characterCount {
            characterCountLabel.stringValue = "\(characterCount) characters"
        }
        layoutResultText()
    }

    private func layoutResultText() {
        let width = max(0, resultScroll.contentSize.width)
        resultTextView.textContainer?.containerSize = NSSize(
            width: width, height: CGFloat.greatestFiniteMagnitude)
        resultTextView.frame = NSRect(x: 0, y: 0, width: width,
                                      height: max(1, resultScroll.contentSize.height))
        guard let layoutManager = resultTextView.layoutManager,
              let textContainer = resultTextView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        resultTextView.frame.size.height = max(resultScroll.contentSize.height, usedHeight)
    }

    func present(alongside parentWindow: NSWindow) {
        if parent !== parentWindow {
            parent?.removeChildWindow(self)
            parentWindow.addChildWindow(self, ordered: .above)
        }
        makeKeyAndOrderFront(nil)
    }

    func position(alongside parentWindow: NSWindow, stackIndex: Int, stackCount: Int) {
        let parentFrame = parentWindow.frame
        let screen = parentWindow.screen
            ?? ScreenManager.shared.screenForMouseLocation(NSPoint(x: parentFrame.midX, y: parentFrame.midY))
            ?? NSScreen.main
        let available = screen?.visibleFrame ?? parentFrame
        let size = NSSize(width: min(Self.designSize.width, available.width),
                          height: min(Self.designSize.height, available.height))
        let step = min(Self.stackStep,
                       max(0, available.width - size.width) / CGFloat(max(1, stackCount - 1)))
        let rightmostOffset = CGFloat(max(0, stackCount - 1)) * step
        let baseX = max(available.minX,
                        min(parentFrame.maxX + Self.sideGap,
                            available.maxX - size.width - rightmostOffset))
        let originX = baseX + CGFloat(stackIndex) * step
        let originY = max(available.minY,
                          min(parentFrame.maxY - size.height, available.maxY - size.height))
        let proposed = NSRect(origin: NSPoint(x: originX, y: originY), size: size)
        if frame != proposed { setFrame(proposed, display: true) }
    }

    func dismiss() {
        copyRevertWorkItem?.cancel()
        parent?.removeChildWindow(self)
        orderOut(nil)
        let callback = onDismiss
        onDismiss = nil
        onBecomeKey = nil
        callback?()
    }

    override func close() {
        dismiss()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func didBecomeKey(_ notification: Notification) { onBecomeKey?() }

    private static func metadataText(for source: MediaInfo) -> String {
        let format = source.formatName.isEmpty
            ? source.url.pathExtension.uppercased()
            : source.formatName.uppercased()
        guard let dimensions = source.dimensions,
              dimensions.width > 0, dimensions.height > 0 else { return format }
        return "\(Int(dimensions.width.rounded())) × \(Int(dimensions.height.rounded()))  ·  \(format)"
    }

    private func copyResult() {
        guard !resultText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        copyButton.setCopied(true)
        copyRevertWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.copyButton.setCopied(false) }
        copyRevertWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    @objc private func closeTrafficTapped() { dismiss() }
    @objc private func minimizeTrafficTapped() { miniaturize(nil) }
    @objc private func zoomTrafficTapped() { zoom(nil) }
}

final class WidgetTextResultRootView: NSView {
    var onLayout: ((NSRect) -> Void)?
    override func layout() {
        super.layout()
        onLayout?(bounds)
    }
}

final class WidgetTextResultTitlebar: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

final class WidgetTextCopyButton: NSControl {
    var onPress: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "Copy".localized)
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        icon.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = PanelStyle.accent
        addSubview(icon)
        label.font = PanelStyle.inspectFont(ofSize: 11, weight: .semibold)
        label.textColor = PanelStyle.accent
        label.alignment = .center
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Copy result".localized)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }
    override func accessibilityPerformPress() -> Bool { performPress(); return true }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 11, y: 8.5, width: 15, height: 15)
        label.frame = NSRect(x: 28, y: 8, width: max(0, bounds.width - 36), height: 16)
    }
    override func mouseDown(with event: NSEvent) {
        if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) { performPress() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = PanelStyle.resolvedCG(
            PanelStyle.inspectToolbar.blended(withFraction: 0.12, of: PanelStyle.accent)
                ?? PanelStyle.inspectToolbar)
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
    }
    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
            setAccessibilityEnabled(isEnabled)
        }
    }
    func setCopied(_ copied: Bool) {
        icon.image = NSImage(systemSymbolName: copied ? "checkmark" : "doc.on.doc",
                             accessibilityDescription: nil)
        icon.contentTintColor = copied ? PanelStyle.success : PanelStyle.accent
        label.stringValue = copied ? "Copied".localized : "Copy".localized
        label.textColor = copied ? PanelStyle.success : PanelStyle.accent
    }
    private func performPress() { onPress?() }
}

final class WidgetTextInputPreviewView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        PanelStyle.inspectCanvas.setFill()
        bounds.fill()
        if let image, image.size.width > 0, image.size.height > 0 {
            let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let destination = NSRect(x: bounds.midX - size.width / 2,
                                     y: bounds.midY - size.height / 2,
                                     width: size.width, height: size.height)
            image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        } else if let placeholder = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
            placeholder.draw(in: NSRect(x: bounds.midX - 10, y: bounds.midY - 10,
                                        width: 20, height: 20),
                             from: .zero, operation: .sourceOver, fraction: 0.45)
        }
        NSGraphicsContext.restoreGraphicsState()
        PanelStyle.inspectLine.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
