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
    private lazy var closeTrafficButton = TrafficLightButton(
        color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1),
        target: self, action: #selector(closeTrafficTapped))
    private lazy var minimizeTrafficButton = TrafficLightButton(
        color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1),
        target: self, action: #selector(minimizeTrafficTapped))
    private lazy var zoomTrafficButton = TrafficLightButton(
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
        appearance = PanelStyle.windowAppearance
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeKey),
                                               name: NSWindow.didBecomeKeyNotification, object: self)

        let windowContainer = NSView()
        contentView = windowContainer
        WidgetTextResultChrome.styleWindow(container: windowContainer, root: rootView)
        WidgetTextResultChrome.styleTitlebar(titlebar, title: titleLabel, text: "Widget Result".localized,
                                             traffic: [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton],
                                             divider: titlebarDivider, in: rootView)
        copyButton.idleTitle = "Copy result".localized
        copyButton.onPress = { [weak self] in self?.copyResult() }
        rootView.addSubview(copyButton)

        // Figma `33 · Widget Result / Text`: a 44 pt source thumbnail, the
        // Widget name (13 pt medium) and the source in mono, then a caption.
        widgetNameLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        widgetNameLabel.textColor = InspectInk.text1
        widgetNameLabel.lineBreakMode = .byTruncatingTail
        rootView.addSubview(widgetNameLabel)

        statusLabel.font = PanelStyle.monoFont(ofSize: 11)
        statusLabel.textColor = InspectInk.text3
        statusDot.isHidden = true
        rootView.addSubview(statusDot)
        rootView.addSubview(statusLabel)

        rootView.addSubview(inputPreview)
        inputLabel.isHidden = true
        rootView.addSubview(inputLabel)
        filenameLabel.font = PanelStyle.monoFont(ofSize: 11)
        filenameLabel.textColor = InspectInk.text3
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        rootView.addSubview(filenameLabel)
        metadataLabel.isHidden = true
        rootView.addSubview(metadataLabel)

        contentDivider.isHidden = true
        rootView.addSubview(contentDivider)

        resultScroll.drawsBackground = false
        resultScroll.hasVerticalScroller = true
        PanelStyle.styleScrollers(in: resultScroll)
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

        WidgetTextResultChrome.styleFooter(divider: footerDivider, count: characterCountLabel, in: rootView)
        // The result type is part of the caption above the text.
        typeLabel.isHidden = true
        rootView.addSubview(typeLabel)
        statusLabel.stringValue = Self.captionText

        rootView.onLayout = { [weak self] bounds in self?.layoutContent(in: bounds) }
        layoutContent(in: rootView.bounds)
        setResultText("Waiting for Widget result…".localized,
                      color: PanelStyle.textTertiary, characterCount: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Figma `RESULT  ·  PLAIN TEXT` caption (mono 11, text/3).
    private static var captionText: String {
        ("Result".localized + "  ·  " + "Plain text".localized).uppercased()
    }

    /// Figma (top-origin, 31 pt sides): header at 71 (44 pt thumbnail, name and
    /// source beside it), caption 28 pt below, the text 12 pt below that, and
    /// the footer rule 16 pt above the 32 pt Copy button, 25 pt from the foot.
    private func layoutContent(in bounds: NSRect) {
        let width = bounds.width
        let height = bounds.height
        WidgetTextResultChrome.layoutTitlebar(titlebar, title: titleLabel,
                                              traffic: [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton],
                                              divider: titlebarDivider, width: width, height: height)
        let inset: CGFloat = 31
        let textWidth = max(0, width - inset * 2)
        inputPreview.frame = frameFromTop(x: inset, y: 71, width: 44, height: 44, containerHeight: height)
        widgetNameLabel.frame = frameFromTop(x: inset + 56, y: 76, width: max(0, textWidth - 56), height: 17,
                                             containerHeight: height)
        filenameLabel.frame = frameFromTop(x: inset + 56, y: 96, width: max(0, textWidth - 56), height: 15,
                                           containerHeight: height)
        statusLabel.frame = frameFromTop(x: inset, y: 143, width: textWidth, height: 15, containerHeight: height)
        statusLabel.alignment = .left
        statusDot.frame = .zero
        inputLabel.frame = .zero
        metadataLabel.frame = .zero
        contentDivider.frame = .zero

        let copyWidth = copyButton.preferredWidth
        copyButton.frame = NSRect(x: width - inset - copyWidth, y: 25, width: copyWidth, height: 32)
        let footerY = WidgetTextResultChrome.layoutFooter(divider: footerDivider, count: characterCountLabel,
                                                          inset: inset, width: width)
        typeLabel.frame = .zero
        let resultTop = height - 170
        resultScroll.frame = NSRect(x: inset, y: footerY + 16, width: textWidth,
                                    height: max(0, resultTop - footerY - 16))
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
        filenameLabel.stringValue = source.filename + "  ·  " + Self.metadataText(for: source)
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
        setResultText(displayed, color: InspectInk.text1,
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
        paragraph.minimumLineHeight = 26
        paragraph.maximumLineHeight = 26
        paragraph.lineBreakMode = .byWordWrapping
        resultTextView.textStorage?.setAttributedString(NSAttributedString(
            string: text,
            attributes: [
                .font: PanelStyle.inspectFont(ofSize: 15),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]))
        if let characterCount {
            characterCountLabel.stringValue = String(format: "%d characters".localized, characterCount)
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

/// Figma primary `Button` (text/1 fill, 13 pt medium ink label, 32 pt high,
/// 16 pt padding). Shows "Copied" briefly after a copy.
final class WidgetTextCopyButton: NSControl {
    var onPress: (() -> Void)?
    /// The resting title ("Copy result", "Copy All").
    var idleTitle = "Copy".localized { didSet { if !copied { title = idleTitle } } }
    private var title = "Copy".localized { didSet { setAccessibilityLabel(title); needsDisplay = true } }
    private var copied = false
    private var hovering = false
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }
    override func accessibilityPerformPress() -> Bool { performPress(); return true }
    /// Wide enough for both the resting and the "Copied" title, so it never jumps.
    var preferredWidth: CGFloat {
        max(InspectDialogButton.width(idleTitle), InspectDialogButton.width("Copied".localized))
    }

    override func draw(_ dirtyRect: NSRect) {
        let plate = NSBezierPath(roundedRect: bounds, xRadius: PanelStyle.Radius.control, yRadius: PanelStyle.Radius.control)
        (hovering && isEnabled ? PanelStyle.accentHover : InspectInk.text1).setFill()
        plate.fill()
        // Centre the 13 pt label in the 32 pt plate (Figma auto layout, items-center).
        let font = InspectDialogButton.font
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        InspectText.draw(title, in: NSRect(x: 0, y: (bounds.height - lineHeight) / 2, width: bounds.width, height: lineHeight),
                         font: font, color: PanelStyle.accentInk, align: .center)
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
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
            setAccessibilityEnabled(isEnabled)
        }
    }
    func setCopied(_ copied: Bool) {
        self.copied = copied
        title = copied ? "Copied".localized : idleTitle
    }
    private func performPress() { onPress?() }
}

/// Shared Shizuka chrome of the side text windows (Recognize Text, Widget
/// Result): ink/1 plate, line/strong edge, 12 pt corners, a 44 pt titlebar
/// with 12 pt window controls and a 13 pt text/2 title.
enum WidgetTextResultChrome {
    static func styleWindow(container: NSView, root: NSView) {
        container.wantsLayer = true
        container.layer?.cornerRadius = PanelStyle.Radius.window
        container.layer?.masksToBounds = true
        container.superview?.wantsLayer = true
        container.superview?.layer?.cornerRadius = PanelStyle.Radius.window
        container.superview?.layer?.masksToBounds = true
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.ink1)
        root.layer?.cornerRadius = PanelStyle.Radius.window
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
        root.frame = container.bounds
        root.autoresizingMask = [.width, .height]
        container.addSubview(root)
    }

    static func styleTitlebar(_ titlebar: NSView, title: PanelCenteredTextView, text: String,
                              traffic: [NSView], divider: NSView, in root: NSView) {
        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = NSColor.clear.cgColor
        root.addSubview(titlebar)
        traffic.forEach(titlebar.addSubview)
        title.string = text
        title.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        title.textColor = InspectInk.text2
        title.alignment = .center
        titlebar.addSubview(title)
        // The Shizuka side windows have no titlebar rule.
        divider.isHidden = true
        titlebar.addSubview(divider)
    }

    static func layoutTitlebar(_ titlebar: NSView, title: PanelCenteredTextView, traffic: [NSView],
                               divider: NSView, width: CGFloat, height: CGFloat) {
        let barHeight = InspectLayout.titlebarHeight
        titlebar.frame = NSRect(x: 0, y: height - barHeight, width: width, height: barHeight)
        for (index, button) in traffic.enumerated() {
            button.frame = NSRect(x: 20 + CGFloat(index) * 20, y: barHeight - 16 - 12, width: 12, height: 12)
            button.layer?.cornerRadius = 6
        }
        title.frame = NSRect(x: 80, y: barHeight - 13 - 16, width: max(0, width - 160), height: 16)
        divider.frame = .zero
    }

    static func styleFooter(divider: NSView, count: NSTextField, in root: NSView) {
        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.line)
        root.addSubview(divider)
        count.font = PanelStyle.monoFont(ofSize: 11)
        count.textColor = InspectInk.text3
        count.alignment = .left
        root.addSubview(count)
    }

    /// Rule 16 pt above the 32 pt button row that sits 25 pt from the foot; the
    /// count is centred on that row. Returns the rule's y.
    @discardableResult
    static func layoutFooter(divider: NSView, count: NSTextField, inset: CGFloat, width: CGFloat) -> CGFloat {
        let ruleY: CGFloat = 25 + 32 + 16
        divider.frame = NSRect(x: inset, y: ruleY, width: max(0, width - inset * 2), height: 1)
        count.frame = NSRect(x: inset, y: 25 + (32 - 14) / 2, width: max(0, width / 2 - inset), height: 14)
        return ruleY
    }
}

final class WidgetTextInputPreviewView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
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
    }
}
