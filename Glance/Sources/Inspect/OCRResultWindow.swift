import AppKit

/// Slide-out panel showing OCR results, docked beside the main window.
/// Attached as a child window (same occlusion behavior as the info panel)
/// with frosted translucent chrome.
final class OCRResultWindow: NSPanel {
    private let scroll = NSScrollView()
    private let textView = NSTextView()
    private let copyButton = NSButton()
    private var recognizedText = ""
    private var revertWorkItem: DispatchWorkItem?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 240, height: 200)
        title = "Recognize Text".localized
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        guard let content = contentView else { return }
        let frost = PanelStyle.makeFrostedBase(cornerRadius: 0)
        frost.frame = content.bounds
        frost.autoresizingMask = [.width, .height]
        content.addSubview(frost)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = PanelStyle.body
        textView.textColor = PanelStyle.textPrimary
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        content.addSubview(scroll)

        copyButton.isBordered = false
        copyButton.wantsLayer = true
        copyButton.layer?.cornerRadius = 6
        copyButton.layer?.backgroundColor = PanelStyle.controlFill.cgColor
        copyButton.target = self
        copyButton.action = #selector(copyAll)
        updateCopyButtonTitle("Copy All".localized)
        content.addSubview(copyButton)
        layoutSubviews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func layoutSubviews() {
        guard let content = contentView else { return }
        let barHeight: CGFloat = 48
        scroll.frame = NSRect(x: 0, y: barHeight, width: content.bounds.width,
                              height: content.bounds.height - barHeight)
        scroll.autoresizingMask = [.width, .height]
        let buttonSize = NSSize(width: 120, height: 28)
        copyButton.frame = NSRect(x: (content.bounds.width - buttonSize.width) / 2,
                                  y: (barHeight - buttonSize.height) / 2,
                                  width: buttonSize.width, height: buttonSize.height)
        copyButton.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
    }

    func showLoading() {
        recognizedText = ""
        textView.string = "Recognizing…".localized
        copyButton.isEnabled = false
    }

    func showResult(_ text: String) {
        recognizedText = text
        textView.string = text.isEmpty ? "No text found".localized : text
        copyButton.isEnabled = !text.isEmpty
        textView.scrollToBeginningOfDocument(nil)
    }

    func reloadLocalization() {
        title = "Recognize Text".localized
        updateCopyButtonTitle("Copy All".localized)
    }

    private func updateCopyButtonTitle(_ title: String) {
        copyButton.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: PanelStyle.textPrimary, .font: PanelStyle.label])
    }

    @objc private func copyAll() {
        guard !recognizedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recognizedText, forType: .string)
        updateCopyButtonTitle("Copied ✓".localized)
        revertWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.updateCopyButtonTitle("Copy All".localized)
        }
        revertWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }
}
