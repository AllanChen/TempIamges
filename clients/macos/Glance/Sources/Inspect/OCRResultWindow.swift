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
        appearance = PanelStyle.windowAppearance
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Figma `22 · Recognize Text` chrome, shared with the Widget Result window.
        let windowContainer = NSView()
        contentView = windowContainer
        WidgetTextResultChrome.styleWindow(container: windowContainer, root: rootView)
        WidgetTextResultChrome.styleTitlebar(titlebar, title: titleLabel, text: "Recognize Text".localized,
                                             traffic: [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton],
                                             divider: titlebarDivider, in: rootView)
        copyButton.idleTitle = "Copy All".localized
        copyButton.onPress = { [weak self] in self?.copyAll() }
        rootView.addSubview(copyButton)

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

        WidgetTextResultChrome.styleFooter(divider: footerDivider, count: characterCountLabel, in: rootView)
        // Figma's footer carries only the count and Copy All.
        typeLabel.isHidden = true
        rootView.addSubview(typeLabel)

        rootView.onLayout = { [weak self] bounds in self?.layoutContent(in: bounds) }
        layoutContent(in: rootView.bounds)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Same chrome and footer as `WidgetTextResultWindow`; the text starts
    /// 32 pt below the titlebar (Figma text column at y 75).
    private func layoutContent(in bounds: NSRect) {
        let width = bounds.width
        let height = bounds.height
        WidgetTextResultChrome.layoutTitlebar(titlebar, title: titleLabel,
                                              traffic: [closeTrafficButton, minimizeTrafficButton, zoomTrafficButton],
                                              divider: titlebarDivider, width: width, height: height)
        let inset: CGFloat = 28
        let copyWidth = copyButton.preferredWidth
        copyButton.frame = NSRect(x: width - inset - copyWidth, y: 25, width: copyWidth, height: 32)
        let footerY = WidgetTextResultChrome.layoutFooter(divider: footerDivider, count: characterCountLabel,
                                                          inset: inset, width: width)
        typeLabel.frame = .zero
        let resultTop = max(footerY + 16, height - InspectLayout.titlebarHeight - 32)
        scroll.frame = NSRect(x: inset, y: footerY + 16, width: max(0, width - inset * 2),
                              height: max(0, resultTop - footerY - 16))
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
                color: text.isEmpty ? InspectInk.text3 : InspectInk.text2,
                characterCount: text.count)
        textView.scrollToBeginningOfDocument(nil)
    }

    func reloadLocalization() {
        titleLabel.string = "Recognize Text".localized
        typeLabel.stringValue = "Plain text".localized
        copyButton.idleTitle = "Copy All".localized
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
                .font: PanelStyle.inspectFont(ofSize: 14),
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
