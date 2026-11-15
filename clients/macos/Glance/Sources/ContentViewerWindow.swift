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
///
/// Layout follows Figma `18 · Content Viewer / Markdown`: a 44 pt titlebar with
/// a centred title and the action segments, the body, and a 32 pt status bar.
final class ContentViewerWindow: NSWindow, NSTextFieldDelegate, NSTextViewDelegate, WKNavigationDelegate {
    private let webView: WKWebView
    private let textView: NSTextView
    private let textScroll: NSScrollView
    private let titlebar = ContentTitlebarView()
    private let actionGroup = ContentSegmentGroup()
    private let saveButton = ContentSegmentButton(text: "Save".localized)
    private var findButton = NSButton()     // toggles the find bar
    private var locateButton = NSButton()   // Reveal in Finder, local-only
    private let statusBar = ContentStatusBar()  // path · kind · size · modified
    private let addressBar = NSTextField()
    private let loadingIndicator = FocusSweepLoadingView(frame: .zero)

    // WebView find UI
    private lazy var webFindBar = ContentFindBar(target: self,
                                                 previous: #selector(webFindPrev(_:)),
                                                 next: #selector(webFindNext(_:)),
                                                 done: #selector(hideWebFindBar))
    private var webFindField: NSTextField { webFindBar.field }
    private var webFindCountLabel: NSTextField { webFindBar.countLabel }
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
        let config = WKWebViewConfiguration()
        PanelStyle.styleWebScrollbars(in: config)
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
        tv.textContainerInset = NSSize(width: 20, height: 16)
        textView = tv

        let scroll = NSScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        PanelStyle.styleScrollers(in: scroll)
        scroll.borderType = .noBorder
        scroll.documentView = tv
        textScroll = scroll

        let initialFrame = ScreenManager.shared.contentFrame(for: NSSize(width: 652.0, height: 962.0))
        super.init(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        self.isReleasedWhenClosed = false
        self.title = "Glance".localized
        // Match ContentPanel's chrome regardless of system theme.
        appearance = PanelStyle.windowAppearance
        backgroundColor = ContentChrome.window
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        ContentChrome.hideSystemTrafficLights(of: self)
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
        showLoading()
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
        showLoading()
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
        showLoading()
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
        showLoading()
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
        let titleH = ContentChrome.titlebarHeight
        let statusH = ContentChrome.statusHeight
        ContentChrome.paint(content, ContentChrome.window)

        // Titlebar: traffic lights, centred identity, action segments + icons.
        titlebar.frame = NSRect(x: 0, y: bounds.height - titleH, width: bounds.width, height: titleH)
        titlebar.autoresizingMask = [.width, .minYMargin]
        titlebar.onResize = { [weak self] in self?.layoutToolbarButtons() }
        content.addSubview(titlebar)

        // Address bar replaces the centred title for web pages.
        ContentChrome.styleAddressBar(addressBar)
        addressBar.isEditable = true
        addressBar.isHidden = true
        addressBar.target = self
        addressBar.action = #selector(addressBarSubmitted)
        titlebar.addSubview(addressBar)

        findButton = ContentChrome.makeIconButton(symbol: "magnifyingglass",
                                                  tooltip: "Find in page".localized,
                                                  target: self, action: #selector(findTapped))
        titlebar.addSubview(findButton)

        locateButton = ContentChrome.makeIconButton(symbol: "folder",
                                                    tooltip: "Reveal in Finder".localized,
                                                    target: self, action: #selector(locateTapped))
        locateButton.isHidden = true
        titlebar.addSubview(locateButton)

        saveButton.activatesWhenEnabled = true
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.isEnabled = false   // always visible, lit only when dirty
        actionGroup.addSubview(saveButton)
        titlebar.addSubview(actionGroup)

        // Dirty-tracking for the editable text view.
        textView.delegate = self

        statusBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: statusH)
        statusBar.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(statusBar)

        // Body — webView + textScroll fill the space between the two bars.
        let bodyFrame = NSRect(x: 0, y: statusH, width: bounds.width,
                               height: bounds.height - titleH - statusH)
        webView.frame = bodyFrame
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView, positioned: .below, relativeTo: titlebar)

        textScroll.frame = bodyFrame
        textScroll.autoresizingMask = [.width, .height]
        textScroll.drawsBackground = false
        // Track the scroll view's content width so the text view word-wraps.
        textView.textContainer?.containerSize = NSSize(
            width: bodyFrame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        content.addSubview(textScroll, positioned: .below, relativeTo: titlebar)

        loadingIndicator.frame = NSRect(
            x: bodyFrame.midX - FocusSweepLoadingView.preferredSize.width / 2,
            y: bodyFrame.midY - FocusSweepLoadingView.preferredSize.height / 2,
            width: FocusSweepLoadingView.preferredSize.width,
            height: FocusSweepLoadingView.preferredSize.height
        )
        loadingIndicator.autoresizingMask = [.minXMargin, .minYMargin, .maxXMargin, .maxYMargin]
        content.addSubview(loadingIndicator)

        // ─── Web find card (floats over the top-right of the document) ───
        webFindBar.frame = NSRect(origin: ContentChrome.findBarOrigin(in: bounds),
                                  size: ContentChrome.findBarSize)
        webFindBar.autoresizingMask = [.minXMargin, .minYMargin]
        webFindBar.isHidden = true
        webFindField.delegate = self
        content.addSubview(webFindBar)
        layoutToolbarButtons()
    }

    /// Pack the right action group (icons, then the Save segment) right-to-left,
    /// hidden ones collapsing, then centre the title / address bar in the rest.
    private func layoutToolbarButtons() {
        let groupMinX = ContentChrome.layoutTrailingControls(
            in: titlebar,
            icons: [locateButton, findButton],
            group: actionGroup,
            segments: [(saveButton, ContentSegmentButton.width(for: ["Save".localized, "Saved ✓".localized]))]
        )
        titlebar.centerTitle(addressBar.isHidden ? titlebar.titleLabel : addressBar,
                             rightLimit: groupMinX - 12)
    }

    // MARK: - Identity (titlebar + status bar)

    private func showFileIdentity(for url: URL) {
        addressBar.isHidden = true
        titlebar.titleLabel.isHidden = false
        titlebar.titleLabel.stringValue = url.lastPathComponent
        titlebar.titleLabel.toolTip = url.isFileURL ? url.path : url.absoluteString
        let kindLabel = kind == .markdown ? "Markdown".localized : url.pathExtension.uppercased()
        statusBar.show(left: ContentChrome.statusPath(for: url),
                       right: ContentChrome.statusDetail(for: url, kindLabel: kindLabel),
                       leftToolTip: url.isFileURL ? url.path : url.absoluteString)
    }

    private func showAddressBarIdentity(for url: URL) {
        titlebar.titleLabel.isHidden = true
        addressBar.isHidden = false
        addressBar.stringValue = url.absoluteString
        statusBar.show(left: "", right: "", leftToolTip: nil)
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

    static func modificationDate(for url: URL) -> Date? {
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
            let html = Self.wrapMarkdownInHTML(raw, documentTop: ContentChrome.documentTop)
            await MainActor.run {
                self?.webView.loadHTMLString(html, baseURL: url)
                self?.showWebView()
            }
        }
    }

    /// Load raw file/URL text into the editable text view. Assigning
    /// `textView.string` does not fire `textDidChange`, so the buffer starts
    /// clean (isDirty = false) until the user actually types.
    private static let maxHighlightedBytes = 256 * 1024

    private func loadEditableText(url: URL) {
        isDirty = false
        Task.detached { [weak self] in
            let raw = await Self.fetchTextContent(from: url)
            await MainActor.run {
                guard let self = self else { return }
                // Highlighting runs on the main thread; past a few hundred KB it
                // freezes the app for seconds, so big files open as plain text.
                let highlight = raw.utf8.count <= Self.maxHighlightedBytes
                (self.textView.textStorage as? CodeAttributedString)?.language = highlight ? Self.hljsLanguage(for: url) : nil
                self.textView.string = raw
                self.isDirty = false
                self.showTextView()
                self.hideLoading()
                self.refreshSaveButton()
            }
        }
    }

    private func showLoading() {
        loadingIndicator.setLoading(true)
    }

    private func hideLoading() {
        loadingIndicator.setLoading(false)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        showLoading()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        hideLoading()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        hideLoading()
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
        guard BillingCoordinator.shared.requireLocalTool("Save".localized, over: self) else { return }
        guard kind == .text, let url = currentURL, url.isFileURL else { return }
        let body = textView.string
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            saveButton.isEnabled = false
            saveButton.text = "Saved ✓".localized
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.saveButton.text = "Save".localized
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
        // Theme tokens are fixed for the session; re-assert the layer snapshots.
        if let content = contentView { ContentChrome.paint(content, ContentChrome.window) }
        titlebar.applyTheme()
        actionGroup.applyTheme()
        statusBar.applyTheme()
        webFindBar.applyTheme()
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
        webFindBar.frame.origin = ContentChrome.findBarOrigin(in: contentView?.bounds ?? .zero)
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
    /// `clear()`. Matches are vermilion marks (Figma `find match`).
    static let findHelperJS: String = {
        let current = ContentChrome.css(PanelStyle.failure)
        let currentInk = ContentChrome.css(PanelStyle.themed(PanelStyle.Sumi.text1, PanelStyle.Washi.ink1))
        let other = ContentChrome.css(PanelStyle.failure, alpha: 0.28)
        return """
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
          self.marks[i].style.background = (i === self.current) ? '\(current)' : '\(other)';
          self.marks[i].style.color = (i === self.current) ? '\(currentInk)' : 'inherit';
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
              mk.style.background = '\(other)';
              mk.style.color = 'inherit';
              mk.style.borderRadius = '3px';
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
    }()

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
          <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/\(PanelStyle.isLight ? "prism" : "prism-tomorrow").min.css">
          <style>
            \(ContentChrome.rootCSS)
            body {
              font-family: var(--font-mono);
              font-size: 13px;
              line-height: 1.6;
              margin: 0;
              padding: 16px 22px 40px;
              background: var(--ink1);
              color: var(--text1);
              -webkit-font-smoothing: antialiased;
            }
            ::selection { background: var(--selection); }
            .file-header {
              font-family: var(--font-ui);
              font-size: 11px;
              font-weight: 500;
              letter-spacing: 0.02em;
              color: var(--text3);
              margin: -4px -6px 14px;
              padding: 6px 10px;
              border-radius: 6px;
              background: var(--ink2);
              display: flex;
              justify-content: space-between;
            }
            .file-header span:first-child { text-transform: uppercase; }
            .file-header span:last-child { font-family: var(--font-mono); }
            pre {
              margin: 0;
              background: transparent !important;
            }
            code {
              font-family: var(--font-mono);
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
              background: var(--ink2) !important;
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
    /// from a CDN (falls back to plain-text display when offline). The reading
    /// column follows Figma `18 · Content Viewer / Markdown`; `documentTop`
    /// leaves room for the content windows' floating find card.
    static func wrapMarkdownInHTML(_ markdown: String, documentTop: Int = 40) -> String {
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
            /* Reading theme follows Glance's theme tokens, not the system appearance. */
            \(ContentChrome.rootCSS)
            * { box-sizing: border-box; }
            html { -webkit-text-size-adjust: 100%; background: var(--ink1); }
            body {
              font-family: var(--font-ui);
              font-size: 15px;
              line-height: 26px;
              color: var(--text2);
              background: var(--ink1);
              max-width: 688px;
              margin: 0 auto;
              padding: \(documentTop)px 24px 64px;
              -webkit-font-smoothing: antialiased;
            }
            ::selection { background: var(--selection); }
            #rendered > :first-child { margin-top: 0; }
            h1, h2, h3, h4, h5, h6 { color: var(--text1); margin: 32px 0 12px; }
            h1 {
              font-family: var(--font-title);
              font-size: 34px; line-height: 44px; font-weight: 400;
            }
            h2 { font-size: 16px; line-height: 22px; font-weight: 500; }
            h3 { font-size: 15px; line-height: 22px; font-weight: 500; }
            h4, h5, h6 { font-size: 14px; line-height: 20px; font-weight: 500; color: var(--text2); }
            p, ul, ol, blockquote, table, pre { margin: 0 0 12px; }
            ul, ol { padding-left: 1.4em; }
            li { margin: 4px 0; }
            li::marker { color: var(--text3); }
            strong, b { color: var(--text1); font-weight: 600; }
            blockquote {
              border-left: 2px solid var(--line-strong);
              padding: 0 0 0 16px;
              color: var(--text3);
            }
            hr { border: none; border-top: 1px solid var(--line); margin: 32px 0; }
            code {
              font-family: var(--font-mono);
              font-size: 0.86em;
              color: var(--text1);
              background: var(--ink2);
              padding: 0.1em 0.35em;
              border-radius: 4px;
            }
            pre {
              background: var(--ink2);
              padding: 13px 18px;
              border-radius: 6px;
              white-space: pre-wrap; word-wrap: break-word;
              overflow-x: auto;
            }
            pre code {
              background: transparent; padding: 0; border-radius: 0;
              font-size: 12.5px; line-height: 22px; color: var(--text1);
            }
            img { max-width: 100%; height: auto; border-radius: 3px; }
            a { color: var(--ai); text-decoration: none; }
            a:hover { text-decoration: underline; }
            table { border-collapse: collapse; width: 100%; font-size: 13px; line-height: 17px; }
            th, td {
              height: 36px; padding: 0 16px 0 0; text-align: left; vertical-align: middle;
              border-bottom: 1px solid var(--line);
            }
            th { color: var(--text3); font-size: 12px; font-weight: 500; border-bottom-color: var(--line-strong); }
            td:first-child { color: var(--text1); }
            td:first-child code { background: transparent; padding: 0; font-size: 12px; }
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

// MARK: - 静 Shizuka content chrome

/// Shared geometry, tokens and builders for the content surfaces: Figma
/// `18 · Content Viewer / Markdown` and `19 · Content Viewer / Git Diff`.
/// Used by ContentViewerWindow, ContentPanel and its Git diff window.
enum ContentChrome {
    static let titlebarHeight: CGFloat = 44
    static let statusHeight: CGFloat = 32
    static let findBarSize = NSSize(width: 254, height: 40)
    /// Figma find card: 24 pt from the right edge, 56 pt below the window top.
    static let findBarRight: CGFloat = 24
    static let findBarTop: CGFloat = 56
    /// Figma document top (y 120) minus the 44 pt titlebar.
    static let documentTop = 76

    static let window = PanelStyle.surface                                   // ink/1
    static let card = PanelStyle.overlay                                     // ink/2
    static let segmentActive = PanelStyle.surfaceElevated                    // ink/4
    static let line = PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line)
    static let text4 = PanelStyle.themed(PanelStyle.Sumi.text4, PanelStyle.Washi.text4)

    static func findBarOrigin(in bounds: NSRect) -> NSPoint {
        NSPoint(x: bounds.width - findBarRight - findBarSize.width,
                y: bounds.height - findBarTop - findBarSize.height)
    }

    static func paint(_ view: NSView, _ color: NSColor) {
        view.wantsLayer = true
        view.layer?.backgroundColor = PanelStyle.resolvedCG(color)
    }

    /// The red / yellow / green buttons are drawn by `ContentTitlebarView` so
    /// they sit centred in the 44 pt titlebar.
    static func hideSystemTrafficLights(of window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    /// 28 pt borderless SF Symbol button (Figma `IconButton`).
    static func makeIconButton(symbol: String, tooltip: String,
                               target: AnyObject?, action: Selector) -> NSButton {
        let btn = PanelStyle.makeIconButton(symbol: symbol, tooltip: tooltip, target: target, action: action)
        btn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        btn.contentTintColor = PanelStyle.textSecondary
        btn.setAccessibilityLabel(tooltip)
        return btn
    }

    static func makeLabel(font: NSFont, color: NSColor, alignment: NSTextAlignment = .left,
                          truncation: NSLineBreakMode = .byTruncatingTail) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = truncation
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        return label
    }

    static func styleAddressBar(_ field: NSTextField) {
        field.font = PanelStyle.inspectFont(ofSize: 12)
        field.alignment = .center
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = card
        field.textColor = PanelStyle.textSecondary
        field.wantsLayer = true
        field.layer?.cornerRadius = PanelStyle.Radius.control
        field.layer?.masksToBounds = true
    }

    /// Lay out the titlebar's trailing controls right-to-left — 28 pt icons at
    /// the edge, then the segment group — and return the group's min x.
    @discardableResult
    static func layoutTrailingControls(in bar: NSView, icons: [NSButton],
                                       group: ContentSegmentGroup,
                                       segments: [(ContentSegmentButton, CGFloat)]) -> CGFloat {
        var right = bar.bounds.width - 20
        for icon in icons where !icon.isHidden {
            icon.frame = NSRect(x: right - 28, y: 8, width: 28, height: 28)
            right -= 28 + 4
        }
        if right < bar.bounds.width - 20 { right -= 4 }
        let width = group.arrange(segments)
        group.isHidden = width == 0
        group.frame = NSRect(x: right - width, y: 8, width: width, height: 27)
        return width == 0 ? right : group.frame.minX
    }

    /// Path shown in the status bar: `~`-abbreviated for files, the URL otherwise.
    static func statusPath(for url: URL) -> String {
        url.isFileURL ? (url.path as NSString).abbreviatingWithTildeInPath : url.absoluteString
    }

    /// "Markdown · 4 KB · Modified <date>" for the status bar's right side.
    static func statusDetail(for url: URL, kindLabel: String) -> String {
        var parts: [String] = []
        if !kindLabel.isEmpty { parts.append(kindLabel) }
        if url.isFileURL,
           let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber {
            let f = ByteCountFormatter()
            f.countStyle = .file
            parts.append(f.string(fromByteCount: size.int64Value))
        }
        if let date = ContentViewerWindow.modificationDate(for: url) {
            parts.append("Modified ".localized + ContentViewerWindow.friendlyDate(date))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: CSS

    static func css(_ color: NSColor, alpha: CGFloat? = nil) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "rgba(%ld,%ld,%ld,%.3f)",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()),
                      alpha ?? c.alphaComponent)
    }

    /// Theme tokens for Glance-owned HTML documents (Sumi on dark, Washi on light).
    static let rootCSS: String = {
        typealias S = PanelStyle.Sumi
        typealias W = PanelStyle.Washi
        let t = { (dark: NSColor, light: NSColor) in css(PanelStyle.themed(dark, light)) }
        return """
        :root {
          color-scheme: \(PanelStyle.isLight ? "light" : "dark");
          --ink0: \(t(S.ink0, W.ink0));
          --ink1: \(t(S.ink1, W.ink1));
          --ink2: \(t(S.ink2, W.ink2));
          --ink3: \(t(S.ink3, W.ink3));
          --ink4: \(t(S.ink4, W.ink4));
          --line: \(t(S.line, W.line));
          --line-strong: \(t(S.lineStrong, W.lineStrong));
          --text1: \(t(S.text1, W.text1));
          --text2: \(t(S.text2, W.text2));
          --text3: \(t(S.text3, W.text3));
          --text4: \(t(S.text4, W.text4));
          --shu: \(t(S.shu, W.shu));
          --moss: \(t(S.moss, W.moss));
          --ai: \(t(S.ai, W.ai));
          --selection: \(css(PanelStyle.contrast, alpha: PanelStyle.isLight ? 0.12 : 0.18));
          --font-ui: "Inter", -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
          --font-title: "Hiragino Mincho ProN", "Hiragino Mincho Pro", serif;
          --font-mono: ui-monospace, "SF Mono", Menlo, monospace;
        }
        """
    }()
}

/// 44 pt titlebar: traffic lights at (20, 16), a centred title, and room for
/// trailing controls. Dragging it moves the window; double-click zooms.
final class ContentTitlebarView: NSView {
    let titleLabel = ContentChrome.makeLabel(font: PanelStyle.inspectFont(ofSize: 13, weight: .medium),
                                             color: PanelStyle.textSecondary,
                                             alignment: .center, truncation: .byTruncatingMiddle)
    var onResize: (() -> Void)?
    var onMouseDown: (() -> Void)?

    private lazy var lights: [TrafficLightButton] = [
        TrafficLightButton(color: NSColor(srgbRed: 237 / 255, green: 106 / 255, blue: 94 / 255, alpha: 1),
                           target: self, action: #selector(closeTapped)),
        TrafficLightButton(color: NSColor(srgbRed: 244 / 255, green: 191 / 255, blue: 79 / 255, alpha: 1),
                           target: self, action: #selector(minimizeTapped)),
        TrafficLightButton(color: NSColor(srgbRed: 97 / 255, green: 197 / 255, blue: 84 / 255, alpha: 1),
                           target: self, action: #selector(zoomTapped)),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        ContentChrome.paint(self, ContentChrome.window)
        for (index, light) in lights.enumerated() {
            light.frame = NSRect(x: 20 + CGFloat(index) * 20, y: 16, width: 12, height: 12)
            light.autoresizingMask = [.minYMargin]
            addSubview(light)
        }
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }

    /// Centre `view` on the titlebar, clear of the traffic lights and of
    /// anything right of `rightLimit`. Titles use the Figma 16 pt text frame at
    /// y 14; the web address field is a 26 pt control.
    func centerTitle(_ view: NSView, rightLimit: CGFloat) {
        let mid = bounds.midX
        let half = max(20, min(mid - 84, rightLimit - mid))
        if view === titleLabel {
            titleLabel.frame = NSRect(x: mid - half, y: 14, width: half * 2, height: 16)
        } else {
            let width = min(half * 2, 560)
            view.frame = NSRect(x: mid - width / 2, y: 9, width: width, height: 26)
        }
    }

    func applyTheme() {
        ContentChrome.paint(self, ContentChrome.window)
    }

    @objc private func closeTapped() { window?.close() }
    @objc private func minimizeTapped() { window?.miniaturize(nil) }
    @objc private func zoomTapped() { window?.zoom(nil) }
}

/// Figma `segmented`: an ink/2 well (radius 6) holding 23 pt segments.
final class ContentSegmentGroup: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Place visible segments left-to-right with 2 pt insets; returns the width.
    func arrange(_ segments: [(ContentSegmentButton, CGFloat)]) -> CGFloat {
        var x: CGFloat = 2
        var any = false
        for (button, width) in segments where !button.isHidden {
            button.frame = NSRect(x: x, y: 2, width: width, height: 23)
            x += width + 2
            any = true
        }
        return any ? x : 0
    }

    func applyTheme() {
        layer?.backgroundColor = PanelStyle.resolvedCG(ContentChrome.card)
    }
}

/// A text segment in the titlebar group (and the find card's Done). Active
/// segments sit on ink/4 with text/1; resting ones are text/3 on the well.
final class ContentSegmentButton: NSButton {
    var text: String { didSet { refresh() } }
    var isActive = false { didSet { refresh() } }
    /// Lit like an active segment whenever clickable (Save once dirty).
    var activatesWhenEnabled = false { didSet { refresh() } }
    var restingColor = PanelStyle.textTertiary { didSet { refresh() } }
    override var isEnabled: Bool { didSet { refresh() } }

    static let font = PanelStyle.inspectFont(ofSize: 12)
    private var hovering = false
    private var tracking: NSTrackingArea?

    init(text: String, target: AnyObject? = nil, action: Selector? = nil) {
        self.text = text
        super.init(frame: .zero)
        cell = ContentCenteredButtonCell(textCell: text)
        self.target = target
        self.action = action
        bezelStyle = .recessed
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 4
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Figma segments pad their label by 10 pt each side; size for the widest text.
    static func width(for texts: [String]) -> CGFloat {
        let widest = texts.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(widest) + 20
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

    override func mouseEntered(with event: NSEvent) { hovering = true; refresh() }
    override func mouseExited(with event: NSEvent) { hovering = false; refresh() }

    private func refresh() {
        let lit = isActive || (activatesWhenEnabled && isEnabled)
        let fill: NSColor
        if lit { fill = ContentChrome.segmentActive }
        else if hovering && isEnabled { fill = PanelStyle.controlFill }
        else { fill = .clear }
        layer?.backgroundColor = PanelStyle.resolvedCG(fill)
        let color: NSColor
        if !isEnabled { color = ContentChrome.text4 }
        else if lit { color = PanelStyle.textPrimary }
        else if hovering { color = PanelStyle.textSecondary }
        else { color = restingColor }
        attributedTitle = NSAttributedString(string: text,
                                             attributes: [.font: Self.font, .foregroundColor: color])
        setAccessibilityLabel(text)
    }
}

private final class ContentCenteredButtonCell: NSButtonCell {
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let textHeight = min(frame.height, ceil(title.size().height))
        let centered = NSRect(x: frame.minX, y: frame.midY - textHeight / 2,
                              width: frame.width, height: textHeight)
        return super.drawTitle(title, withFrame: centered, in: controlView)
    }
}

/// Figma `find in page`: a 254 × 40 ink/2 card with a hairline edge holding
/// the query, a mono match count, previous / next and Done.
final class ContentFindBar: NSView {
    let field = NSTextField()
    let countLabel = ContentChrome.makeLabel(font: PanelStyle.monoFont(ofSize: 11),
                                             color: PanelStyle.textTertiary)
    private let icon = NSImageView()
    private let doneButton: ContentSegmentButton

    init(target: AnyObject, previous: Selector, next: Selector, done: Selector) {
        doneButton = ContentSegmentButton(text: "Done".localized, target: target, action: done)
        super.init(frame: NSRect(origin: .zero, size: ContentChrome.findBarSize))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        icon.contentTintColor = PanelStyle.textTertiary
        icon.frame = NSRect(x: 13, y: 12, width: 16, height: 16)
        addSubview(icon)

        field.font = PanelStyle.inspectFont(ofSize: 13)
        field.textColor = PanelStyle.textPrimary
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(
            string: "Find in page".localized,
            attributes: [.font: PanelStyle.inspectFont(ofSize: 13), .foregroundColor: PanelStyle.textTertiary])
        field.setAccessibilityLabel("Find in page".localized)
        field.frame = NSRect(x: 39, y: 12, width: 55, height: 16)
        addSubview(field)

        countLabel.frame = NSRect(x: 98, y: 13, width: 40, height: 14)
        addSubview(countLabel)

        let prev = ContentChrome.makeIconButton(symbol: "chevron.up", tooltip: "Previous match".localized,
                                                target: target, action: previous)
        prev.frame = NSRect(x: 141, y: 6, width: 28, height: 28)
        addSubview(prev)
        let nextButton = ContentChrome.makeIconButton(symbol: "chevron.down", tooltip: "Next match".localized,
                                                      target: target, action: next)
        nextButton.frame = NSRect(x: 177, y: 6, width: 28, height: 28)
        addSubview(nextButton)

        doneButton.restingColor = PanelStyle.textSecondary
        doneButton.frame = NSRect(x: 209, y: 6, width: 42, height: 28)
        addSubview(doneButton)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyTheme() {
        layer?.backgroundColor = PanelStyle.resolvedCG(ContentChrome.card)
        layer?.borderColor = PanelStyle.resolvedCG(ContentChrome.line)
    }
}

/// 32 pt status bar: a hairline on top, a mono path on the left and Inter
/// metadata on the right (Figma `status`).
final class ContentStatusBar: NSView {
    let leftLabel = ContentChrome.makeLabel(font: PanelStyle.monoFont(ofSize: 11),
                                            color: PanelStyle.textTertiary, truncation: .byTruncatingHead)
    let rightLabel = ContentChrome.makeLabel(font: PanelStyle.inspectFont(ofSize: 12),
                                             color: PanelStyle.textTertiary, alignment: .right)
    private let rule = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(rule)
        addSubview(leftLabel)
        addSubview(rightLabel)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(left: String, right: String, leftToolTip: String?) {
        leftLabel.stringValue = left
        leftLabel.toolTip = leftToolTip
        rightLabel.stringValue = right
        layoutLabels()
    }

    /// Diff status: a styled left run (count + path) instead of a plain path.
    func show(attributedLeft: NSAttributedString, right: String) {
        leftLabel.attributedStringValue = attributedLeft
        leftLabel.toolTip = nil
        rightLabel.stringValue = right
        layoutLabels()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLabels()
    }

    /// Text frames from Figma: left x 20 / y 10 / h 14, right ends 20 pt from
    /// the edge at y 9 / h 15 (top-origin, converted for the 32 pt bar).
    private func layoutLabels() {
        let h = bounds.height
        rule.frame = NSRect(x: 0, y: h - 1, width: bounds.width, height: 1)
        let rightWidth = min(ceil(rightLabel.attributedStringValue.size().width) + 4,
                             max(0, bounds.width / 2 - 20))
        rightLabel.frame = NSRect(x: bounds.width - 20 - rightWidth, y: h - 9 - 15, width: rightWidth, height: 15)
        let leftRight = rightWidth > 0 ? rightLabel.frame.minX - 16 : bounds.width - 20
        leftLabel.frame = NSRect(x: 20, y: h - 10 - 14, width: max(0, leftRight - 20), height: 14)
    }

    func applyTheme() {
        ContentChrome.paint(self, ContentChrome.window)
        ContentChrome.paint(rule, ContentChrome.line)
    }
}
