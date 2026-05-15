import AppKit
import WebKit

final class ContentPanel: NSPanel, NSTextFieldDelegate, WKNavigationDelegate {
    static let shared = ContentPanel()

    private let webView: WKWebView
    private let textView: NSTextView
    private let textScroll: NSScrollView
    private let toolbarBar = NSView()
    private let saveButton = NSButton()
    private let toggleButton = NSButton()
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
    private var isEditing: Bool = false

    private let headerHeight: CGFloat = 48
    private let toolbarH: CGFloat = 36
    private let imageInfoBarH: CGFloat = 48

    private weak var loadingOverlay: NSView?
    private weak var loadingSpinner: NSProgressIndicator?

    private let imageInfoBar = NSView()
    private let imageInfoNameLabel = NSTextField(labelWithString: "")
    private let imageInfoMetaLabel = NSTextField(labelWithString: "")

    /// Set to true when the user drags the panel by hand; once true the
    /// panel will no longer follow PreviewPanel automatically.
    private(set) var hasBeenManuallyMoved: Bool = false
    /// Guard used inside didMoveNotification to distinguish user-driven
    /// moves from programmatic sync moves coming from PreviewPanel.
    private var isBeingSynced: Bool = false

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

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        webView.navigationDelegate = self

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        isMovableByWindowBackground = true

        buildLayout()
        showWebView()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    @objc private func panelDidMove() {
        guard !isBeingSynced else { return }
        hasBeenManuallyMoved = true
    }

    /// Move the panel so it sits immediately to the right of the given
    /// preview frame.  Called by PreviewPanel when it moves — unless the
    /// user has already dragged this panel independently.
    func syncPosition(to previewFrame: NSRect) {
        guard !hasBeenManuallyMoved else { return }
        let contentSize = frame.size
        let originX = previewFrame.maxX
        let originY = previewFrame.maxY - contentSize.height
        let newFrame = NSRect(origin: CGPoint(x: originX, y: originY), size: contentSize)
        isBeingSynced = true
        setFrame(newFrame, display: true)
        isBeingSynced = false
    }

    /// Call when a fresh preview cycle starts so the panel will resume
    /// following PreviewPanel even if it was manually dragged before.
    func resetFollowState() {
        hasBeenManuallyMoved = false
    }

    private func buildLayout() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor

        let navBar = buildNavBar(width: 700)
        navBar.frame = NSRect(x: 0, y: 600 - headerHeight, width: 700, height: headerHeight)
        navBar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(navBar)

        let bodyFrame = NSRect(x: 0, y: 0, width: 700, height: 600 - headerHeight)

        toolbarBar.frame = NSRect(x: 0, y: bodyFrame.height - toolbarH,
                                  width: bodyFrame.width, height: toolbarH)
        toolbarBar.autoresizingMask = [.width, .minYMargin]
        toolbarBar.wantsLayer = true
        toolbarBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let sep = NSView(frame: NSRect(x: 0, y: 0, width: bodyFrame.width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.autoresizingMask = [.width]
        toolbarBar.addSubview(sep)

        let locateW: CGFloat = 32
        locateButton.bezelStyle = .rounded
        locateButton.image = NSImage(systemSymbolName: "folder.fill",
                                       accessibilityDescription: "Reveal in Finder")
        locateButton.imagePosition = .imageOnly
        locateButton.target = self
        locateButton.action = #selector(locateTapped)
        locateButton.toolTip = "Reveal in Finder"
        locateButton.frame = NSRect(x: bodyFrame.width - 12 - locateW, y: 6,
                                     width: locateW, height: 24)
        locateButton.autoresizingMask = [.minXMargin]
        locateButton.isHidden = true
        toolbarBar.addSubview(locateButton)

        saveButton.bezelStyle = .rounded
        saveButton.title = "Save"
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.frame = NSRect(x: bodyFrame.width - 20 - locateW - 70, y: 6,
                                   width: 70, height: 24)
        saveButton.autoresizingMask = [.minXMargin]
        saveButton.isHidden = true
        toolbarBar.addSubview(saveButton)

        toggleButton.bezelStyle = .rounded
        toggleButton.title = "Edit"
        toggleButton.target = self
        toggleButton.action = #selector(toggleEditTapped)
        toggleButton.frame = NSRect(x: bodyFrame.width - 30 - locateW - 70 - 70, y: 6,
                                     width: 70, height: 24)
        toggleButton.autoresizingMask = [.minXMargin]
        toggleButton.isHidden = true
        toolbarBar.addSubview(toggleButton)

        modifiedLabel.font = NSFont.systemFont(ofSize: 11)
        modifiedLabel.textColor = .secondaryLabelColor
        modifiedLabel.alignment = .right
        modifiedLabel.lineBreakMode = .byTruncatingTail
        modifiedLabel.maximumNumberOfLines = 1
        modifiedLabel.frame = NSRect(x: bodyFrame.width - 30 - locateW - 70 - 70 - 160 - 12,
                                      y: 9, width: 160, height: 18)
        modifiedLabel.autoresizingMask = [.minXMargin]
        toolbarBar.addSubview(modifiedLabel)

        addressBar.font = NSFont.systemFont(ofSize: 12)
        addressBar.alignment = .center
        addressBar.isEditable = false
        addressBar.isSelectable = true
        addressBar.isBordered = true
        addressBar.backgroundColor = NSColor(white: 0.18, alpha: 1)
        addressBar.textColor = .secondaryLabelColor
        addressBar.frame = NSRect(x: 80, y: 6, width: bodyFrame.width - 160, height: 24)
        addressBar.autoresizingMask = [.width]
        addressBar.isHidden = true
        toolbarBar.addSubview(addressBar)

        root.addSubview(toolbarBar)

        let contentFrame = NSRect(x: 0, y: 0, width: bodyFrame.width,
                                   height: bodyFrame.height - toolbarH)
        webView.frame = contentFrame
        webView.autoresizingMask = [.width, .height]
        root.addSubview(webView)

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

        webFindField.placeholderString = "Find in page"
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

        let doneBtn = NSButton(title: "Done", target: self, action: #selector(hideWebFindBar))
        doneBtn.bezelStyle = .rounded
        doneBtn.frame = NSRect(x: contentFrame.width - 60, y: 6, width: 50, height: 24)
        doneBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(doneBtn)

        root.addSubview(webFindBar)

        let overlay = NSView(frame: contentFrame)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true

        let spinner = NSProgressIndicator(frame: NSRect(
            x: (contentFrame.width - 24) / 2,
            y: (contentFrame.height - 24) / 2,
            width: 24, height: 24
        ))
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.usesThreadedAnimation = true
        spinner.appearance = NSAppearance(named: .vibrantDark)
        spinner.autoresizingMask = [.minXMargin, .minYMargin, .maxXMargin, .maxYMargin]
        spinner.startAnimation(nil)
        overlay.addSubview(spinner)

        let loadingLbl = NSTextField(labelWithString: "Loading…")
        loadingLbl.textColor = NSColor(white: 1, alpha: 0.7)
        loadingLbl.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        loadingLbl.alignment = .center
        loadingLbl.frame = NSRect(x: 0, y: spinner.frame.minY - 22,
                                   width: contentFrame.width, height: 16)
        loadingLbl.autoresizingMask = [.width, .minXMargin, .maxXMargin]
        overlay.addSubview(loadingLbl)

        root.addSubview(overlay)
        loadingOverlay = overlay
        loadingSpinner = spinner

        // Image info bar — floats above the content area when viewing images.
        imageInfoBar.frame = NSRect(x: 0, y: 0,
                                     width: bodyFrame.width, height: imageInfoBarH)
        imageInfoBar.autoresizingMask = [.width, .maxYMargin]
        imageInfoBar.wantsLayer = true
        imageInfoBar.layer?.backgroundColor = NSColor(white: 0, alpha: 0.78).cgColor
        imageInfoBar.isHidden = true

        imageInfoNameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        imageInfoNameLabel.textColor = .white
        imageInfoNameLabel.lineBreakMode = .byTruncatingMiddle
        imageInfoNameLabel.maximumNumberOfLines = 1
        imageInfoNameLabel.frame = NSRect(x: 16, y: 24,
                                           width: bodyFrame.width - 32, height: 18)
        imageInfoNameLabel.autoresizingMask = [.width]
        imageInfoBar.addSubview(imageInfoNameLabel)

        imageInfoMetaLabel.font = NSFont.systemFont(ofSize: 11)
        imageInfoMetaLabel.textColor = NSColor(white: 1, alpha: 0.75)
        imageInfoMetaLabel.lineBreakMode = .byTruncatingTail
        imageInfoMetaLabel.maximumNumberOfLines = 1
        imageInfoMetaLabel.frame = NSRect(x: 16, y: 6,
                                           width: bodyFrame.width - 32, height: 14)
        imageInfoMetaLabel.autoresizingMask = [.width]
        imageInfoBar.addSubview(imageInfoMetaLabel)

        root.addSubview(imageInfoBar)

        contentView = root
    }

    private func buildNavBar(width: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.autoresizingMask = [.width]
        bar.addSubview(sep)

        let closeBtn = NSButton(frame: .zero)
        closeBtn.bezelStyle = .recessed
        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.contentTintColor = .labelColor
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        closeBtn.frame = NSRect(x: 12, y: (headerHeight - 24) / 2, width: 24, height: 24)
        bar.addSubview(closeBtn)

        let titleLbl = NSTextField(labelWithString: "TempDisplay")
        titleLbl.textColor = .labelColor
        titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLbl.alignment = .center
        titleLbl.frame = NSRect(x: 48, y: (headerHeight - 18) / 2, width: width - 96, height: 18)
        titleLbl.autoresizingMask = [.width]
        bar.addSubview(titleLbl)

        return bar
    }

    @objc private func closeTapped() {
        orderOut(nil)
    }

    func dismiss() {
        orderOut(nil)
    }

    func load(info: MediaInfo) {
        currentMediaInfo = info
        showLoading()
        switch info.kind {
        case .markdown:
            currentURL = info.url
            kind = .markdown
            isEditing = false
            showToolbar()
            imageInfoBar.isHidden = true
            toggleButton.isHidden = false
            toggleButton.title = "Edit"
            saveButton.isHidden = true
            locateButton.isHidden = !info.url.isFileURL
            updateModifiedDate(for: info.url)
            renderMarkdownView(url: info.url)
        case .text:
            currentURL = info.url
            kind = .text
            isEditing = false
            showToolbar()
            imageInfoBar.isHidden = true
            toggleButton.isHidden = false
            toggleButton.title = "Edit"
            saveButton.isHidden = true
            locateButton.isHidden = !info.url.isFileURL
            updateModifiedDate(for: info.url)
            renderHighlightedCode(url: info.url)
        case .pdf:
            currentURL = info.url
            kind = .pdf
            showToolbar()
            imageInfoBar.isHidden = true
            toggleButton.isHidden = true
            saveButton.isHidden = true
            locateButton.isHidden = !info.url.isFileURL
            updateModifiedDate(for: info.url)
            if info.url.isFileURL {
                webView.loadFileURL(info.url, allowingReadAccessTo: info.url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: info.url))
            }
            showWebView()
        case .image:
            currentURL = info.url
            kind = .image
            showToolbar()
            toggleButton.isHidden = true
            saveButton.isHidden = true
            locateButton.isHidden = !info.url.isFileURL
            updateImageInfoBar(with: info)
            imageInfoBar.isHidden = false
            let html = """
            <html><head><style>
            body { margin: 0; display: flex; align-items: center; justify-content: center;
                   background: #0a0a0a; height: 100vh; }
            img { max-width: 100%; max-height: 100%; object-fit: contain; }
            </style></head><body><img src="\(info.url.absoluteString)"></body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
            showWebView()
            hideLoading()
        default:
            currentURL = info.url
            kind = .webpage
            showToolbar()
            imageInfoBar.isHidden = true
            locateButton.isHidden = !info.url.isFileURL
            webView.load(URLRequest(url: info.url))
            showWebView()
        }
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
    }

    private func showTextView() {
        webView.isHidden = true
        textScroll.isHidden = false
    }

    private func showAddressBar(for url: URL) {
        toggleButton.isHidden = true
        saveButton.isHidden = true
        locateButton.isHidden = !url.isFileURL
        modifiedLabel.isHidden = true
        addressBar.isHidden = false
        addressBar.stringValue = url.absoluteString
    }

    private func showToolbar() {
        addressBar.isHidden = true
        modifiedLabel.isHidden = false
    }

    @objc private func toggleEditTapped() {
        guard let url = currentURL else { return }
        guard kind == .markdown || kind == .text else { return }
        isEditing.toggle()
        if isEditing {
            toggleButton.title = "View"
            saveButton.isHidden = !url.isFileURL
            loadEditableText(url: url, prettyPrint: false)
        } else {
            toggleButton.title = "Edit"
            saveButton.isHidden = true
            if kind == .markdown {
                renderMarkdownView(url: url)
            } else {
                renderHighlightedCode(url: url)
            }
        }
    }

    @objc private func locateTapped() {
        guard let url = currentURL, url.isFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func saveTapped() {
        guard let url = currentURL, url.isFileURL else { return }
        let body = textView.string
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            saveButton.title = "Saved ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.saveButton.title = "Save"
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't save \(url.lastPathComponent)"
            alert.beginSheetModal(for: self, completionHandler: nil)
        }
    }

    private func updateModifiedDate(for url: URL?) {
        guard let url = url, url.isFileURL else {
            modifiedLabel.stringValue = ""
            return
        }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            modifiedLabel.stringValue = ""
            return
        }
        modifiedLabel.stringValue = "Modified \(ContentViewerWindow.friendlyDate(date))"
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
            webFindCountLabel.stringValue = webFindField.stringValue.isEmpty ? "" : "0 results"
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
}

extension ContentPanel {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        hideLoading()
    }
}
