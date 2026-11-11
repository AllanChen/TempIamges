import AppKit

/// Slide-out panel showing OCR results, docked beside the main window.
/// Shares the Widget Result window chrome (custom titlebar, traffic lights,
/// Copy button, footer) so text results look the same however they were made.
final class OCRResultWindow: NSPanel {
    static let panelWidth: CGFloat = 360

    /// Called when the user closes the panel from its own chrome.
    var onDismiss: (() -> Void)?

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
    private let scroll = NSScrollView()
    private let textView = NSTextView()
    private let footerDivider = NSView()
    private let typeLabel = NSTextField(labelWithString: "Plain text".localized)
    private let characterCountLabel = NSTextField(labelWithString: "0 characters".localized)
    private var recognizedText = ""
    private var revertWorkItem: DispatchWorkItem?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 480),
                   styleMask: [.borderless, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 280, height: 240)
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

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
        titleLabel.string = "Recognize Text".localized
        titleLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.alignment = .center
        titlebar.addSubview(titleLabel)
        titlebarDivider.wantsLayer = true
        titlebarDivider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        titlebar.addSubview(titlebarDivider)
        copyButton.onPress = { [weak self] in self?.copyAll() }
        titlebar.addSubview(copyButton)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        PanelStyle.styleScrollers(in: scroll)
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        rootView.addSubview(scroll)

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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Same metrics as `WidgetTextResultWindow`, minus the input-image header.
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

        let footerY: CGFloat = 66
        footerDivider.frame = NSRect(x: 28, y: footerY, width: max(0, width - 56), height: 1)
        typeLabel.frame = NSRect(x: 28, y: 24, width: 120, height: 16)
        characterCountLabel.frame = NSRect(x: max(148, width - 178), y: 24,
                                           width: 150, height: 16)
        let resultTop = max(footerY + 14, height - titlebarHeight - 24)
        scroll.frame = NSRect(x: 28, y: footerY + 14, width: max(0, width - 56),
                              height: max(0, resultTop - footerY - 14))
        layoutText()
    }

    func showLoading() {
        recognizedText = ""
        copyButton.isEnabled = false
        copyButton.setCopied(false)
        setText("Recognizing…".localized, color: PanelStyle.textTertiary, characterCount: 0)
    }

    func showResult(_ text: String) {
        recognizedText = text
        copyButton.isEnabled = !text.isEmpty
        setText(text.isEmpty ? "No text found".localized : text,
                color: text.isEmpty ? PanelStyle.textTertiary : PanelStyle.textPrimary,
                characterCount: text.count)
        textView.scrollToBeginningOfDocument(nil)
    }

    func reloadLocalization() {
        titleLabel.string = "Recognize Text".localized
        typeLabel.stringValue = "Plain text".localized
        copyButton.setCopied(false)
        characterCountLabel.stringValue = String(format: "%d characters".localized,
                                                 recognizedText.count)
    }

    private func setText(_ text: String, color: NSColor, characterCount: Int) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 24
        paragraph.maximumLineHeight = 24
        paragraph.lineBreakMode = .byWordWrapping
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: text,
            attributes: [
                .font: PanelStyle.inspectFont(ofSize: 15),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]))
        characterCountLabel.stringValue = String(format: "%d characters".localized, characterCount)
        layoutText()
    }

    private func layoutText() {
        let width = max(0, scroll.contentSize.width)
        textView.textContainer?.containerSize = NSSize(
            width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: width,
                                height: max(1, scroll.contentSize.height))
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        textView.frame.size.height = max(scroll.contentSize.height, usedHeight)
    }

    func dismiss() {
        revertWorkItem?.cancel()
        parent?.removeChildWindow(self)
        orderOut(nil)
        onDismiss?()
    }

    override func close() {
        dismiss()
    }

    private func copyAll() {
        guard !recognizedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recognizedText, forType: .string)
        copyButton.setCopied(true)
        revertWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.copyButton.setCopied(false) }
        revertWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    @objc private func closeTrafficTapped() { dismiss() }
    @objc private func minimizeTrafficTapped() { miniaturize(nil) }
    @objc private func zoomTrafficTapped() { zoom(nil) }
}
