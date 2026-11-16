import AppKit
import WebKit
import Highlightr

/// Content window docked beside PreviewPanel. Layout follows Figma
/// `18 · Content Viewer / Markdown`: a 44 pt titlebar (traffic lights, centred
/// title, action segments + icons), the body, and a 32 pt status bar.
final class ContentPanel: NSWindow, NSTextFieldDelegate, NSTextViewDelegate, WKNavigationDelegate {
    static let shared = ContentPanel()

    private let webView: WKWebView
    private let textView: NSTextView
    private let textScroll: NSScrollView
    private let imageView: ImageFillView
    private let titlebar = ContentTitlebarView()
    private let actionGroup = ContentSegmentGroup()
    private let saveButton = ContentSegmentButton(text: "Save".localized)
    private var findButton = NSButton()     // toggles the find bar
    private let gitDiffButton = ContentSegmentButton(text: "Diff".localized)
    private var locateButton = NSButton()   // Reveal in Finder, local-only
    private let statusBar = ContentStatusBar()  // path · kind · size · modified
    private let addressBar = NSTextField()

    private lazy var webFindBar = ContentFindBar(target: self,
                                                 previous: #selector(webFindPrev(_:)),
                                                 next: #selector(webFindNext(_:)),
                                                 done: #selector(hideWebFindBar))
    private var webFindField: NSTextField { webFindBar.field }
    private var webFindCountLabel: NSTextField { webFindBar.countLabel }
    private var webFindMatchCount = 0
    private var webFindCurrentIndex = -1

    private enum Kind { case webpage, markdown, text, pdf, image }
    private var kind: Kind = .webpage
    private var currentURL: URL?
    private var currentMediaInfo: MediaInfo?
    private var currentGitContext: GitDiffService.Context?
    private var gitDiffLookupID = UUID()
    private var gitDiffWindows: [GitDiffWindow] = []
    /// True once the editable text view has unsaved user edits.
    private var isDirty: Bool = false

    private weak var loadingOverlay: NSView?
    private weak var loadingIndicator: FocusSweepLoadingView?
    private weak var loadFailedView: LoadFailedAnimationView?

    private(set) var hasBeenManuallyMoved: Bool = false
    private var escapeLocalMonitor: Any?
    private var escapeGlobalMonitor: Any?
    private var zoomMonitor: Any?

    private var currentZoomLevel: CGFloat = 1.0
    private let minZoomLevel: CGFloat = 0.25
    private let maxZoomLevel: CGFloat = 5.0
    private let zoomStep: CGFloat = 1.1


    private init() {
        let config = WKWebViewConfiguration()
        PanelStyle.styleWebScrollbars(in: config)
        let findScript = WKUserScript(
            source: ContentViewerWindow.findHelperJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(findScript)
        webView = WKWebView(frame: .zero, configuration: config)

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

        let iv = ImageFillView(frame: .zero)
        iv.isHidden = true
        imageView = iv

        let initialFrame = ScreenManager.shared.contentFrame(for: NSSize(width: 652.0, height: 962.0))
        super.init(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false

        title = "Glance".localized
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        // Commit the whole window to Glance's theme so it matches PreviewPanel
        // regardless of the system theme. The custom 44 pt titlebar draws the
        // traffic lights; the system title and buttons stay hidden.
        appearance = PanelStyle.windowAppearance
        backgroundColor = ContentChrome.window
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        ContentChrome.hideSystemTrafficLights(of: self)

        buildLayout()
        showWebView()
        installEscapeKeyMonitors()
        installZoomMonitor()
        observeThemeChanges()

        // The red close button bypasses dismiss()/cancelOperation — stop any
        // in-page media so audio doesn't keep playing after the window closes.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.stopWebMedia()
            NotificationCenter.default.post(name: .init("ContentPanelDidClose"), object: self)
        }
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
        // Keep the docked window fully on-screen even when the preview sits near
        // a screen edge.
        setFrame(ScreenManager.shared.clampedToVisible(newFrame), display: true)
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
            return NSSize(width: 720.0, height: 960.0)
        case .text:
            return NSSize(width: 720.0, height: 960.0)
        case .markdown:
            return NSSize(width: 720.0, height: 960.0)
        case .pdf:
            return NSSize(width: 720.0, height: 960.0)
        case .image:
            return NSSize(width: 652.0, height: 962.0)
        }
    }

    private static func windowSize(for mediaKind: MediaInfo.Kind) -> NSSize {
        switch mediaKind {
        case .text:     return NSSize(width: 720.0, height: 960.0)
        case .markdown: return NSSize(width: 720.0, height: 960.0)
        case .pdf:      return NSSize(width: 720.0, height: 960.0)
        default:        return NSSize(width: 970.0, height: 990.0)
        }
    }

    private static func calculateImageWindowSize(imageSize: CGSize) -> NSSize {
        let maxWindowWidth: CGFloat = 1200
        let maxWindowHeight: CGFloat = 900
        let minWindowWidth: CGFloat = 300
        let minWindowHeight: CGFloat = 200
        // Titlebar + status bar around the image.
        let extraHeight: CGFloat = ContentChrome.titlebarHeight + ContentChrome.statusHeight

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
        imageView.resetPan()
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
        // Solid ink/1 base, shared by the titlebar, body and status bar.
        ContentChrome.paint(root, ContentChrome.window)
        let bounds = root.bounds
        let titleH = ContentChrome.titlebarHeight
        let statusH = ContentChrome.statusHeight

        titlebar.frame = NSRect(x: 0, y: bounds.height - titleH, width: bounds.width, height: titleH)
        titlebar.autoresizingMask = [.width, .minYMargin]
        titlebar.onResize = { [weak self] in self?.layoutToolbarButtons() }
        // Clicking the chrome counts as taking the window over from PreviewPanel.
        titlebar.onMouseDown = { [weak self] in self?.hasBeenManuallyMoved = true }

        // Address bar replaces the centred title for web pages.
        ContentChrome.styleAddressBar(addressBar)
        addressBar.isEditable = false
        addressBar.isHidden = true
        titlebar.addSubview(addressBar)

        // ── Actions (right): Save + Diff segments, then Find / Locate icons ──
        findButton = ContentChrome.makeIconButton(symbol: "magnifyingglass",
                                                  tooltip: "Find in page".localized,
                                                  target: self, action: #selector(findTapped))
        titlebar.addSubview(findButton)

        locateButton = ContentChrome.makeIconButton(symbol: "folder",
                                                    tooltip: "Reveal in Finder".localized,
                                                    target: self, action: #selector(locateTapped))
        locateButton.isHidden = true
        titlebar.addSubview(locateButton)

        gitDiffButton.target = self
        gitDiffButton.action = #selector(gitDiffTapped)
        gitDiffButton.toolTip = "Compare with Git".localized
        gitDiffButton.isHidden = true
        actionGroup.addSubview(gitDiffButton)

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

        let contentFrame = NSRect(x: 0, y: statusH, width: bounds.width,
                                  height: bounds.height - titleH - statusH)
        webView.frame = contentFrame
        webView.autoresizingMask = [.width, .height]
        root.addSubview(webView)

        imageView.frame = contentFrame
        imageView.autoresizingMask = [.width, .height]
        root.addSubview(imageView)

        textScroll.frame = contentFrame
        textScroll.autoresizingMask = [.width, .height]
        textScroll.drawsBackground = false
        textView.textContainer?.containerSize = NSSize(
            width: contentFrame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        root.addSubview(textScroll)

        let overlay = NSView(frame: contentFrame)
        ContentChrome.paint(overlay, ContentChrome.window)
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true

        let loadingIndicator = FocusSweepLoadingView(frame: NSRect(
            x: (contentFrame.width - FocusSweepLoadingView.preferredSize.width) / 2,
            y: (contentFrame.height - FocusSweepLoadingView.preferredSize.height) / 2 + 10,
            width: FocusSweepLoadingView.preferredSize.width,
            height: FocusSweepLoadingView.preferredSize.height
        ))
        loadingIndicator.autoresizingMask = [.minXMargin, .minYMargin, .maxXMargin, .maxYMargin]
        overlay.addSubview(loadingIndicator)

        let loadFailedView = LoadFailedAnimationView(frame: NSRect(
            x: (contentFrame.width - LoadFailedAnimationView.preferredSize.width) / 2,
            y: (contentFrame.height - LoadFailedAnimationView.preferredSize.height) / 2 + 12,
            width: LoadFailedAnimationView.preferredSize.width,
            height: LoadFailedAnimationView.preferredSize.height
        ))
        loadFailedView.autoresizingMask = [.minXMargin, .minYMargin, .maxXMargin, .maxYMargin]
        loadFailedView.isHidden = true
        overlay.addSubview(loadFailedView)

        root.addSubview(overlay)
        loadingOverlay = overlay
        self.loadingIndicator = loadingIndicator
        self.loadFailedView = loadFailedView

        // ─── Web find card (floats over the top-right of the document) ───
        webFindBar.frame = NSRect(origin: ContentChrome.findBarOrigin(in: bounds),
                                  size: ContentChrome.findBarSize)
        webFindBar.autoresizingMask = [.minXMargin, .minYMargin]
        webFindBar.isHidden = true
        webFindField.delegate = self
        root.addSubview(webFindBar)

        statusBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: statusH)
        statusBar.autoresizingMask = [.width, .maxYMargin]
        root.addSubview(statusBar)

        root.addSubview(titlebar)
        contentView = root
        layoutToolbarButtons()
    }

    /// Pack the right action group (icons, then the Save + Diff segments)
    /// right-to-left, hidden ones collapsing, then centre the title / address
    /// bar in the remaining space.
    private func layoutToolbarButtons() {
        let groupMinX = ContentChrome.layoutTrailingControls(
            in: titlebar,
            icons: [locateButton, findButton],
            group: actionGroup,
            segments: [
                (saveButton, ContentSegmentButton.width(for: ["Save".localized, "Saved ✓".localized])),
                (gitDiffButton, ContentSegmentButton.width(for: ["Diff".localized, "..."])),
            ]
        )
        titlebar.centerTitle(addressBar.isHidden ? titlebar.titleLabel : addressBar,
                             rightLimit: groupMinX - 12)
    }

    func dismiss() {
        stopWebMedia()
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        stopWebMedia()
        orderOut(nil)
        NotificationCenter.default.post(name: .init("ContentPanelDidClose"), object: self)
    }

    /// Pause in-page audio/video and halt loading so a dismissed panel (e.g.
    /// a direct mp4 URL rendered by WKWebView) doesn't keep playing sound in
    /// the background. The webView itself is reused across loads.
    private func stopWebMedia() {
        webView.stopLoading()
        webView.evaluateJavaScript(
            "document.querySelectorAll('video,audio').forEach(function(m){ m.pause(); })",
            completionHandler: nil
        )
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
            locateButton.isHidden = !info.url.isFileURL
            showFileIdentity(for: info.url)
            refreshSaveButton()
            refreshGitDiffAvailability(for: info.url)
            renderMarkdownView(url: info.url)
        case .text:
            currentURL = info.url
            kind = .text
            locateButton.isHidden = !info.url.isFileURL
            showFileIdentity(for: info.url)
            refreshGitDiffAvailability(for: info.url)
            loadEditableText(url: info.url)
        case .pdf:
            currentURL = info.url
            kind = .pdf
            locateButton.isHidden = !info.url.isFileURL
            showFileIdentity(for: info.url)
            refreshSaveButton()
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
            locateButton.isHidden = !info.url.isFileURL
            showFileIdentity(for: info.url)
            refreshSaveButton()
            updateImageInfoBar(with: info)
            let imageURL = info.url
            if imageURL.isFileURL {
                // Local files decode from disk fast enough to stay synchronous.
                applyLoadedImage(NSImage(contentsOf: imageURL), for: imageURL)
            } else {
                // Remote URLs: NSImage(contentsOf:) downloads synchronously, so
                // run it off the main thread — otherwise the panel freezes until
                // the whole image arrives. The loading overlay (shown above)
                // stays up meanwhile.
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let image = NSImage(contentsOf: imageURL)
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        // The user may have navigated to another item while the
                        // download was in flight — only apply if still current.
                        guard self.currentURL == imageURL else { return }
                        self.applyLoadedImage(image, for: imageURL)
                    }
                }
            }
        default:
            currentURL = info.url
            kind = .webpage
            locateButton.isHidden = !info.url.isFileURL
            showAddressBarIdentity(for: info.url)
            refreshSaveButton()
            webView.load(URLRequest(url: info.url))
            showWebView()
        }
        layoutToolbarButtons()
    }

    /// Display a decoded image (native NSImageView path), or fall back to a
    /// WebKit <img> render when decoding failed. Sizes the window to the image
    /// and clears the loading overlay. Safe to call from the main thread only.
    private func applyLoadedImage(_ image: NSImage?, for url: URL) {
        if let image = image {
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
                   background: \(ContentChrome.css(PanelStyle.canvas)); height: 100vh; overflow: hidden; }
            img { max-width: 100%; max-height: 100%; object-fit: contain; }
            </style></head><body><img src="\(url.absoluteString)"></body></html>
            """
            let baseURL = url.isFileURL ? url.deletingLastPathComponent() : nil
            webView.loadHTMLString(html, baseURL: baseURL)
            showWebView()
            // Keep the shared loader visible until WebKit reports that the
            // fallback remote image document has finished.
            return
        }
        hideLoading()
    }

    private func showLoading() {
        loadingOverlay?.isHidden = false
        loadFailedView?.isHidden = true
        loadingIndicator?.setLoading(true)
    }

    private func hideLoading() {
        loadingOverlay?.isHidden = true
        loadingIndicator?.setLoading(false)
        loadFailedView?.isHidden = true
    }

    private func showLoadFailed() {
        loadingOverlay?.isHidden = false
        loadingIndicator?.setLoading(false)
        loadFailedView?.isHidden = false
    }

    private func renderMarkdownView(url: URL) {
        Task.detached { [weak self] in
            let raw = await ContentViewerWindow.fetchTextContent(from: url)
            let html = ContentViewerWindow.wrapMarkdownInHTML(raw, documentTop: ContentChrome.documentTop)
            await MainActor.run {
                self?.webView.loadHTMLString(html, baseURL: url)
                self?.showWebView()
                self?.hideLoading()
            }
        }
    }

    /// Load raw file/URL text into the editable text view. Assigning
    /// `textView.string` does not fire `textDidChange`, so the buffer starts
    /// clean (isDirty = false) until the user actually types.
    private func loadEditableText(url: URL) {
        isDirty = false
        Task.detached { [weak self] in
            let raw = await ContentViewerWindow.fetchTextContent(from: url)
            await MainActor.run {
                guard let self = self else { return }
                (self.textView.textStorage as? CodeAttributedString)?.language = ContentViewerWindow.hljsLanguage(for: url)
                self.textView.string = raw
                self.isDirty = false
                self.showTextView()
                self.hideLoading()
                self.refreshSaveButton()
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
        addressBar.isEditable = true
        addressBar.target = self
        addressBar.action = #selector(addressBarSubmitted)
        statusBar.show(left: "", right: "", leftToolTip: nil)
    }

    /// Save is always visible; only clickable for a dirty, local, editable file.
    private func refreshSaveButton() {
        saveButton.isHidden = false
        let editable = (kind == .text) && (currentURL?.isFileURL ?? false)
        saveButton.isEnabled = editable && isDirty
    }

    @objc private func findTapped() {
        if !webView.isHidden {
            showWebFindBar()
        } else if !textScroll.isHidden {
            invokeTextFinder(.showFindInterface)
        }
    }

    @objc private func gitDiffTapped() {
        guard let context = currentGitContext else { return }
        gitDiffButton.isEnabled = false
        gitDiffButton.text = "..."

        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = GitDiffService.makeSnapshot(for: context)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.gitDiffButton.isEnabled = true
                self.gitDiffButton.text = "Diff".localized

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

    private func resetGitDiffAvailability() {
        gitDiffLookupID = UUID()
        currentGitContext = nil
        gitDiffButton.isHidden = true
        gitDiffButton.isEnabled = true
        gitDiffButton.text = "Diff".localized
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

    /// Image metadata (format · size · dimensions) on the status bar's right;
    /// the filename is the window title.
    private func updateImageInfoBar(with info: MediaInfo) {
        var parts: [String] = []
        if info.formatName.isDisplayableValue {
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
        statusBar.show(left: ContentChrome.statusPath(for: info.url),
                       right: parts.joined(separator: " · "),
                       leftToolTip: info.url.isFileURL ? info.url.path : info.url.absoluteString)
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
        // Theme tokens are fixed for the session (a theme change relaunches), so
        // a preferences change only re-asserts the layer colour snapshots.
        guard let root = contentView else { return }
        ContentChrome.paint(root, ContentChrome.window)
        if let loadingOverlay { ContentChrome.paint(loadingOverlay, ContentChrome.window) }
        titlebar.applyTheme()
        actionGroup.applyTheme()
        statusBar.applyTheme()
        webFindBar.applyTheme()
    }


}

extension ContentPanel {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadFailed()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadFailed()
    }
}

private final class ImageFillView: NSView {
    var image: NSImage? {
        didSet {
            imageLayer.contents = image
        }
    }

    private let imageLayer = CALayer()
    private var panOffset = CGPoint.zero
    private var lastMouseLocation = CGPoint.zero
    private var currentZoom: CGFloat = 1.0
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.canvas.cgColor
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
        currentZoom = zoom
        applyTransform()
    }

    func resetPan() {
        panOffset = .zero
        applyTransform()
    }

    override func mouseDown(with event: NSEvent) {
        guard currentZoom > 1.0 else {
            super.mouseDown(with: event)
            return
        }
        isDragging = true
        lastMouseLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, currentZoom > 1.0 else { return }
        let loc = event.locationInWindow
        let delta = CGPoint(x: loc.x - lastMouseLocation.x, y: loc.y - lastMouseLocation.y)
        panOffset.x += delta.x
        panOffset.y += delta.y
        lastMouseLocation = loc
        constrainPan()
        applyTransform()
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    override func scrollWheel(with event: NSEvent) {
        guard currentZoom > 1.0 else {
            super.scrollWheel(with: event)
            return
        }
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        guard abs(deltaX) > 0 || abs(deltaY) > 0 else { return }
        panOffset.x -= deltaX
        panOffset.y -= deltaY
        constrainPan()
        applyTransform()
    }

    private func applyTransform() {
        var transform = CATransform3DIdentity
        transform = CATransform3DScale(transform, currentZoom, currentZoom, 1)
        transform = CATransform3DTranslate(transform, panOffset.x, panOffset.y, 0)
        imageLayer.transform = transform
    }

    private func constrainPan() {
        guard currentZoom > 1.0, let image = image else { return }

        let viewSize = bounds.size
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return }

        // Compute the aspect-fitted rendered size (same logic as resizeAspect)
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let renderedWidth = imageSize.width * scale
        let renderedHeight = imageSize.height * scale

        // After zoom, the rendered image dimensions
        let scaledWidth = renderedWidth * currentZoom
        let scaledHeight = renderedHeight * currentZoom

        // Max pan in each direction: half the overflow
        let maxPanX = max(0, (scaledWidth - viewSize.width) / 2)
        let maxPanY = max(0, (scaledHeight - viewSize.height) / 2)

        panOffset.x = max(-maxPanX, min(maxPanX, panOffset.x))
        panOffset.y = max(-maxPanY, min(maxPanY, panOffset.y))
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
                            beforeTitle: "\(columnTitle("Before - HEAD".localized).label) - \(shortHash(beforeRev))",
                            afterTitle: "\(columnTitle("After - Working Tree".localized).label) - \(shortHash(afterRev))",
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

    /// Split a "Before - HEAD" style column title into its label and the
    /// revision / tree meta shown beside it in mono.
    static func columnTitle(_ title: String) -> (label: String, meta: String) {
        guard let range = title.range(of: " - ") else { return (title, "") }
        return (String(title[..<range.lowerBound]), String(title[range.upperBound...]))
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
        #if MAS
        // Sandboxed apps can't run the developer tools; Git history is not
        // shown in the App Store build.
        return nil
        #else
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
        #endif
    }
}

/// Side-by-side Git diff, laid out after Figma `19 · Content Viewer / Git Diff`:
/// a 44 pt titlebar, a 40 pt Before / After header, two hairline-split code
/// columns with mono line numbers, and a 32 pt status bar.
private final class GitDiffWindow: NSWindow {
    private let leftScroll: NSScrollView
    private let rightScroll: NSScrollView
    private var isSyncingScroll = false
    private let titlebar = ContentTitlebarView()
    private let statusBar = ContentStatusBar()

    init(snapshot: GitDiffService.Snapshot) {
        let diff = Self.makeSideBySideDiff(before: snapshot.beforeText, after: snapshot.afterText)
        leftScroll = Self.makeCodeScroll(attributedText: diff.left)
        rightScroll = Self.makeCodeScroll(attributedText: diff.right)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        title = "Git Diff - \(snapshot.fileURL.lastPathComponent)"
        appearance = PanelStyle.windowAppearance
        backgroundColor = ContentChrome.window
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        ContentChrome.hideSystemTrafficLights(of: self)
        buildLayout(snapshot: snapshot, changedRows: diff.changedRows)
        center()
        installScrollSync()
    }

    private func buildLayout(snapshot: GitDiffService.Snapshot, changedRows: Int) {
        let size = NSSize(width: 1200, height: 760)
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        ContentChrome.paint(root, ContentChrome.window)
        contentView = root
        let w = size.width, h = size.height
        let titleH = ContentChrome.titlebarHeight
        let headerH: CGFloat = 40
        let statusH = ContentChrome.statusHeight
        let bodyH = h - titleH - headerH - statusH

        titlebar.frame = NSRect(x: 0, y: h - titleH, width: w, height: titleH)
        titlebar.autoresizingMask = [.width, .minYMargin]
        titlebar.titleLabel.stringValue = snapshot.fileURL.lastPathComponent
        titlebar.titleLabel.toolTip = snapshot.fileURL.path
        titlebar.onResize = { [weak self] in
            guard let bar = self?.titlebar else { return }
            bar.centerTitle(bar.titleLabel, rightLimit: bar.bounds.width - 20)
        }
        titlebar.centerTitle(titlebar.titleLabel, rightLimit: w - 20)

        let header = NSView(frame: NSRect(x: 0, y: h - titleH - headerH, width: w, height: headerH))
        header.autoresizingMask = [.width, .minYMargin]
        let before = makeColumnHeader(title: snapshot.beforeTitle,
                                      frame: NSRect(x: 0, y: 0, width: w / 2, height: headerH))
        before.autoresizingMask = [.width, .maxXMargin]
        header.addSubview(before)
        let after = makeColumnHeader(title: snapshot.afterTitle,
                                     frame: NSRect(x: w / 2, y: 0, width: w / 2, height: headerH))
        after.autoresizingMask = [.width, .minXMargin]
        header.addSubview(after)
        let headerRule = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 1))
        headerRule.autoresizingMask = [.width]
        ContentChrome.paint(headerRule, ContentChrome.line)
        header.addSubview(headerRule)

        leftScroll.frame = NSRect(x: 0, y: statusH, width: w / 2, height: bodyH)
        leftScroll.autoresizingMask = [.width, .height, .maxXMargin]
        rightScroll.frame = NSRect(x: w / 2, y: statusH, width: w / 2, height: bodyH)
        rightScroll.autoresizingMask = [.width, .height, .minXMargin]
        let divider = NSView(frame: NSRect(x: w / 2, y: statusH, width: 1, height: bodyH))
        divider.autoresizingMask = [.height, .minXMargin, .maxXMargin]
        ContentChrome.paint(divider, ContentChrome.line)

        // "N lines changed" (Figma) followed by the repo-relative path.
        let countText = changedRows == 1
            ? "1 line changed".localized
            : String(format: "%d lines changed".localized, changedRows)
        let left = NSMutableAttributedString(string: countText, attributes: [
            .font: PanelStyle.inspectFont(ofSize: 12), .foregroundColor: PanelStyle.textSecondary])
        left.append(NSAttributedString(string: "   " + snapshot.relativePath, attributes: [
            .font: PanelStyle.monoFont(ofSize: 11), .foregroundColor: PanelStyle.textTertiary]))
        statusBar.frame = NSRect(x: 0, y: 0, width: w, height: statusH)
        statusBar.autoresizingMask = [.width, .maxYMargin]
        statusBar.leftLabel.lineBreakMode = .byTruncatingTail
        statusBar.show(attributedLeft: left, right: "Compare with Git".localized + " · " + snapshot.summary)
        statusBar.leftLabel.toolTip = snapshot.fileURL.path

        for view in [leftScroll, rightScroll, divider, header, statusBar, titlebar] as [NSView] {
            root.addSubview(view)
        }
    }

    /// "Before" in Inter 12 medium, the revision / tree beside it in mono.
    /// Figma text frames: label x 24 / y 12 / h 15, meta 10 pt after / y 12.5 / h 14.
    private func makeColumnHeader(title: String, frame: NSRect) -> NSView {
        let column = NSView(frame: frame)
        let parts = GitDiffService.columnTitle(title)
        let label = ContentChrome.makeLabel(font: PanelStyle.inspectFont(ofSize: 12, weight: .medium),
                                            color: PanelStyle.textPrimary)
        label.stringValue = parts.label
        let labelW = ceil(label.attributedStringValue.size().width) + 2
        label.frame = NSRect(x: 24, y: frame.height - 12 - 15, width: labelW, height: 15)
        column.addSubview(label)

        let meta = ContentChrome.makeLabel(font: PanelStyle.monoFont(ofSize: 11),
                                           color: PanelStyle.textTertiary)
        meta.stringValue = parts.meta
        meta.frame = NSRect(x: label.frame.maxX + 8, y: frame.height - 12.5 - 14,
                            width: max(0, frame.width - label.frame.maxX - 32), height: 14)
        meta.autoresizingMask = [.width]
        column.addSubview(meta)
        return column
    }

    private static func makeCodeScroll(attributedText: NSAttributedString) -> NSScrollView {
        let textView = DiffTextView(frame: .zero)
        textView.font = PanelStyle.monoFont(ofSize: 12)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        // Same ink/1 plane as the window; the system textBackgroundColor
        // falls back to white even under a dark appearance.
        textView.backgroundColor = ContentChrome.window
        textView.textContainerInset = NSSize(width: 0, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
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
        PanelStyle.styleScrollers(in: scrollView)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
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
        let changedRows: Int
    }

    private static func makeSideBySideDiff(before: String, after: String) -> RenderedDiff {
        let beforeLines = splitLines(before)
        let afterLines = splitLines(after)
        let rows = diffRows(before: beforeLines, after: afterLines)
        let changed = rows.filter { $0.left.kind == .deleted || $0.right.kind == .inserted }.count
        // Both columns share one code indent so long line numbers stay aligned.
        let maxNumber = rows.map { max($0.left.number ?? 0, $0.right.number ?? 0) }.max() ?? 0
        let digitW = ("0" as NSString).size(withAttributes: [.font: PanelStyle.monoFont(ofSize: 11)]).width
        let codeX = max(48, ceil(16 + CGFloat(String(maxNumber).count) * digitW + 12))
        return RenderedDiff(
            left: attributedText(for: rows.map(\.left), codeX: codeX),
            right: attributedText(for: rows.map(\.right), codeX: codeX),
            changedRows: changed
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

    /// One 26 pt row per cell: the line number at x 16 (mono 11) and the code
    /// at `codeX` (mono 12). Changed rows carry `DiffTextView.kindKey` so the
    /// view paints the full-width tint and 2 pt bar behind them.
    private static func attributedText(for cells: [DiffCell], codeX: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let codeFont = PanelStyle.monoFont(ofSize: 12)
        let numberFont = PanelStyle.monoFont(ofSize: 11)
        let rowHeight: CGFloat = 26
        let natural = NSLayoutManager().defaultLineHeight(for: codeFont)
        let baselineOffset = max(0, (rowHeight - natural) / 2)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.minimumLineHeight = rowHeight
        paragraph.maximumLineHeight = rowHeight
        paragraph.firstLineHeadIndent = 16
        paragraph.headIndent = codeX
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: codeX)]

        for cell in cells {
            let changed = cell.kind == .deleted || cell.kind == .inserted
            let number = cell.number.map(String.init) ?? ""
            let line = NSMutableAttributedString(string: number + "\t", attributes: [
                .font: numberFont,
                .foregroundColor: changed ? PanelStyle.textTertiary : ContentChrome.text4,
                .paragraphStyle: paragraph,
                .baselineOffset: baselineOffset
            ])
            line.append(NSAttributedString(string: cell.text + "\n", attributes: [
                .font: codeFont,
                .foregroundColor: changed ? PanelStyle.textPrimary : PanelStyle.textSecondary,
                .paragraphStyle: paragraph,
                .baselineOffset: baselineOffset
            ]))
            switch cell.kind {
            case .deleted:
                line.addAttribute(DiffTextView.kindKey, value: DiffTextView.deleted,
                                  range: NSRange(location: 0, length: line.length))
            case .inserted:
                line.addAttribute(DiffTextView.kindKey, value: DiffTextView.inserted,
                                  range: NSRange(location: 0, length: line.length))
            case .unchanged, .placeholder:
                break
            }
            result.append(line)
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

/// Read-only diff column that paints changed rows edge to edge: a 14 % moss
/// (inserted) or shu (deleted) tint inset 1 pt top and bottom, plus a 2 pt bar
/// on the leading edge.
private final class DiffTextView: NSTextView {
    static let kindKey = NSAttributedString.Key("GlanceDiffKind")
    static let deleted = 1
    static let inserted = 2

    /// Keep the view at least as wide as the column so tints span it.
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if let clip = enclosingScrollView?.contentSize { size.width = max(size.width, clip.width) }
        super.setFrameSize(size)
    }

    override func viewWillDraw() {
        if let clip = enclosingScrollView?.contentSize, frame.width < clip.width {
            setFrameSize(NSSize(width: clip.width, height: frame.height))
        }
        super.viewWillDraw()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return }
        let origin = textContainerOrigin
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y),
                                              in: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, glyphRange, _ in
            let index = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            guard index < storage.length,
                  let kind = storage.attribute(Self.kindKey, at: index, effectiveRange: nil) as? Int else { return }
            let color = kind == Self.deleted ? PanelStyle.failure : PanelStyle.success
            let row = NSRect(x: 0, y: lineRect.minY + origin.y + 1,
                             width: self.bounds.width, height: lineRect.height - 2)
            color.withAlphaComponent(0.14).setFill()
            row.fill(using: .sourceOver)
            color.setFill()
            NSRect(x: 0, y: row.minY, width: 2, height: row.height).fill(using: .sourceOver)
        }
    }
}
