import AppKit
import WebKit
import Highlightr

/// Standalone window that displays markdown, plain-text formats (txt/json/xml),
/// or arbitrary web pages from a preview-panel tile.
///
/// - Webpages render in a WKWebView and are read-only.
/// - .txt/.json/.xml open straight into an editable NSTextView with the
///   content pretty-printed (JSON / XML) where applicable.
/// - .markdown defaults to a rendered WKWebView view; an "Edit" toggle
///   swaps to the raw source in NSTextView.
/// - For local files a Save button writes the buffer back to disk. Remote
///   files are editable in-memory but the Save button is disabled.
final class ContentViewerWindow: NSWindow, NSTextFieldDelegate, NSTextViewDelegate {
    private let webView: WKWebView
    private let textView: NSTextView
    private let textScroll: NSScrollView
    private let toolbarBar = PanelStyle.makeBarBlur()
    private let filenameLabel = NSTextField(labelWithString: "")  // identity: file name
    private let saveButton = NSButton()
    private var findButton = NSButton()     // toggles the find bar
    private var locateButton = NSButton()   // Reveal in Finder, local-only
    private let modifiedLabel = NSTextField(labelWithString: "")  // identity subtitle: path · modified
    private let addressBar = NSTextField()

    // WebView find UI
    private let webFindBar = PanelStyle.makeBarBlur()
    private let webFindField = NSTextField()
    private let webFindCountLabel = NSTextField(labelWithString: "")
    private var webFindMatchCount = 0
    private var webFindCurrentIndex = -1
    private var escapeKeyMonitor: Any?
    private var resizeCursorMonitor: Any?
    private var zoomMonitor: Any?

    private var currentZoomLevel: CGFloat = 1.0
    private let minZoomLevel: CGFloat = 0.25
    private let maxZoomLevel: CGFloat = 5.0
    private let zoomStep: CGFloat = 1.1

    private enum Kind { case webpage, markdown, text, pdf }
    private var kind: Kind = .webpage
    private var currentURL: URL?
    /// True once the editable text view has unsaved user edits. Drives whether
    /// the always-visible Save button is clickable.
    private var isDirty: Bool = false

    init() {
        // Standard desktop browser dimensions — fits most modern websites
        // comfortably without dominating the screen.
        let initialSize = NSSize(width: 1100, height: 720)
        let config = WKWebViewConfiguration()
        // Inject the find helper so every loaded document has window.__tdfind.
        let findScript = WKUserScript(
            source: Self.findHelperJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(findScript)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = false

        let tv = PanelStyle.makeCodeTextView()
        textView = tv

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.documentView = tv
        textScroll = scroll

        let initialFrame = ScreenManager.shared.contentFrame(for: NSSize(width: 652.0, height: 962.0))
        super.init(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.isReleasedWhenClosed = false
        self.title = "Glance".localized
        // Match ContentPanel's dark-glass chrome regardless of system theme.
        appearance = NSAppearance(named: .darkAqua)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        installEscapeKeyMonitor()
        installZoomMonitor()
        observeThemeChanges()
        installResizeCursorMonitor()

        buildLayout()
        showWebView()  // default
    }

    // MARK: - Public load API

    /// Loads a web page URL directly (read-only).
    func loadWebPage(_ url: URL) {
        resetZoom()
        currentURL = url
        kind = .webpage
        title = url.host ?? url.absoluteString
        webView.load(URLRequest(url: url))
        locateButton.isHidden = !url.isFileURL
        showAddressBarIdentity(for: url)
        refreshSaveButton()
        layoutToolbarButtons()
        showWebView()
        resizeToDocumentSize()
    }

    /// Loads a markdown file — rendered (read-only). No edit mode; the styled
    /// view is what you see.
    func loadMarkdown(_ url: URL) {
        resetZoom()
        currentURL = url
        kind = .markdown
        title = url.lastPathComponent
        locateButton.isHidden = !url.isFileURL
        showFileIdentity(for: url)
        refreshSaveButton()
        layoutToolbarButtons()
        resizeToDocumentSize()
        renderMarkdownView(url: url)
    }

    /// Loads a plain-text or code file directly into the editable text view.
    /// Save lights up once the content is modified.
    func loadText(_ url: URL) {
        resetZoom()
        currentURL = url
        kind = .text
        title = url.lastPathComponent
        locateButton.isHidden = !url.isFileURL
        showFileIdentity(for: url)
        layoutToolbarButtons()
        loadEditableText(url: url)
        resizeToDocumentSize()
    }

    /// Loads a PDF file in the WKWebView. macOS WebKit ships a native PDF
    /// renderer, so no extra dependencies needed. Read-only.
    func loadPDF(_ url: URL) {
        resetZoom()
        currentURL = url
        kind = .pdf
        title = url.lastPathComponent
        locateButton.isHidden = !url.isFileURL
        showFileIdentity(for: url)
        refreshSaveButton()
        layoutToolbarButtons()
        resizeToDocumentSize()
        if url.isFileURL {
            // Sandbox-friendly: explicit grant for the parent directory so
            // WebKit can read the file and any sibling assets.
            webView.loadFileURL(url,
                                 allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
        showWebView()
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
        }
    }

    private func resizeToDocumentSize() {
        let size = Self.windowSize(for: kind)
        let fixedFrame = ScreenManager.shared.contentFrame(for: size)
        setFrame(fixedFrame, display: true)
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let content = contentView else { return }
        let bounds = content.bounds
        let toolbarH: CGFloat = 52

        // Toolbar across the top: identity block on the left, action icons +
        // Save on the right (positions set in layoutToolbarButtons).
        toolbarBar.frame = NSRect(x: 0, y: bounds.height - toolbarH,
                                width: bounds.width, height: toolbarH)
        toolbarBar.autoresizingMask = [.width, .minYMargin]
        PanelStyle.addHairline(to: toolbarBar, edge: .minY)

        // ── Identity (left): filename over a path · modified subtitle ──
        filenameLabel.font = PanelStyle.headline
        filenameLabel.textColor = PanelStyle.textPrimary
        filenameLabel.lineBreakMode = .byTruncatingMiddle
        filenameLabel.maximumNumberOfLines = 1
        filenameLabel.autoresizingMask = [.width]
        toolbarBar.addSubview(filenameLabel)

        modifiedLabel.font = PanelStyle.caption
        modifiedLabel.textColor = PanelStyle.textSecondary
        modifiedLabel.alignment = .left
        modifiedLabel.lineBreakMode = .byTruncatingHead   // keep the filename tail
        modifiedLabel.maximumNumberOfLines = 1
        modifiedLabel.autoresizingMask = [.width]
        toolbarBar.addSubview(modifiedLabel)

        // Address bar replaces the identity block for web pages.
        addressBar.font = PanelStyle.label
        addressBar.alignment = .left
        addressBar.isEditable = true
        addressBar.isSelectable = true
        addressBar.isBordered = false
        addressBar.isBezeled = false
        addressBar.drawsBackground = true
        addressBar.backgroundColor = PanelStyle.controlFill
        addressBar.textColor = PanelStyle.textSecondary
        addressBar.wantsLayer = true
        addressBar.layer?.cornerRadius = 6
        addressBar.layer?.masksToBounds = true
        addressBar.autoresizingMask = [.width]
        addressBar.isHidden = true
        addressBar.target = self
        addressBar.action = #selector(addressBarSubmitted)
        toolbarBar.addSubview(addressBar)

        // ── Actions (right): Find, Locate (icons) + Save (text) ──
        findButton = PanelStyle.makeIconButton(symbol: "magnifyingglass",
                                               tooltip: "Find in page".localized,
                                               target: self, action: #selector(findTapped))
        findButton.autoresizingMask = [.minXMargin]
        toolbarBar.addSubview(findButton)

        locateButton = PanelStyle.makeIconButton(symbol: "folder",
                                                 tooltip: "Reveal in Finder".localized,
                                                 target: self, action: #selector(locateTapped))
        locateButton.autoresizingMask = [.minXMargin]
        locateButton.isHidden = true
        toolbarBar.addSubview(locateButton)

        saveButton.bezelStyle = .texturedRounded
        saveButton.title = "Save".localized
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.autoresizingMask = [.minXMargin]
        saveButton.isEnabled = false   // always visible, lit only when dirty
        toolbarBar.addSubview(saveButton)

        content.addSubview(toolbarBar)

        // Dirty-tracking for the editable text view.
        textView.delegate = self

        // Body — webView + textScroll occupy the area below the toolbar.
        let bodyFrame = NSRect(x: 0, y: 0, width: bounds.width,
                                height: bounds.height - toolbarH)
        webView.frame = bodyFrame
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)

        textScroll.frame = bodyFrame
        textScroll.autoresizingMask = [.width, .height]
        // Track the scroll view's content width so the text view word-wraps.
        textView.textContainer?.containerSize = NSSize(
            width: bodyFrame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        content.addSubview(textScroll)

        // ─── Web find bar (overlays the top edge of the web view) ───────
        let findBarH: CGFloat = 36
        webFindBar.frame = NSRect(
            x: 0, y: bodyFrame.maxY - findBarH,
            width: bodyFrame.width, height: findBarH
        )
        webFindBar.autoresizingMask = [.width, .minYMargin]
        webFindBar.isHidden = true
        PanelStyle.addHairline(to: webFindBar, edge: .minY)

        webFindField.placeholderString = "Find in page".localized
        webFindField.frame = NSRect(x: 12, y: 6, width: 240, height: 24)
        webFindField.delegate = self
        webFindBar.addSubview(webFindField)

        webFindCountLabel.font = PanelStyle.caption
        webFindCountLabel.textColor = PanelStyle.textSecondary
        webFindCountLabel.frame = NSRect(x: 260, y: 9, width: 80, height: 18)
        webFindBar.addSubview(webFindCountLabel)

        let prevBtn = NSButton(title: "‹", target: self, action: #selector(webFindPrev))
        prevBtn.bezelStyle = .texturedRounded
        prevBtn.frame = NSRect(x: bodyFrame.width - 140, y: 6, width: 32, height: 24)
        prevBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(prevBtn)

        let nextBtn = NSButton(title: "›", target: self, action: #selector(webFindNext))
        nextBtn.bezelStyle = .texturedRounded
        nextBtn.frame = NSRect(x: bodyFrame.width - 102, y: 6, width: 32, height: 24)
        nextBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(nextBtn)

        let doneBtn = NSButton(title: "Done".localized, target: self, action: #selector(hideWebFindBar))
        doneBtn.bezelStyle = .texturedRounded
        doneBtn.frame = NSRect(x: bodyFrame.width - 60, y: 6, width: 50, height: 24)
        doneBtn.autoresizingMask = [.minXMargin]
        webFindBar.addSubview(doneBtn)

        content.addSubview(webFindBar)
        layoutToolbarButtons()
    }

    /// Pack the right action group (Save + icon buttons) right-to-left, hidden
    /// ones collapsing, then size the left identity block / address bar to fill
    /// the remaining space.
    private func layoutToolbarButtons() {
        let gap: CGFloat = 8
        let saveW: CGFloat = 72
        let iconW: CGFloat = 30
        let ctrlH: CGFloat = 26
        let rightMargin: CGFloat = 16
        let leftMargin: CGFloat = 18
        let labelGap: CGFloat = 16
        let barH = toolbarBar.bounds.height
        let ctrlY = (barH - ctrlH) / 2
        let bodyWidth = toolbarBar.bounds.width

        // Right group, packed right→left; each entry carries its width.
        let group: [(NSButton, CGFloat)] = [
            (saveButton, saveW),
            (locateButton, iconW),
            (findButton, iconW),
        ]
        var currentRight = bodyWidth - rightMargin
        var leftmostVisibleX: CGFloat?
        for (button, w) in group {
            guard !button.isHidden else { continue }
            let x = currentRight - w
            button.frame = NSRect(x: x, y: ctrlY, width: w, height: ctrlH)
            leftmostVisibleX = x
            currentRight = x - gap
        }

        let identityRight = leftmostVisibleX.map { $0 - labelGap } ?? (bodyWidth - rightMargin)
        let identityWidth = max(80, identityRight - leftMargin)

        // Two-line identity block (filename over subtitle).
        if !filenameLabel.isHidden {
            filenameLabel.frame = NSRect(x: leftMargin, y: barH - 29, width: identityWidth, height: 18)
            modifiedLabel.frame  = NSRect(x: leftMargin, y: 9, width: identityWidth, height: 15)
        }
        // Address bar (web pages) fills the same area, vertically centered.
        if !addressBar.isHidden {
            addressBar.frame = NSRect(x: leftMargin, y: (barH - 26) / 2, width: identityWidth, height: 26)
        }
    }

    // MARK: - Identity (toolbar left)

    private func showFileIdentity(for url: URL) {
        addressBar.isHidden = true
        filenameLabel.isHidden = false
        modifiedLabel.isHidden = false
        filenameLabel.stringValue = url.lastPathComponent
        modifiedLabel.stringValue = Self.subtitleString(for: url)
        modifiedLabel.toolTip = url.isFileURL ? url.path : url.absoluteString
    }

    private func showAddressBarIdentity(for url: URL) {
        filenameLabel.isHidden = true
        modifiedLabel.isHidden = true
        addressBar.isHidden = false
        addressBar.stringValue = url.absoluteString
    }

    /// "~/dir · Modified <date>" subtitle shown under the filename.
    static func subtitleString(for url: URL) -> String {
        guard url.isFileURL else { return url.absoluteString }
        var parts: [String] = []
        let dir = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        if !dir.isEmpty { parts.append(dir) }
        if let date = modificationDate(for: url) {
            parts.append("Modified ".localized + friendlyDate(date))
        }
        return parts.joined(separator: " · ")
    }

    private static func modificationDate(for url: URL) -> Date? {
        guard url.isFileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    /// Human-readable date string: relative when recent, absolute otherwise.
    static func friendlyDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    /// Save is always visible; only clickable for a dirty, local, editable file.
    private func refreshSaveButton() {
        saveButton.isHidden = false
        let editable = (kind == .text) && (currentURL?.isFileURL ?? false)
        saveButton.isEnabled = editable && isDirty
    }

    private func showWebView() {
        webView.isHidden = false
        textScroll.isHidden = true
    }

    private func showTextView() {
        webView.isHidden = true
        textScroll.isHidden = false
        makeFirstResponder(textView)
    }

    // MARK: - Loading helpers

    private func renderMarkdownView(url: URL) {
        Task.detached { [weak self] in
            let raw = await Self.fetchTextContent(from: url)
            let html = Self.wrapMarkdownInHTML(raw)
            await MainActor.run {
                self?.webView.loadHTMLString(html, baseURL: url)
                self?.showWebView()
            }
        }
    }

    /// Load raw file/URL text into the editable text view. Assigning
    /// `textView.string` does not fire `textDidChange`, so the buffer starts
    /// clean (isDirty = false) until the user actually types.
    private func loadEditableText(url: URL) {
        isDirty = false
        Task.detached { [weak self] in
            let raw = await Self.fetchTextContent(from: url)
            await MainActor.run {
                guard let self = self else { return }
                (self.textView.textStorage as? CodeAttributedString)?.language = Self.hljsLanguage(for: url)
                self.textView.string = raw
                self.isDirty = false
                self.showTextView()
                self.refreshSaveButton()
            }
        }
    }

    // MARK: - Actions

    @objc private func findTapped() {
        if !webView.isHidden {
            showWebFindBar()
        } else if !textScroll.isHidden {
            invokeTextFinder(.showFindInterface)
        }
    }

    @objc private func locateTapped() {
        guard let url = currentURL, url.isFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func saveTapped() {
        guard kind == .text, let url = currentURL, url.isFileURL else { return }
        let body = textView.string
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            saveButton.isEnabled = false
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

    // NSTextViewDelegate — mark the buffer dirty on user edits so Save lights up.
    func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === textView else { return }
        isDirty = true
        refreshSaveButton()
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
        title = url.host ?? url.absoluteString
        webView.load(URLRequest(url: url))
    }

    // MARK: - Static content helpers (reused by PreviewPanel)

    /// Reads the raw text content from a local file or remote URL.
    /// Exposed so other views (e.g. an in-panel markdown push) can reuse it.
    static func fetchTextContent(from url: URL) async -> String {
        if url.isFileURL {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return String(format: "# Could not read file\n\nPath: `%@`".localized, url.path)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return String(data: data, encoding: .utf8)
                ?? String(format: "# Could not decode content\n\nURL: %@".localized, url.absoluteString)
        } catch {
            return String(format: "# Failed to load\n\n%@\n\n`%@`".localized, error.localizedDescription, url.absoluteString)
        }
    }

    /// Pretty-print a JSON document. Returns nil if the input isn't valid JSON.
    static func prettyPrintJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]) else { return nil }
        guard let pretty = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    /// Pretty-print an XML document via Foundation's XMLDocument.
    static func prettyPrintXML(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let doc = try? XMLDocument(data: data, options: [.nodePreserveAll]) else {
            return nil
        }
        let xmlData = doc.xmlData(options: [.nodePrettyPrint])
        return String(data: xmlData, encoding: .utf8)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        Logger.info("ContentViewerWindow frame changed: x=\(frameRect.origin.x), y=\(frameRect.origin.y), width=\(frameRect.size.width), height=\(frameRect.size.height)")
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
            let font = NSFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
            textView.font = font
            if let storage = textView.textStorage as? CodeAttributedString {
                storage.highlightr.theme.codeFont = font
                let lang = storage.language
                storage.language = lang   // re-highlight at the new size
            }
        }
    }

    private func installEscapeKeyMonitor() {
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  self.isVisible,
                  event.window === self,
                  event.keyCode == 53 else {
                return event
            }
            self.close()
            return nil
        }
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

    deinit {
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
        }
        if let zoomMonitor {
            NSEvent.removeMonitor(zoomMonitor)
        }
        if let resizeCursorMonitor {
            NSEvent.removeMonitor(resizeCursorMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func installResizeCursorMonitor() {
        resizeCursorMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self = self, self.isVisible, event.window === self else { return event }
            let loc = event.locationInWindow
            let edgeSize: CGFloat = 8
            let w = self.frame.width
            let h = self.frame.height
            let onLeft = loc.x <= edgeSize
            let onRight = loc.x >= w - edgeSize
            let onBottom = loc.y <= edgeSize
            let onTop = loc.y >= h - edgeSize
            switch (onTop, onBottom, onLeft, onRight) {
            case (true, _, true, _), (_, true, _, true): NSCursor.crosshair.set()
            case (true, _, _, true), (_, true, true, _): NSCursor.crosshair.set()
            case (true, _, _, _), (_, true, _, _):       NSCursor.resizeUpDown.set()
            case (_, _, true, _), (_, _, _, true):       NSCursor.resizeLeftRight.set()
            default: break
            }
            return event
        }
    }

    private func observeThemeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateToolbarAppearance),
            name: .preferencesDidChange,
            object: nil
        )
    }

    @objc private func updateToolbarAppearance() {
        // Dark-glass chrome is theme-independent; just re-tint the hairlines.
        for bar in [toolbarBar, webFindBar] {
            for sub in bar.subviews where sub.frame.height == 1 {
                sub.layer?.backgroundColor = PanelStyle.hairline.cgColor
            }
        }
    }

    // MARK: - Find shortcuts

    /// Intercept ⌘F / ⌘G / ⌘⇧G ourselves. This app runs as `LSUIElement`
    /// with no main menu, so the standard Edit > Find menu shortcuts that
    /// would normally trigger NSTextView's find bar never reach the text
    /// view. We route them manually based on which body view is showing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            close()
            return true
        }
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

    /// Drive NSTextView's built-in find bar by faking the sender NSMenuItem
    /// whose `tag` `performTextFinderAction(_:)` reads to dispatch the
    /// requested action.
    private func invokeTextFinder(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }

    private func showWebFindBar() {
        webFindBar.isHidden = false
        webFindBar.frame.origin.y = (contentView?.bounds.height ?? 0) - 52 /* toolbar */ - webFindBar.bounds.height
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
        let jsQuery = Self.jsStringLiteral(query)
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

    // NSTextFieldDelegate — incremental search + Esc/Enter handling.
    func controlTextDidChange(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField, tf === webFindField else { return }
        runWebFind(query: tf.stringValue)
    }

    func control(_ control: NSControl, textView fieldEditor: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if control === webFindField {
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
        if control === addressBar {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                addressBarSubmitted()
                return true
            }
            return false
        }
        return false
    }

    /// Encode an arbitrary string as a JS string literal (handles quotes,
    /// backslashes, newlines, control chars). Used when interpolating user
    /// input into evaluateJavaScript calls.
    static func jsStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    /// JS injected at document-end on every page load. Exposes
    /// `window.__tdfind` with `highlight(query)`, `next()`, `prev()`,
    /// `clear()`.
    static let findHelperJS: String = """
    (function(){
      if (window.__tdfind) return;
      const SCROLL_OPTS = { block: 'center', behavior: 'smooth' };
      function clear(self){
        self.marks.forEach(m => {
          if (m.parentNode) {
            const t = document.createTextNode(m.textContent);
            m.parentNode.replaceChild(t, m);
          }
        });
        // Coalesce adjacent text nodes back together.
        try { document.body.normalize(); } catch(e) {}
        self.marks = [];
        self.current = -1;
      }
      function refresh(self){
        for (let i = 0; i < self.marks.length; i++) {
          self.marks[i].style.background = (i === self.current) ? '#ff9800' : '#ffe066';
          self.marks[i].style.color = '#000';
        }
        if (self.current >= 0 && self.current < self.marks.length) {
          self.marks[self.current].scrollIntoView(SCROLL_OPTS);
        }
      }
      window.__tdfind = {
        marks: [],
        current: -1,
        clear: function(){ clear(this); },
        highlight: function(query){
          clear(this);
          if (!query) return 0;
          const q = String(query).toLowerCase();
          if (q.length === 0) return 0;
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: function(n){
              const p = n.parentElement;
              if (!p) return NodeFilter.FILTER_REJECT;
              if (p.closest('script, style, noscript')) return NodeFilter.FILTER_REJECT;
              if (p.classList && p.classList.contains('tdfind')) return NodeFilter.FILTER_REJECT;
              return NodeFilter.FILTER_ACCEPT;
            }
          });
          const targets = [];
          let n;
          while ((n = walker.nextNode())) {
            if (n.nodeValue && n.nodeValue.toLowerCase().indexOf(q) !== -1) targets.push(n);
          }
          const marks = [];
          targets.forEach(node => {
            const text = node.nodeValue;
            const lower = text.toLowerCase();
            const frag = document.createDocumentFragment();
            let last = 0, i;
            while ((i = lower.indexOf(q, last)) !== -1) {
              if (i > last) frag.appendChild(document.createTextNode(text.slice(last, i)));
              const mk = document.createElement('mark');
              mk.className = 'tdfind';
              mk.style.background = '#ffe066';
              mk.style.color = '#000';
              mk.textContent = text.slice(i, i + q.length);
              frag.appendChild(mk);
              marks.push(mk);
              last = i + q.length;
            }
            if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
            if (node.parentNode) node.parentNode.replaceChild(frag, node);
          });
          this.marks = marks;
          this.current = marks.length > 0 ? 0 : -1;
          refresh(this);
          return marks.length;
        },
        next: function(){
          if (this.marks.length === 0) return -1;
          this.current = (this.current + 1) % this.marks.length;
          refresh(this);
          return this.current;
        },
        prev: function(){
          if (this.marks.length === 0) return -1;
          this.current = (this.current - 1 + this.marks.length) % this.marks.length;
          refresh(this);
          return this.current;
        }
      };
    })();
    """

    /// Language identifier for Highlightr (highlight.js). Reuses the Prism map
    /// and remaps the few names that differ between the two.
    static func hljsLanguage(for url: URL) -> String? {
        guard let lang = languageIdentifier(for: url) else { return nil }
        switch lang {
        case "markup": return "xml"
        case "batch":  return "dos"
        default:       return lang
        }
    }

    /// Map a file extension to a Prism.js language identifier.
    static func languageIdentifier(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "mjs", "cjs": return "javascript"
        case "ts": return "typescript"
        case "tsx": return "tsx"
        case "jsx": return "jsx"
        case "java": return "java"
        case "kt": return "kotlin"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "rb": return "ruby"
        case "go": return "go"
        case "rs": return "rust"
        case "php": return "php"
        case "cs": return "csharp"
        case "lua": return "lua"
        case "sh", "bash": return "bash"
        case "zsh": return "zsh"
        case "fish": return "fish"
        case "ps1": return "powershell"
        case "bat", "cmd": return "batch"
        case "json": return "json"
        case "xml": return "xml"
        case "yaml", "yml": return "yaml"
        case "ini", "conf", "cfg": return "ini"
        case "toml": return "toml"
        case "html", "htm": return "html"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "less": return "less"
        case "sql": return "sql"
        case "graphql", "gql": return "graphql"
        case "proto": return "protobuf"
        case "dart": return "dart"
        case "scala": return "scala"
        case "r": return "r"
        case "pl": return "perl"
        case "erl": return "erlang"
        case "hs": return "haskell"
        case "ml": return "ocaml"
        case "fs": return "fsharp"
        case "jl": return "julia"
        case "tex": return "latex"
        case "vue", "svelte": return "markup"
        case "astro": return "astro"
        default: return nil
        }
    }

    /// Wrap source code in an HTML host page with Prism.js syntax highlighting.
    /// Falls back to a plain `<pre>` block when offline or for unrecognised languages.
    static func wrapCodeInHTML(_ code: String, language: String?) -> String {
        let escaped = code
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let langClass = language.map { " class=\"language-\($0)\"" } ?? ""
        let langTitle = language?.uppercased() ?? "TEXT"

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css">
          <style>
            body {
              font-family: ui-monospace, "SF Mono", Menlo, monospace;
              font-size: 13px;
              line-height: 1.6;
              margin: 0;
              padding: 16px 22px 40px;
              background: #1b1d21;
              color: #d6d9dd;
              -webkit-font-smoothing: antialiased;
            }
            ::selection { background: rgba(108,182,255,0.30); }
            .file-header {
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              font-size: 11px;
              font-weight: 600;
              letter-spacing: 0.02em;
              color: #9aa0a6;
              margin: -4px -6px 14px;
              padding: 6px 10px;
              border-radius: 7px;
              background: rgba(255,255,255,0.05);
              display: flex;
              justify-content: space-between;
            }
            .file-header span:first-child { text-transform: uppercase; }
            pre {
              margin: 0;
              background: transparent !important;
            }
            code {
              font-family: ui-monospace, "SF Mono", Menlo, monospace;
              font-size: 13px;
              line-height: 1.6;
            }
            pre[class*="language-"] {
              background: transparent !important;
              margin: 0 !important;
              padding: 0 !important;
              white-space: pre-wrap;
              word-wrap: break-word;
              overflow: hidden;
              text-shadow: none !important;
            }
            :not(pre) > code[class*="language-"] {
              background: rgba(255,255,255,0.08) !important;
              padding: 2px 5px !important;
              border-radius: 4px;
            }
          </style>
        </head>
        <body>
          <div class="file-header"><span>\(langTitle)</span><span>\(code.count) chars</span></div>
          <pre><code\(langClass)>\(escaped)</code></pre>
          <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-core.min.js"></script>
          <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/autoloader/prism-autoloader.min.js"></script>
        </body>
        </html>
        """
    }

    /// Wrap markdown source in an HTML host page that renders via marked.js
    /// from a CDN (falls back to plain-text display when offline).
    static func wrapMarkdownInHTML(_ markdown: String) -> String {
        let escaped = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            /* Dark reading theme — committed to dark so the rendered page sits
               cohesively inside Glance's dark-glass panel regardless of the
               system appearance. */
            :root {
              --bg: #1b1d21;
              --fg: #e7e9ec;
              --muted: #9aa0a6;
              --hairline: rgba(255,255,255,0.10);
              --fill: rgba(255,255,255,0.06);
              --fill-strong: rgba(255,255,255,0.09);
              --accent: #6cb6ff;
            }
            * { box-sizing: border-box; }
            html { -webkit-text-size-adjust: 100%; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text",
                           system-ui, sans-serif;
              font-size: 15px;
              line-height: 1.72;
              color: var(--fg);
              background: var(--bg);
              max-width: 740px;
              margin: 0 auto;
              padding: 40px 28px 64px;
              -webkit-font-smoothing: antialiased;
            }
            ::selection { background: rgba(108,182,255,0.30); }
            h1, h2, h3, h4, h5, h6 {
              line-height: 1.3; margin: 1.6em 0 0.6em; font-weight: 600;
              letter-spacing: -0.01em; color: #f3f5f8;
            }
            h1 { font-size: 1.9em; border-bottom: 1px solid var(--hairline); padding-bottom: 0.3em; }
            h2 { font-size: 1.5em; border-bottom: 1px solid var(--hairline); padding-bottom: 0.25em; }
            h3 { font-size: 1.25em; }
            h4 { font-size: 1.05em; }
            p, ul, ol, blockquote, table { margin: 0.9em 0; }
            ul, ol { padding-left: 1.4em; }
            li { margin: 0.25em 0; }
            blockquote {
              border-left: 3px solid var(--accent);
              padding: 0.2em 0 0.2em 1em; margin-left: 0;
              color: var(--muted);
            }
            hr { border: none; border-top: 1px solid var(--hairline); margin: 2em 0; }
            code {
              font-family: ui-monospace, "SF Mono", Menlo, monospace;
              background: var(--fill-strong); padding: 0.15em 0.4em;
              border-radius: 5px; font-size: 0.88em;
            }
            pre {
              background: #111317; border: 1px solid var(--hairline);
              padding: 14px 16px; border-radius: 10px;
              white-space: pre-wrap; word-wrap: break-word;
              overflow-x: auto; line-height: 1.55;
            }
            pre code { background: transparent; padding: 0; font-size: 0.86em; border: none; }
            img { max-width: 100%; height: auto; border-radius: 8px; }
            a { color: var(--accent); text-decoration: none; }
            a:hover { text-decoration: underline; }
            table { border-collapse: collapse; width: 100%; font-size: 0.92em; }
            th, td { border: 1px solid var(--hairline); padding: 7px 12px; text-align: left; }
            th { background: var(--fill); font-weight: 600; }
            tr:nth-child(even) td { background: rgba(255,255,255,0.02); }
          </style>
        </head>
        <body>
          <pre id="raw" style="display:none">\(escaped)</pre>
          <div id="rendered"></div>
          <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
          <script>
            (function() {
              var raw = document.getElementById('raw').textContent;
              var target = document.getElementById('rendered');
              if (typeof marked === 'object' && typeof marked.parse === 'function') {
                target.innerHTML = marked.parse(raw);
              } else if (typeof marked === 'function') {
                target.innerHTML = marked(raw);
              } else {
                var pre = document.createElement('pre');
                pre.textContent = raw;
                target.appendChild(pre);
              }
            })();
          </script>
        </body>
        </html>
        """
    }
}
