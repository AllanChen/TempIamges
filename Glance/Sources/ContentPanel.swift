import AppKit
import WebKit

final class ContentPanel: NSWindow, NSTextFieldDelegate, WKNavigationDelegate {
    static let shared = ContentPanel()

    private let webView: WKWebView
    private let textView: NSTextView
    private let textScroll: NSScrollView
    private let imageView: ImageFillView
    private let toolbarBar = NSView()
    private let saveButton = NSButton()
    private let toggleButton = NSButton()
    private let gitDiffButton = NSButton()
    private let locateButton = NSButton()
    private let modifiedLabel = NSTextField(labelWithString: "")
    private let addressBar = NSTextField()

    private let webFindBar = NSView()
    private let webFindField = NSTextField()
    private let webFindCountLabel = NSTextField(labelWithString: "")
    private var webFindMatchCount = 0
    private var webFindCurrentIndex = -1

    private enum Kind { case webpage, markdown, text, pdf, image }
    private var kind: Kind = .webpage
    private var currentURL: URL?
    private var currentMediaInfo: MediaInfo?
    private var currentGitContext: GitDiffService.Context?
    private var gitDiffLookupID = UUID()
    private var gitDiffWindows: [GitDiffWindow] = []
    private var isEditing: Bool = false

    private let headerHeight: CGFloat = 56
    private let toolbarH: CGFloat = 44
    private let imageInfoBarH: CGFloat = 56

    private weak var loadingOverlay: NSView?
    private weak var loadingSpinner: NSProgressIndicator?

    private let imageInfoBar = NSView()
    private let imageInfoNameLabel = NSTextField(labelWithString: "")
    private let imageInfoMetaLabel = NSTextField(labelWithString: "")

    private(set) var hasBeenManuallyMoved: Bool = false
    private var escapeLocalMonitor: Any?
    private var escapeGlobalMonitor: Any?
    private var zoomMonitor: Any?

    private var currentZoomLevel: CGFloat = 1.0
    private let minZoomLevel: CGFloat = 0.25
    private let maxZoomLevel: CGFloat = 5.0
    private let zoomStep: CGFloat = 1.1

    private static func resolvedCG(_ color: NSColor) -> CGColor {
        var resolved: CGColor!
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    private init() {
        let config = WKWebViewConfiguration()
        let findScript = WKUserScript(
            source: ContentViewerWindow.findHelperJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(findScript)
        webView = WKWebView(frame: .zero, configuration: config)

        let tv = NSTextView(frame: .zero)
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        textView = tv

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.documentView = tv
        textScroll = scroll

        let iv = ImageFillView(frame: .zero)
        iv.isHidden = true
        imageView = iv

        let initialFrame = ScreenManager.shared.contentFrame(for: NSSize(width: 652.0, height: 962.0))
        super.init(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        webView.navigationDelegate = self
        webView.allowsMagnification = false

        title = "Glance".localized
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        buildLayout()
        showWebView()
        installEscapeKeyMonitors()
        installZoomMonitor()
        observeThemeChanges()
    }

    override var canBecomeKey: Bool { true }

    /// Move the window so it sits immediately to the right of the given
    /// preview frame. Called by PreviewPanel when it moves.
    func syncPosition(to previewFrame: NSRect) {
        guard !hasBeenManuallyMoved else { return }
        let contentSize = frame.size
        let originX = previewFrame.maxX
        let originY = previewFrame.maxY - contentSize.height
        let newFrame = NSRect(origin: CGPoint(x: originX, y: originY), size: contentSize)
        setFrame(newFrame, display: true)
    }

    /// Call when a fresh preview cycle starts so the window will resume
    /// following PreviewPanel even if it was manually dragged before.
    func resetFollowState() {
        hasBeenManuallyMoved = false
    }

    override func mouseDown(with event: NSEvent) {
        hasBeenManuallyMoved = true
        super.mouseDown(with: event)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        Logger.info("ContentPanel frame changed: x=\(frameRect.origin.x), y=\(frameRect.origin.y), width=\(frameRect.size.width), height=\(frameRect.size.height)")
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .magnify, isVisible {
            let newZoom = currentZoomLevel * (1 + event.magnification)
            currentZoomLevel = min(max(newZoom, minZoomLevel), maxZoomLevel)
            applyZoom()
            return
        }
        super.sendEvent(event)
    }

    override func magnify(with event: NSEvent) {
        let newZoom = currentZoomLevel * (1 + event.magnification)
        currentZoomLevel = min(max(newZoom, minZoomLevel), maxZoomLevel)
        applyZoom()
    }

    private func zoomIn() {
        guard currentZoomLevel < maxZoomLevel else { return }
        currentZoomLevel *= zoomStep
        applyZoom()
    }

    private func zoomOut() {
        guard currentZoomLevel > minZoomLevel else { return }
        currentZoomLevel /= zoomStep
        applyZoom()
    }

    private static func windowSize(for kind: Kind) -> NSSize {
        switch kind {
        case .webpage:
            return NSSize(width: 970.0, height: 990.0)
        case .text:
            return NSSize(width: 970.0, height: 990.0)
        case .markdown:
            return NSSize(width: 863.0, height: 919.0)
        case .pdf:
            return NSSize(width: 863.0, height: 919.0)
        case .image:
            return NSSize(width: 652.0, height: 962.0)
        }
    }

    private static func windowSize(for mediaKind: MediaInfo.Kind) -> NSSize {
        switch mediaKind {
        case .text:     return NSSize(width: 970.0, height: 990.0)
        case .markdown: return NSSize(width: 863.0, height: 919.0)
        case .pdf:      return NSSize(width: 863.0, height: 919.0)
        default:        return NSSize(width: 970.0, height: 990.0)
        }
    }

    private static func calculateImageWindowSize(imageSize: CGSize) -> NSSize {
        let maxWindowWidth: CGFloat = 1200
        let maxWindowHeight: CGFloat = 900
        let minWindowWidth: CGFloat = 300
        let minWindowHeight: CGFloat = 200
        let extraHeight: CGFloat = 44 + 56

        let screenSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let maxW = min(maxWindowWidth, screenSize.width * 0.8)
        let maxH = min(maxWindowHeight, screenSize.height * 0.8)

        var width = imageSize.width
        var height = imageSize.height + extraHeight

        if width > maxW {
            let scale = maxW / width
            width = maxW
            height = (imageSize.height * scale) + extraHeight
        }
        if height > maxH {
            let scale = (maxH - extraHeight) / imageSize.height
            height = maxH
            width = imageSize.width * scale
        }

        width = max(width, minWindowWidth)
        height = max(height, minWindowHeight)

        return NSSize(width: width, height: height)
    }

    private func resetZoom() {
        currentZoomLevel = 1.0
        applyZoom()
    }

    private func applyZoom() {
        switch kind {
        case .webpage, .markdown, .pdf:
            webView.magnification = currentZoomLevel
        case .text:
            let baseSize: CGFloat = 13
            let newSize = max(6, min(200, baseSize * currentZoomLevel))
            textView.font = NSFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
        case .image:
            if imageView.isHidden {
                webView.magnification = currentZoomLevel
            } else {
                imageView.setZoom(currentZoomLevel)
            }
        }
    }

    private func buildLayout() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 652.0, height: 962.0))
        root.wantsLayer = true
        root.layer?.backgroundColor = Self.resolvedCG(.windowBackgroundColor)

        let bodyFrame = NSRect(x: 0, y: 0, width: 652.0, height: 962.0)

        toolbarBar.frame = NSRect(x: 0, y: bodyFrame.height - toolbarH,
                                  width: bodyFrame.width, height: toolbarH)
        toolbarBar.autoresizingMask = [.width, .minYMargin]
        toolbarBar.wantsLayer = true
        toolbarBar.layer?.backgroundColor = Self.resolvedCG(.windowBackgroundColor)

        let toolbarSep = NSView(frame: NSRect(x: 0, y: 0, width: bodyFrame.width, height: 1))
        toolbarSep.wantsLayer = true
        toolbarSep.layer?.backgroundColor = Self.resolvedCG(.separatorColor)
        toolbarSep.autoresizingMask = [.width]
        toolbarBar.addSubview(toolbarSep)

        locateButton.bezelStyle = .rounded
        locateButton.image = NSImage(systemSymbolName: "folder.fill",
                                       accessibilityDescription: "Reveal in Finder".localized)
        locateButton.imagePosition = .imageOnly
        locateButton.target = self
        locateButton.action = #selector(locateTapped)
        locateButton.toolTip = "Reveal in Finder".localized
        locateButton.autoresizingMask = [.minXMargin]
        locateButton.isHidden = true
        toolbarBar.addSubview(locateButton)

        saveButton.bezelStyle = .rounded
        saveButton.title = "Save".localized
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.autoresizingMask = [.minXMargin]
        saveButton.isHidden = true
        toolbarBar.addSubview(saveButton)

        toggleButton.bezelStyle = .rounded
        toggleButton.title = "Edit".localized
        toggleButton.target = self
        toggleButton.action = #selector(toggleEditTapped)
        toggleButton.autoresizingMask = [.minXMargin]
        toggleButton.isHidden = true
        toolbarBar.addSubview(toggleButton)

        gitDiffButton.bezelStyle = .rounded
        gitDiffButton.title = "Diff".localized
        gitDiffButton.target = self
        gitDiffButton.action = #selector(gitDiffTapped)
        gitDiffButton.toolTip = "Compare with Git".localized
        gitDiffButton.autoresizingMask = [.minXMargin]
        gitDiffButton.isHidden = true
        toolbarBar.addSubview(gitDiffButton)

        modifiedLabel.font = NSFont.systemFont(ofSize: 11)
        modifiedLabel.textColor = .tertiaryLabelColor
        modifiedLabel.alignment = .left
        modifiedLabel.lineBreakMode = .byTruncatingMiddle
        modifiedLabel.maximumNumberOfLines = 1
        modifiedLabel.autoresizingMask = [.width]
        toolbarBar.addSubview(modifiedLabel)

        addressBar.font = NSFont.systemFont(ofSize: 12)
        addressBar.alignment = .center
        addressBar.isEditable = false
        addressBar.isSelectable = true
        addressBar.isBordered = true
        addressBar.backgroundColor = NSColor.textBackgroundColor
        addressBar.textColor = .secondaryLabelColor
        addressBar.frame = NSRect(x: 80, y: 9, width: bodyFrame.width - 160, height: 26)
        addressBar.autoresizingMask = [.width]
        addressBar.isHidden = true
        toolbarBar.addSubview(addressBar)

        root.addSubview(toolbarBar)
        layoutToolbarButtons()

        let contentFrame = NSRect(x: 0, y: 0, width: bodyFrame.width,
                                   height: bodyFrame.height - toolbarH)
        webView.frame = contentFrame
        webView.autoresizingMask = [.width, .height]
        root.addSubview(webView)

        imageView.frame = contentFrame
        imageView.autoresizingMask = [.width, .height]
        root.addSubview(imageView)

        textScroll.frame = contentFrame
        textScroll.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(
            width: contentFrame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        root.addSubview(textScroll)

        let findBarH: CGFloat = 36
        webFindBar.frame = NSRect(
            x: 0, y: contentFrame.maxY - findBarH,
            width: contentFrame.width, height: findBarH
        )
        webFindBar.autoresizingMask = [.width, .minYMargin]
        webFindBar.wantsLayer = true
        webFindBar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        webFindBar.isHidden = true

        let findSep = NSView(frame: NSRect(x: 0, y: 0, width: contentFrame.width, height: 1))
        findSep.wantsLayer = true
        findSep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        findSep.autoresizingMask = [.width]
        webFindBar.addSubview(findSep)

        webFindField.placeholderString = "Find in page".localized
        webFindField.frame = NSRect(x: 12, y: 6, width: 240, height: 24)
        webFindField.delegate = self
        webFindBar.addSubview(webFindField)

        webFindCountLabel.font = NSFont.systemFont(ofSize: 11)
        webFindCountLabel.textColor = .secondaryLabelColor
        webFindCountLabel.frame = NSRect(x: 260, y: 9, width: 80, height: 18)
        webFindBar.addSubview(webFindCountLabel)

        let prevBtn = NSButton(title: "‹", target: self, action: #selector(webFindPrev))
        prevBtn.bezelStyle = .rounded
        prevBtn.frame = NSRect(x: contentFrame.width - 140, y: 6, width: 32, height: 24)
        prevBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(prevBtn)

        let nextBtn = NSButton(title: "›", target: self, action: #selector(webFindNext))
        nextBtn.bezelStyle = .rounded
        nextBtn.frame = NSRect(x: contentFrame.width - 102, y: 6, width: 32, height: 24)
        nextBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(nextBtn)

        let doneBtn = NSButton(title: "Done".localized, target: self, action: #selector(hideWebFindBar))
        doneBtn.bezelStyle = .rounded
        doneBtn.frame = NSRect(x: contentFrame.width - 60, y: 6, width: 50, height: 24)
        doneBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(doneBtn)

        root.addSubview(webFindBar)

        let overlay = NSView(frame: contentFrame)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = Self.resolvedCG(.windowBackgroundColor)
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true

        let spinnerContainer = NSView(frame: NSRect(
            x: (contentFrame.width - 40) / 2,
            y: (contentFrame.height - 40) / 2,
            width: 40, height: 40
        ))
        spinnerContainer.wantsLayer = true
        spinnerContainer.layer?.cornerRadius = 10
        spinnerContainer.layer?.backgroundColor = Self.resolvedCG(.controlBackgroundColor)
        spinnerContainer.autoresizingMask = [.minXMargin, .minYMargin, .maxXMargin, .maxYMargin]
        overlay.addSubview(spinnerContainer)

        let spinner = NSProgressIndicator(frame: NSRect(
            x: 10, y: 10, width: 20, height: 20
        ))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.usesThreadedAnimation = true
        spinner.appearance = NSAppearance(named: .vibrantDark)
        spinner.startAnimation(nil)
        spinnerContainer.addSubview(spinner)

        let loadingLbl = NSTextField(labelWithString: "Loading…".localized)
        loadingLbl.textColor = .secondaryLabelColor
        loadingLbl.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        loadingLbl.alignment = .center
        loadingLbl.frame = NSRect(x: 0, y: spinnerContainer.frame.minY - 32,
                                   width: contentFrame.width, height: 18)
        loadingLbl.autoresizingMask = [.width, .minXMargin, .maxXMargin]
        overlay.addSubview(loadingLbl)

        root.addSubview(overlay)
        loadingOverlay = overlay
        loadingSpinner = spinner

        imageInfoBar.frame = NSRect(x: 0, y: 0,
                                     width: bodyFrame.width, height: imageInfoBarH)
        imageInfoBar.autoresizingMask = [.width, .maxYMargin]
        imageInfoBar.wantsLayer = true
        imageInfoBar.layer?.backgroundColor = Self.resolvedCG(.underPageBackgroundColor)
        imageInfoBar.isHidden = true

        imageInfoNameLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        imageInfoNameLabel.textColor = .labelColor
        imageInfoNameLabel.lineBreakMode = .byTruncatingMiddle
        imageInfoNameLabel.maximumNumberOfLines = 1
        imageInfoNameLabel.frame = NSRect(x: 20, y: 30,
                                           width: bodyFrame.width - 40, height: 20)
        imageInfoNameLabel.autoresizingMask = [.width]
        imageInfoBar.addSubview(imageInfoNameLabel)

        imageInfoMetaLabel.font = NSFont.systemFont(ofSize: 11)
        imageInfoMetaLabel.textColor = .secondaryLabelColor
        imageInfoMetaLabel.lineBreakMode = .byTruncatingTail
        imageInfoMetaLabel.maximumNumberOfLines = 1
        imageInfoMetaLabel.frame = NSRect(x: 20, y: 9,
                                           width: bodyFrame.width - 40, height: 14)
        imageInfoMetaLabel.autoresizingMask = [.width]
        imageInfoBar.addSubview(imageInfoMetaLabel)

        root.addSubview(imageInfoBar)

        contentView = root
    }

    /// Re-pack the right-anchored toolbar buttons so hidden ones collapse and
    /// visible ones stay grouped, then resize modifiedLabel to fill the
    /// remaining space with a consistent gap before the button group.
    private func layoutToolbarButtons() {
        let gap: CGFloat = 10
        let btnW: CGFloat = 72
        let btnH: CGFloat = 26
        let btnY: CGFloat = 9
        let rightMargin: CGFloat = 20
        let leftMargin: CGFloat = 20
        let labelButtonGap: CGFloat = 24
        let bodyWidth = toolbarBar.bounds.width

        let buttons: [NSButton] = [locateButton, saveButton, toggleButton, gitDiffButton]
        var currentRight = bodyWidth - rightMargin
        var leftmostVisibleX: CGFloat?
        for button in buttons {
            guard !button.isHidden else { continue }
            let x = currentRight - btnW
            button.frame = NSRect(x: x, y: btnY, width: btnW, height: btnH)
            leftmostVisibleX = x
            currentRight = x - gap
        }

        if !modifiedLabel.isHidden {
            let rightEdge = leftmostVisibleX.map { $0 - labelButtonGap } ?? (bodyWidth - rightMargin)
            modifiedLabel.frame = NSRect(
                x: leftMargin,
                y: btnY,
                width: max(100, rightEdge - leftMargin),
                height: btnH
            )
        }
    }

    func dismiss() {
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
        NotificationCenter.default.post(name: .init("ContentPanelDidClose"), object: self)
    }

    private func installEscapeKeyMonitors() {
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.shouldCloseForEscape(event) else { return event }
            self.cancelOperation(nil)
            return nil
        }

        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.shouldCloseForEscape(event) else { return }
            DispatchQueue.main.async {
                self.cancelOperation(nil)
            }
        }
    }

    private func shouldCloseForEscape(_ event: NSEvent) -> Bool {
        isVisible && event.keyCode == 53
    }

    private func installZoomMonitor() {
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, event.window === self, self.isVisible else { return event }
            if event.modifierFlags.contains(.command) {
                let delta = event.scrollingDeltaY
                if delta > 0 {
                    self.zoomIn()
                } else if delta < 0 {
                    self.zoomOut()
                }
                return nil
            }
            return event
        }
    }

    func load(info: MediaInfo) {
        currentMediaInfo = info
        resetGitDiffAvailability()
        showLoading()

        if info.kind != .image && info.kind != .video {
            let fixedFrame = ScreenManager.shared.contentFrame(for: Self.windowSize(for: info.kind))
            hasBeenManuallyMoved = true
            setFrame(fixedFrame, display: true)
        }

        switch info.kind {
        case .markdown:
            currentURL = info.url
            kind = .markdown
            isEditing = false
            showToolbar()
            imageInfoBar.isHidden = true
            toggleButton.isHidden = false
            toggleButton.title = "Edit".localized
            saveButton.isHidden = true
            locateButton.isHidden = !info.url.isFileURL
            updateToolbarPath(for: info.url)
            refreshGitDiffAvailability(for: info.url)
            renderMarkdownView(url: info.url)
        case .text:
            currentURL = info.url
            kind = .text
            isEditing = false
            showToolbar()
            imageInfoBar.isHidden = true
            toggleButton.isHidden = false
            toggleButton.title = "Edit".localized
            saveButton.isHidden = true
            locateButton.isHidden = !info.url.isFileURL
            updateToolbarPath(for: info.url)
            refreshGitDiffAvailability(for: info.url)
            renderHighlightedCode(url: info.url)
        case .pdf:
            currentURL = info.url
            kind = .pdf
            showToolbar()
            imageInfoBar.isHidden = true
            toggleButton.isHidden = true
            saveButton.isHidden = true
            locateButton.isHidden = !info.url.isFileURL
            updateToolbarPath(for: info.url)
            if info.url.isFileURL {
                webView.loadFileURL(info.url, allowingReadAccessTo: info.url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: info.url))
            }
            showWebView()
        case .image:
            currentURL = info.url
            kind = .image
            resetZoom()
            showToolbar()
            toggleButton.isHidden = true
            saveButton.isHidden = true
            locateButton.isHidden = !info.url.isFileURL
            updateToolbarPath(for: info.url)
            updateImageInfoBar(with: info)
            imageInfoBar.isHidden = false
            if let image = NSImage(contentsOf: info.url) {
                imageView.image = image
                showImageView()
                let imageSize = image.size
                let windowSize = Self.calculateImageWindowSize(imageSize: imageSize)
                let imageFrame = ScreenManager.shared.contentFrame(for: windowSize)
                setFrame(imageFrame, display: true)
            } else {
                let html = """
                <html><head><style>
                body { margin: 0; display: flex; align-items: center; justify-content: center;
                       background: #0a0a0a; height: 100vh; overflow: hidden; }
                img { max-width: 100%; max-height: 100%; object-fit: contain; }
                </style></head><body><img src="\(info.url.absoluteString)"></body></html>
                """
                webView.loadHTMLString(html, baseURL: nil)
                showWebView()
            }
            hideLoading()
        default:
            currentURL = info.url
            kind = .webpage
            showAddressBar(for: info.url)
            imageInfoBar.isHidden = true
            updateToolbarPath(for: info.url)
            webView.load(URLRequest(url: info.url))
            showWebView()
        }
        layoutToolbarButtons()
    }

    private func showLoading() {
        loadingOverlay?.isHidden = false
    }

    private func hideLoading() {
        loadingOverlay?.isHidden = true
    }

    private func renderMarkdownView(url: URL) {
        Task.detached { [weak self] in
            let raw = await ContentViewerWindow.fetchTextContent(from: url)
            let html = ContentViewerWindow.wrapMarkdownInHTML(raw)
            await MainActor.run {
                self?.webView.loadHTMLString(html, baseURL: url)
                self?.showWebView()
                self?.hideLoading()
            }
        }
    }

    private func renderHighlightedCode(url: URL) {
        Task.detached { [weak self] in
            let raw = await ContentViewerWindow.fetchTextContent(from: url)
            let lang = ContentViewerWindow.languageIdentifier(for: url)
            let html = ContentViewerWindow.wrapCodeInHTML(raw, language: lang)
            await MainActor.run {
                self?.webView.loadHTMLString(html, baseURL: url)
                self?.showWebView()
                self?.hideLoading()
            }
        }
    }

    private func loadEditableText(url: URL, prettyPrint: Bool) {
        Task.detached { [weak self] in
            let raw = await ContentViewerWindow.fetchTextContent(from: url)
            let body: String
            if prettyPrint {
                let ext = url.pathExtension.lowercased()
                switch ext {
                case "json": body = await ContentViewerWindow.prettyPrintJSON(raw) ?? raw
                case "xml":  body = await ContentViewerWindow.prettyPrintXML(raw)  ?? raw
                default:     body = raw
                }
            } else {
                body = raw
            }
            await MainActor.run {
                self?.textView.string = body
                self?.showTextView()
                self?.hideLoading()
            }
        }
    }

    private func showWebView() {
        webView.isHidden = false
        textScroll.isHidden = true
        imageView.isHidden = true
    }

    private func showTextView() {
        webView.isHidden = true
        textScroll.isHidden = false
        imageView.isHidden = true
        makeFirstResponder(textView)
    }

    private func showImageView() {
        webView.isHidden = true
        textScroll.isHidden = true
        imageView.isHidden = false
    }

    private func showAddressBar(for url: URL) {
        toggleButton.isHidden = true
        saveButton.isHidden = true
        gitDiffButton.isHidden = true
        locateButton.isHidden = !url.isFileURL
        modifiedLabel.isHidden = true
        addressBar.isHidden = false
        addressBar.stringValue = url.absoluteString
        addressBar.isEditable = true
        addressBar.target = self
        addressBar.action = #selector(addressBarSubmitted)
        layoutToolbarButtons()
    }

    private func showToolbar() {
        addressBar.isHidden = true
        modifiedLabel.isHidden = false
        layoutToolbarButtons()
    }

    @objc private func toggleEditTapped() {
        guard let url = currentURL else { return }
        guard kind == .markdown || kind == .text else { return }
        isEditing.toggle()
        if isEditing {
            toggleButton.title = "View".localized
            saveButton.isHidden = !url.isFileURL
            loadEditableText(url: url, prettyPrint: false)
        } else {
            toggleButton.title = "Edit".localized
            saveButton.isHidden = true
            if kind == .markdown {
                renderMarkdownView(url: url)
            } else {
                renderHighlightedCode(url: url)
            }
        }
        layoutToolbarButtons()
    }

    @objc private func gitDiffTapped() {
        guard let context = currentGitContext else { return }
        gitDiffButton.isEnabled = false
        gitDiffButton.title = "..."

        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = GitDiffService.makeSnapshot(for: context)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.gitDiffButton.isEnabled = true
                self.gitDiffButton.title = "Diff".localized

                guard let snapshot = snapshot else {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't load Git diff".localized
                    alert.informativeText = context.fileURL.path
                    alert.beginSheetModal(for: self, completionHandler: nil)
                    return
                }

                let window = GitDiffWindow(snapshot: snapshot)
                self.gitDiffWindows.append(window)
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self = self, let window = window else { return }
                    self.gitDiffWindows.removeAll { $0 === window }
                }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func locateTapped() {
        guard let url = currentURL, url.isFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func addressBarSubmitted() {
        let text = addressBar.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let urlString: String
        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") {
            urlString = text
        } else {
            urlString = "https://\(text)"
        }
        guard let url = URL(string: urlString) else { return }
        currentURL = url
        webView.load(URLRequest(url: url))
    }

    @objc private func saveTapped() {
        guard let url = currentURL, url.isFileURL else { return }
        let body = textView.string
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            saveButton.title = "Saved ✓".localized
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.saveButton.title = "Save".localized
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = String(format: "Couldn't save %@".localized, url.lastPathComponent)
            alert.beginSheetModal(for: self, completionHandler: nil)
        }
    }

    private func updateToolbarPath(for url: URL?) {
        guard let url = url else {
            modifiedLabel.stringValue = ""
            modifiedLabel.toolTip = nil
            return
        }
        let label = url.isFileURL ? url.path : url.absoluteString
        modifiedLabel.stringValue = label
        modifiedLabel.toolTip = label
    }

    private func resetGitDiffAvailability() {
        gitDiffLookupID = UUID()
        currentGitContext = nil
        gitDiffButton.isHidden = true
        gitDiffButton.isEnabled = true
        gitDiffButton.title = "Diff".localized
        layoutToolbarButtons()
    }

    private func refreshGitDiffAvailability(for url: URL) {
        guard url.isFileURL else { return }
        let lookupID = UUID()
        gitDiffLookupID = lookupID
        DispatchQueue.global(qos: .userInitiated).async {
            let context = GitDiffService.context(for: url)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.gitDiffLookupID == lookupID else { return }
                self.currentGitContext = context
                self.gitDiffButton.isHidden = context == nil
                self.layoutToolbarButtons()
            }
        }
    }

    private func updateImageInfoBar(with info: MediaInfo) {
        imageInfoNameLabel.stringValue = info.filename

        var parts: [String] = []
        if !info.formatName.isEmpty {
            parts.append(info.formatName)
        }
        if let bytes = info.fileSize {
            let f = ByteCountFormatter()
            f.countStyle = .file
            parts.append(f.string(fromByteCount: bytes))
        }
        if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
            parts.append("\(Int(dim.width)) × \(Int(dim.height))")
        }
        imageInfoMetaLabel.stringValue = parts.joined(separator: " · ")
    }

    // MARK: - Find

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers ?? ""
            if key == "f" {
                if !webView.isHidden {
                    showWebFindBar()
                    return true
                }
                if !textScroll.isHidden {
                    invokeTextFinder(.showFindInterface)
                    return true
                }
            }
            if key == "g" {
                let isShift = event.modifierFlags.contains(.shift)
                if !webFindBar.isHidden {
                    if isShift { webFindPrev(nil) } else { webFindNext(nil) }
                    return true
                }
                if !textScroll.isHidden {
                    invokeTextFinder(isShift ? .previousMatch : .nextMatch)
                    return true
                }
            }
            if key == "0" {
                resetZoom()
                return true
            }
            if key == "+" || key == "=" {
                zoomIn()
                return true
            }
            if key == "-" {
                zoomOut()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func invokeTextFinder(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }

    private func showWebFindBar() {
        webFindBar.isHidden = false
        webFindBar.frame.origin.y = (contentView?.bounds.height ?? 0) - headerHeight - toolbarH - webFindBar.bounds.height
        makeFirstResponder(webFindField)
        webFindField.selectText(nil)
        if !webFindField.stringValue.isEmpty {
            runWebFind(query: webFindField.stringValue)
        }
    }

    @objc private func hideWebFindBar() {
        webFindBar.isHidden = true
        webView.evaluateJavaScript("window.__tdfind && window.__tdfind.clear()", completionHandler: nil)
        webFindMatchCount = 0
        webFindCurrentIndex = -1
        updateWebFindCountLabel()
        makeFirstResponder(webView)
    }

    private func runWebFind(query: String) {
        let jsQuery = ContentViewerWindow.jsStringLiteral(query)
        let js = "window.__tdfind && window.__tdfind.highlight(\(jsQuery))"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            let count = (result as? Int) ?? 0
            self.webFindMatchCount = count
            self.webFindCurrentIndex = count > 0 ? 0 : -1
            self.updateWebFindCountLabel()
        }
    }

    @objc private func webFindNext(_ sender: Any?) {
        webView.evaluateJavaScript("window.__tdfind && window.__tdfind.next()") { [weak self] r, _ in
            guard let self = self, let idx = r as? Int, idx >= 0 else { return }
            self.webFindCurrentIndex = idx
            self.updateWebFindCountLabel()
        }
    }

    @objc private func webFindPrev(_ sender: Any?) {
        webView.evaluateJavaScript("window.__tdfind && window.__tdfind.prev()") { [weak self] r, _ in
            guard let self = self, let idx = r as? Int, idx >= 0 else { return }
            self.webFindCurrentIndex = idx
            self.updateWebFindCountLabel()
        }
    }

    private func updateWebFindCountLabel() {
        if webFindMatchCount == 0 {
            webFindCountLabel.stringValue = webFindField.stringValue.isEmpty ? "" : "0 results".localized
        } else {
            webFindCountLabel.stringValue = "\(webFindCurrentIndex + 1) / \(webFindMatchCount)"
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField, tf === webFindField else { return }
        runWebFind(query: tf.stringValue)
    }

    func control(_ control: NSControl, textView fieldEditor: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard control === webFindField else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hideWebFindBar()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            webFindNext(nil)
            return true
        }
        return false
    }

    private func observeThemeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateAppearance),
            name: .preferencesDidChange,
            object: nil
        )
    }

    @objc private func updateAppearance() {
        guard let root = contentView else { return }
        root.layer?.backgroundColor = Self.resolvedCG(.windowBackgroundColor)
        toolbarBar.layer?.backgroundColor = Self.resolvedCG(.windowBackgroundColor)
        if let toolbarSep = toolbarBar.subviews.first(where: { $0.frame.height == 1 && $0 !== webFindBar }) {
            toolbarSep.layer?.backgroundColor = Self.resolvedCG(.separatorColor)
        }
        webFindBar.layer?.backgroundColor = Self.resolvedCG(.controlBackgroundColor)
        if let findSep = webFindBar.subviews.first(where: { $0.frame.height == 1 }) {
            findSep.layer?.backgroundColor = Self.resolvedCG(.separatorColor)
        }
        if let overlay = loadingOverlay {
            overlay.layer?.backgroundColor = Self.resolvedCG(.windowBackgroundColor)
        }
        imageInfoBar.layer?.backgroundColor = Self.resolvedCG(.underPageBackgroundColor)
    }


}

extension ContentPanel {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        hideLoading()
    }
}

private final class ImageFillView: NSView {
    var image: NSImage? {
        didSet {
            imageLayer.contents = image
        }
    }

    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.04, alpha: 1).cgColor
        layer?.masksToBounds = true

        imageLayer.contentsGravity = .resizeAspect
        imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        imageLayer.bounds = bounds
    }

    func setZoom(_ zoom: CGFloat) {
        imageLayer.transform = CATransform3DMakeScale(zoom, zoom, 1)
    }
}

private enum GitDiffService {
    struct Context {
        let rootURL: URL
        let fileURL: URL
        let relativePath: String
        let statusLine: String
        let history: [String]
        let isTracked: Bool
    }

    struct Snapshot {
        let fileURL: URL
        let rootURL: URL
        let relativePath: String
        let beforeTitle: String
        let afterTitle: String
        let beforeText: String
        let afterText: String
        let summary: String
    }

    private struct CommandResult {
        let status: Int32
        let output: String
        let error: String
    }

    static func context(for fileURL: URL) -> Context? {
        guard fileURL.isFileURL else { return nil }
        let fileURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let directoryURL = fileURL.deletingLastPathComponent()

        guard let rootResult = runGit(["rev-parse", "--show-toplevel"], cwd: directoryURL),
              rootResult.status == 0 else { return nil }
        let rootPath = rootResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rootPath.isEmpty else { return nil }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard let relativePath = relativePath(from: rootURL, to: fileURL) else { return nil }

        let status = runGit(["status", "--porcelain", "--", relativePath], cwd: rootURL)?
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let history = runGit(["log", "--follow", "--format=%H", "-n", "2", "--", relativePath], cwd: rootURL)?
            .output
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty } ?? []
        let tracked = runGit(["ls-files", "--error-unmatch", "--", relativePath], cwd: rootURL)?
            .status == 0

        guard tracked || !status.isEmpty || !history.isEmpty else { return nil }
        return Context(rootURL: rootURL,
                       fileURL: fileURL,
                       relativePath: relativePath,
                       statusLine: status,
                       history: history,
                       isTracked: tracked)
    }

    static func makeSnapshot(for context: Context) -> Snapshot? {
        let currentText = readTextFile(context.fileURL) ?? ""
        let hasWorkingChange = !context.statusLine.isEmpty

        if hasWorkingChange {
            let beforeText: String
            let beforeTitle: String
            if context.isTracked || !context.history.isEmpty {
                beforeText = showFile("HEAD", relativePath: context.relativePath, rootURL: context.rootURL) ?? ""
                beforeTitle = "Before - HEAD".localized
            } else {
                beforeText = ""
                beforeTitle = "Before - New file".localized
            }
            return Snapshot(fileURL: context.fileURL,
                            rootURL: context.rootURL,
                            relativePath: context.relativePath,
                            beforeTitle: beforeTitle,
                            afterTitle: "After - Working Tree".localized,
                            beforeText: beforeText,
                            afterText: currentText,
                            summary: context.statusLine)
        }

        if context.history.count >= 2 {
            let afterRev = context.history[0]
            let beforeRev = context.history[1]
            let beforeText = showFile(beforeRev, relativePath: context.relativePath, rootURL: context.rootURL) ?? ""
            let afterText = showFile(afterRev, relativePath: context.relativePath, rootURL: context.rootURL) ?? currentText
            return Snapshot(fileURL: context.fileURL,
                            rootURL: context.rootURL,
                            relativePath: context.relativePath,
                            beforeTitle: "Before - \(shortHash(beforeRev))",
                            afterTitle: "After - \(shortHash(afterRev))",
                            beforeText: beforeText,
                            afterText: afterText,
                            summary: "Last committed change".localized)
        }

        let beforeText = showFile("HEAD", relativePath: context.relativePath, rootURL: context.rootURL) ?? currentText
        return Snapshot(fileURL: context.fileURL,
                        rootURL: context.rootURL,
                        relativePath: context.relativePath,
                        beforeTitle: "Before - HEAD".localized,
                        afterTitle: "After - Working Tree".localized,
                        beforeText: beforeText,
                        afterText: currentText,
                        summary: "No working-tree changes".localized)
    }

    private static func showFile(_ revision: String, relativePath: String, rootURL: URL) -> String? {
        let spec = "\(revision):\(relativePath)"
        guard let result = runGit(["show", "--textconv", spec], cwd: rootURL),
              result.status == 0 else { return nil }
        return result.output
    }

    private static func readTextFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    private static func relativePath(from rootURL: URL, to fileURL: URL) -> String? {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath == rootPath { return "" }
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func shortHash(_ hash: String) -> String {
        String(hash.prefix(7))
    }

    private static func runGit(_ arguments: [String], cwd: URL, timeout: TimeInterval = 5.0) -> CommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = cwd

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment

        do {
            try process.run()
        } catch {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var outputData: Data?
        var errorData: Data?
        var exitStatus: Int32 = -1

        DispatchQueue.global(qos: .userInitiated).async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            exitStatus = process.terminationStatus
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            Logger.info("GitDiffService: git timed out after \(timeout)s: \(arguments.joined(separator: " "))")
            process.terminate()
            return nil
        }

        guard let outData = outputData, let errData = errorData else {
            return nil
        }

        return CommandResult(
            status: exitStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: String(decoding: errData, as: UTF8.self)
        )
    }
}

private final class GitDiffWindow: NSWindow {
    private let leftScroll: NSScrollView
    private let rightScroll: NSScrollView
    private var isSyncingScroll = false

    init(snapshot: GitDiffService.Snapshot) {
        let diff = Self.makeSideBySideDiff(before: snapshot.beforeText, after: snapshot.afterText)
        leftScroll = Self.makeCodeScroll(attributedText: diff.left)
        rightScroll = Self.makeCodeScroll(attributedText: diff.right)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        title = "Git Diff - \(snapshot.fileURL.lastPathComponent)"
        buildLayout(snapshot: snapshot)
        center()
        installScrollSync()
    }

    private func buildLayout(snapshot: GitDiffService.Snapshot) {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView = root

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        root.addSubview(header)

        let pathLabel = NSTextField(labelWithString: snapshot.fileURL.path)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.isSelectable = true
        header.addSubview(pathLabel)

        let summaryLabel = NSTextField(labelWithString: "\(snapshot.summary)  •  \(snapshot.relativePath)")
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = NSFont.systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingMiddle
        summaryLabel.maximumNumberOfLines = 1
        header.addSubview(summaryLabel)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 1
        root.addSubview(stack)

        stack.addArrangedSubview(makeColumn(title: snapshot.beforeTitle, scrollView: leftScroll))
        stack.addArrangedSubview(makeColumn(title: snapshot.afterTitle, scrollView: rightScroll))

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 56),

            pathLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            pathLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            pathLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 9),
            pathLabel.heightAnchor.constraint(equalToConstant: 18),

            summaryLabel.leadingAnchor.constraint(equalTo: pathLabel.leadingAnchor),
            summaryLabel.trailingAnchor.constraint(equalTo: pathLabel.trailingAnchor),
            summaryLabel.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 2),
            summaryLabel.heightAnchor.constraint(equalToConstant: 16),

            stack.topAnchor.constraint(equalTo: header.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func makeColumn(title: String, scrollView: NSScrollView) -> NSView {
        let column = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.wantsLayer = true
        titleLabel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        column.addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: column.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: column.bottomAnchor)
        ])

        return column
    }

    private static func makeCodeScroll(attributedText: NSAttributedString) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textStorage?.setAttributedString(attributedText)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    private enum DiffKind {
        case unchanged
        case deleted
        case inserted
        case placeholder
    }

    private enum DiffOperation {
        case equal(String)
        case delete(String)
        case insert(String)
    }

    private struct DiffCell {
        let number: Int?
        let text: String
        let kind: DiffKind
    }

    private struct DiffRow {
        let left: DiffCell
        let right: DiffCell
    }

    private struct RenderedDiff {
        let left: NSAttributedString
        let right: NSAttributedString
    }

    private static func makeSideBySideDiff(before: String, after: String) -> RenderedDiff {
        let beforeLines = splitLines(before)
        let afterLines = splitLines(after)
        let rows = diffRows(before: beforeLines, after: afterLines)
        return RenderedDiff(
            left: attributedText(for: rows.map(\.left)),
            right: attributedText(for: rows.map(\.right))
        )
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    private static func diffRows(before: [String], after: [String]) -> [DiffRow] {
        let maxCells = 4_000_000
        if !before.isEmpty, after.count > maxCells / before.count {
            return fallbackDiffRows(before: before, after: after)
        }

        let operations = diffOperations(before: before, after: after)
        var rows: [DiffRow] = []
        var i = 0
        var leftLine = 1
        var rightLine = 1

        while i < operations.count {
            switch operations[i] {
            case .equal(let line):
                rows.append(DiffRow(
                    left: DiffCell(number: leftLine, text: line, kind: .unchanged),
                    right: DiffCell(number: rightLine, text: line, kind: .unchanged)
                ))
                leftLine += 1
                rightLine += 1
                i += 1

            case .delete, .insert:
                var deleted: [String] = []
                var inserted: [String] = []
                while i < operations.count {
                    if case .equal = operations[i] { break }
                    switch operations[i] {
                    case .delete(let line):
                        deleted.append(line)
                        i += 1
                    case .insert(let line):
                        inserted.append(line)
                        i += 1
                    case .equal:
                        break
                    }
                }

                let count = max(deleted.count, inserted.count)
                for index in 0..<count {
                    let left: DiffCell
                    if index < deleted.count {
                        left = DiffCell(number: leftLine, text: deleted[index], kind: .deleted)
                        leftLine += 1
                    } else {
                        left = DiffCell(number: nil, text: "", kind: .placeholder)
                    }

                    let right: DiffCell
                    if index < inserted.count {
                        right = DiffCell(number: rightLine, text: inserted[index], kind: .inserted)
                        rightLine += 1
                    } else {
                        right = DiffCell(number: nil, text: "", kind: .placeholder)
                    }

                    rows.append(DiffRow(left: left, right: right))
                }
            }
        }

        if rows.isEmpty {
            rows.append(DiffRow(
                left: DiffCell(number: nil, text: "", kind: .placeholder),
                right: DiffCell(number: nil, text: "", kind: .placeholder)
            ))
        }
        return rows
    }

    private static func diffOperations(before: [String], after: [String]) -> [DiffOperation] {
        let columns = after.count + 1
        var table = Array(repeating: 0, count: (before.count + 1) * columns)

        func index(_ i: Int, _ j: Int) -> Int {
            i * columns + j
        }

        if !before.isEmpty, !after.isEmpty {
            for i in stride(from: before.count - 1, through: 0, by: -1) {
                for j in stride(from: after.count - 1, through: 0, by: -1) {
                    if before[i] == after[j] {
                        table[index(i, j)] = table[index(i + 1, j + 1)] + 1
                    } else {
                        table[index(i, j)] = max(table[index(i + 1, j)], table[index(i, j + 1)])
                    }
                }
            }
        }

        var operations: [DiffOperation] = []
        var i = 0
        var j = 0
        while i < before.count || j < after.count {
            if i < before.count, j < after.count, before[i] == after[j] {
                operations.append(.equal(before[i]))
                i += 1
                j += 1
            } else if j < after.count,
                      (i == before.count || table[index(i, j + 1)] >= table[index(i + 1, j)]) {
                operations.append(.insert(after[j]))
                j += 1
            } else if i < before.count {
                operations.append(.delete(before[i]))
                i += 1
            }
        }
        return operations
    }

    private static func fallbackDiffRows(before: [String], after: [String]) -> [DiffRow] {
        var rows: [DiffRow] = []
        let count = max(before.count, after.count)
        for index in 0..<count {
            if index < before.count, index < after.count, before[index] == after[index] {
                rows.append(DiffRow(
                    left: DiffCell(number: index + 1, text: before[index], kind: .unchanged),
                    right: DiffCell(number: index + 1, text: after[index], kind: .unchanged)
                ))
            } else {
                rows.append(DiffRow(
                    left: index < before.count
                        ? DiffCell(number: index + 1, text: before[index], kind: .deleted)
                        : DiffCell(number: nil, text: "", kind: .placeholder),
                    right: index < after.count
                        ? DiffCell(number: index + 1, text: after[index], kind: .inserted)
                        : DiffCell(number: nil, text: "", kind: .placeholder)
                ))
            }
        }
        return rows
    }

    private static func attributedText(for cells: [DiffCell]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.lineSpacing = 1

        for cell in cells {
            let number = cell.number.map { String(format: "%5d", $0) } ?? "     "
            let marker: String
            switch cell.kind {
            case .deleted: marker = "-"
            case .inserted: marker = "+"
            default: marker = " "
            }

            let line = "\(number) \(marker) \(cell.text)\n"
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraph
            ]

            switch cell.kind {
            case .deleted:
                attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.18)
            case .inserted:
                attributes[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.20)
            case .placeholder:
                attributes[.foregroundColor] = NSColor.clear
            case .unchanged:
                break
            }

            let attributed = NSMutableAttributedString(string: line, attributes: attributes)
            if cell.kind != .placeholder {
                attributed.addAttributes(
                    [.foregroundColor: NSColor.secondaryLabelColor],
                    range: NSRange(location: 0, length: min(5, attributed.length))
                )
                if cell.kind == .deleted {
                    attributed.addAttributes(
                        [.foregroundColor: NSColor.systemRed],
                        range: NSRange(location: 6, length: 1)
                    )
                } else if cell.kind == .inserted {
                    attributed.addAttributes(
                        [.foregroundColor: NSColor.systemGreen],
                        range: NSRange(location: 6, length: 1)
                    )
                }
            }
            result.append(attributed)
        }
        return result
    }

    private func installScrollSync() {
        leftScroll.contentView.postsBoundsChangedNotifications = true
        rightScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(leftDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: leftScroll.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rightDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: rightScroll.contentView
        )
    }

    @objc private func leftDidScroll() {
        syncScroll(from: leftScroll, to: rightScroll)
    }

    @objc private func rightDidScroll() {
        syncScroll(from: rightScroll, to: leftScroll)
    }

    private func syncScroll(from source: NSScrollView, to target: NSScrollView) {
        guard !isSyncingScroll else { return }
        isSyncingScroll = true
        var origin = target.contentView.bounds.origin
        origin.y = source.contentView.bounds.origin.y
        target.contentView.scroll(to: origin)
        target.reflectScrolledClipView(target.contentView)
        isSyncingScroll = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
