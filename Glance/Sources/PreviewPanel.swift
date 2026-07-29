import AppKit
import AVKit
import AVFoundation
import WebKit

class PreviewPanel: NSPanel {
    // MARK: - Layout constants
    private let panelCornerRadius: CGFloat = 20
    private let headerHeight: CGFloat = 52
    /// Fixed width for single-card view; height follows a 9:16 portrait ratio.
    private let singleCardWidth: CGFloat = 320
    private var singleCardImageHeight: CGFloat { singleCardWidth * 16 / 9 }
    private let bottomBarHeight: CGFloat = 72

    // Single-card middle area (around the dark inset)
    private let middlePadding: CGFloat = 20
    private let insetCornerRadius: CGFloat = 20
    private let insetTopArea: CGFloat = 52        // space above the image for anchor + filename pill
    private let metaPillArea: CGFloat = 56        // filename/meta pill below image
    private let filmstripHeight: CGFloat = 56
    private let dotsHeight: CGFloat = 18
    private let insetHorizontalPad: CGFloat = 16  // space between image and dark inset sides
    private let insetBottomPad: CGFloat = 10

    private let splitTotalWidth: CGFloat = 652
    private let splitMaxHeight: CGFloat = 939
    private let splitItemHeight: CGFloat = 64
    private let splitItemSpacing: CGFloat = 2
    private let splitSidebarPad: CGFloat = 8
    private let splitSelectionIndicatorWidth: CGFloat = 3
    private let splitSidebarMinWidth: CGFloat = 120
    private let splitSidebarMaxWidth: CGFloat = 400
    private let splitterWidth: CGFloat = 4
    /// Height of the identity toolbar pinned above the split-view content area.
    private let splitToolbarHeight: CGFloat = 52
    private var userSidebarWidth: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: "PreviewPanelSidebarWidth")
            return saved > 0 ? saved : 180
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "PreviewPanelSidebarWidth")
        }
    }

    // Colors. The semantic ones (windowBackgroundColor, labelColor, etc.)
    // are dynamic NSColors that resolve against NSApp.effectiveAppearance,
    // so flipping the Theme menu updates the panel on next rebuild.
    // The panel now floats on a translucent dark-frosted base (NSVisualEffectView
    // + black tint), so the whole chrome commits to an on-glass dark palette
    // regardless of system theme. Fills are translucent white so the frost reads
    // through them; text is white / dimmed-white.
    fileprivate static let panelBackground   = NSColor.clear
    fileprivate static let middleBackground  = NSColor.clear
    /// Always-dark image canvas — the image needs a neutral dark frame to read
    /// against, even on the frosted base.
    fileprivate static let darkInset         = NSColor(white: 0.03, alpha: 1)
    fileprivate static let bottomBar         = NSColor(white: 1, alpha: 0.06)
    fileprivate static let separator         = NSColor(white: 1, alpha: 0.08)
    fileprivate static let pillBackground    = NSColor(white: 1, alpha: 0.12)
    fileprivate static let pillBackgroundLight = NSColor(white: 1, alpha: 0.18)
    fileprivate static let textDark          = NSColor.white
    fileprivate static let textSecondary     = NSColor(white: 1, alpha: 0.55)
    fileprivate static let textOnDark        = NSColor.white
    fileprivate static let textOnDarkSecondary = NSColor(white: 1, alpha: 0.65)
    fileprivate static let thumbPlaceholder  = NSColor(white: 1, alpha: 0.10)
    fileprivate static let filmstripBorder   = NSColor.systemBlue
    fileprivate static let accentBlue        = NSColor.systemBlue
    /// Hairline that defines the panel edge against any wallpaper.
    fileprivate static let hairline          = NSColor(white: 1, alpha: 0.10)
    /// Translucent card fill for tiles / grouped controls on the frost.
    fileprivate static let glassCard         = NSColor(white: 1, alpha: 0.07)

    /// Resolve a (possibly dynamic) NSColor to a CGColor against the app's
    /// current effective appearance. We need this because `layer.background`
    /// stores a snapshot CGColor — without forcing the right appearance on
    /// resolution, a semantic NSColor (`.windowBackgroundColor` etc.) reads
    /// `NSAppearance.currentDrawing` at the call site, which is usually the
    /// default Aqua appearance during view construction, completely ignoring
    /// our `NSApp.appearance` theme override.
    fileprivate static var isDarkAppearance: Bool {
        var result = false
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            result = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return result
    }

    fileprivate static func resolvedCG(_ color: NSColor) -> CGColor {
        var resolved: CGColor!
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    /// A dark, semi-transparent frosted base. `.hudWindow` + vibrant-dark gives
    /// the translucent black "磨砂" material; a black tint sublayer biases the
    /// frost toward black so it reads consistently over bright wallpapers.
    fileprivate static func makeFrostedBase(cornerRadius: CGFloat) -> NSVisualEffectView {
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true

        let tint = CALayer()
        tint.backgroundColor = NSColor(white: 0, alpha: 0.30).cgColor
        tint.cornerRadius = cornerRadius
        tint.frame = blur.bounds
        tint.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        blur.layer?.addSublayer(tint)
        return blur
    }

    /// 📌 emoji rendered into a fixed-size NSImage — looks identical across
    /// macOS versions because Apple Color Emoji ships with every Mac.
    fileprivate static let pinEmojiImage: NSImage = {
        let canvasSide: CGFloat = 16
        let fontSize: CGFloat = 13
        // Explicitly select Apple Color Emoji so the glyph never falls back
        // to a font that lacks emoji coverage.
        let font = NSFont(name: "Apple Color Emoji", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let text = "📌" as NSString
        let textSize = text.size(withAttributes: attrs)

        let img = NSImage(size: NSSize(width: canvasSide, height: canvasSide))
        img.lockFocus()
        text.draw(
            at: NSPoint(x: (canvasSide - textSize.width) / 2,
                        y: (canvasSide - textSize.height) / 2),
            withAttributes: attrs
        )
        img.unlockFocus()
        img.isTemplate = false  // keep the color glyph; don't let the button tint it
        return img
    }()

    private var tiles: [MediaTileView] = []
    private var anchorPoint: CGPoint = .zero
    private var currentMode: Mode = .singleCard
    private var currentInfos: [MediaInfo] = []
    private var selectedIndex: Int = 0
    private var loadedMediaByIndex: [Int: LoadedMedia] = [:]

    // Single-card view references (used to update labels once load completes).
    private weak var singleHeaderTitle: NSTextField?
    private weak var bottomFilenameLabel: NSTextField?
    private weak var bottomDimsLabel: NSTextField?
    private weak var bottomSizeLabel: NSTextField?
    private weak var topPillLabel: NSTextField?
    private weak var metaPillFilename: NSTextField?
    private weak var metaPillMeta: NSTextField?
    private weak var singleCloseBtn: NSButton?
    private weak var singlePinBtn: NSButton?
    private weak var loginButton: NSButton?
    private weak var navBarView: NSView?
    private weak var splitSidebarScrollView: NSScrollView?
    private weak var splitSidebarDocView: NSView?
    private weak var splitContentView: NSView?
    private weak var splitSidebarContainer: NSView?
    private var splitSidebarItems: [SplitSidebarItem] = []
    private weak var contentWebView: WKWebView?
    private weak var splitterView: NSView?
    /// Identity toolbar pinned above the split-view content area, plus its
    /// child labels. Mirrors ContentViewerWindow's chrome.
    private weak var splitToolbar: NSView?
    private weak var splitToolbarTitle: NSTextField?
    private weak var splitToolbarSubtitle: NSTextField?
    /// Media/webview area below the toolbar. Its subviews are cleared and
    /// rebuilt on every selection change (the toolbar, a sibling, survives).
    private weak var splitContentBody: NSView?
    /// Folder button in the split-view toolbar. Reveals the currently-selected
    /// file in Finder.
    private weak var splitFolderBtn: NSButton?

    /// When pinned, hidePanel() is ignored and the close (X) button shows.
    /// New previews via showLoading() reset this to false.
    private var isPinned: Bool = false
    /// Frame saved after the user manually drags the panel.  Used so the
    /// next preview opens in the same spot rather than re-snapping to the
    /// mouse cursor.
    private var savedPosition: NSRect?

    /// True while a preview is showing, so the didMove observer keeps ContentPanel
    /// docked. Replaces the old 50ms polling follow timer.
    private var isFollowingContentPanel: Bool = false
    private var escapeLocalMonitor: Any?
    private var escapeGlobalMonitor: Any?
    private var contentPanelOpenedByTileClick: Bool = false
    private var hasUserResized: Bool = false
    private var userSetSize: NSSize? {
        get {
            guard let dict = UserDefaults.standard.dictionary(forKey: "PreviewPanelUserSize") as? [String: CGFloat],
                  let w = dict["w"], let h = dict["h"] else { return nil }
            return NSSize(width: w, height: h)
        }
        set {
            if let size = newValue {
                UserDefaults.standard.set(["w": size.width, "h": size.height], forKey: "PreviewPanelUserSize")
            } else {
                UserDefaults.standard.removeObject(forKey: "PreviewPanelUserSize")
            }
        }
    }

    private enum Mode { case singleCard, splitView, contentOnly }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.savedPosition = self.frame
            // Drive ContentPanel following from the move event itself (fires
            // continuously during a live drag) instead of a polling timer.
            if self.isFollowingContentPanel, ContentPanel.shared.isVisible {
                ContentPanel.shared.syncPosition(to: self.frame)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .init("ContentPanelDidClose"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.contentPanelOpenedByTileClick else { return }
            self.forceHidePanel()
        }
        NotificationCenter.default.addObserver(
            forName: .authDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateLoginButtonState()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.hasUserResized = true
            self.userSetSize = self.frame.size
            self.updateSplitView()
        }
        installEscapeKeyMonitors()
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        applyShadowToContent()
    }

    private func applyShadowToContent() {
        guard let root = contentView else { return }
        root.wantsLayer = true
        root.layer?.shadowOpacity = 0.35
        root.layer?.shadowRadius = 32
        root.layer?.shadowOffset = NSSize(width: 0, height: 12)
        root.layer?.shadowColor = NSColor.black.cgColor
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        forceHidePanel(dismissContent: !contentPanelOpenedByTileClick)
    }

    private func installEscapeKeyMonitors() {
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            if self.shouldCloseForEscape(event) {
                self.forceHidePanel(dismissContent: !self.contentPanelOpenedByTileClick)
                return nil
            }
            if self.handleArrowKey(event) {
                return nil
            }
            return event
        }

        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.shouldCloseForEscape(event) else { return }
            DispatchQueue.main.async {
                self.forceHidePanel(dismissContent: !self.contentPanelOpenedByTileClick)
            }
        }
    }

    private func shouldCloseForEscape(_ event: NSEvent) -> Bool {
        isVisible && event.keyCode == 53
    }

    private func handleArrowKey(_ event: NSEvent) -> Bool {
        guard currentMode == .splitView, currentInfos.count > 1 else { return false }
        let newIndex: Int?
        switch event.keyCode {
        case 126:
            newIndex = selectedIndex > 0 ? selectedIndex - 1 : currentInfos.count - 1
        case 125:
            newIndex = selectedIndex < currentInfos.count - 1 ? selectedIndex + 1 : 0
        default:
            return false
        }
        guard let index = newIndex else { return false }
        selectSplitItem(at: index)
        return true
    }

    private func determineMode(for infos: [MediaInfo]) -> Mode {
        if infos.count == 1 {
            switch infos[0].kind {
            case .image, .video:
                return .singleCard
            default:
                return .contentOnly
            }
        }
        return .splitView
    }

    deinit {
        if let escapeLocalMonitor {
            NSEvent.removeMonitor(escapeLocalMonitor)
        }
        if let escapeGlobalMonitor {
            NSEvent.removeMonitor(escapeGlobalMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        let content = ContentPanel.shared
        if content.isVisible {
            content.syncPosition(to: frameRect)
        }
    }

    func startFollowingContentPanel() {
        // Event-driven now: the didMove observer syncs ContentPanel while this
        // flag is set, so there is no polling timer to start.
        isFollowingContentPanel = true
    }

    func stopFollowingContentPanel() {
        isFollowingContentPanel = false
    }

    // MARK: - Public API

    func showLoading(infos: [MediaInfo], at mouseLocation: NSPoint) {
        guard !infos.isEmpty else {
            forceHidePanel()
            return
        }
        contentPanelOpenedByTileClick = false
        ContentPanel.shared.resetFollowState()
        startFollowingContentPanel()
        teardownTiles()
        anchorPoint = mouseLocation
        currentMode = determineMode(for: infos)
        currentInfos = infos
        selectedIndex = 0

        let mainContent = buildContainer(infos: infos)
        let root = buildRootView(mainContent: mainContent)

        relayoutPanel(contentSize: root.frame.size)
        contentView = root

        let isFirstShow = alphaValue == 0
        alphaValue = 0
        if isFirstShow {
            setFrame(NSRect(x: frame.origin.x, y: frame.origin.y,
                           width: frame.width, height: frame.height),
                    display: true)
        }
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    private func buildRootView(mainContent: NSView) -> NSView {
        let navBar = buildNavigationBar(width: mainContent.frame.width)

        let rootWidth: CGFloat
        let rootHeight: CGFloat
        if hasUserResized, let saved = userSetSize {
            rootWidth = saved.width
            rootHeight = saved.height
        } else {
            rootWidth = mainContent.frame.width
            rootHeight = headerHeight + mainContent.frame.height
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: rootWidth, height: rootHeight))
        root.wantsLayer = true
        root.layer?.cornerRadius = panelCornerRadius
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.layer?.borderColor = Self.hairline.cgColor
        root.layer?.borderWidth = 1

        let frost = Self.makeFrostedBase(cornerRadius: panelCornerRadius)
        frost.frame = root.bounds
        frost.autoresizingMask = [.width, .height]
        root.addSubview(frost)

        navBar.frame = NSRect(x: 0, y: rootHeight - headerHeight,
                              width: rootWidth, height: headerHeight)
        mainContent.frame = NSRect(x: 0, y: 0,
                                   width: rootWidth, height: rootHeight - headerHeight)

        navBar.autoresizingMask = [.width, .minYMargin]
        mainContent.autoresizingMask = [.width, .height]

        root.addSubview(mainContent)
        root.addSubview(navBar)
        navBarView = navBar

        return root
    }

    func updateTile(at index: Int, with media: LoadedMedia?, failedMessage: String? = nil) {
        switch currentMode {
        case .singleCard:
            guard tiles.indices.contains(index) else { return }
            let tile = tiles[index]
            if let m = media {
                tile.setLoaded(m)
                if index < currentInfos.count {
                    var updatedInfo = currentInfos[index]
                    updatedInfo.dimensions = m.naturalSize
                    currentInfos[index] = updatedInfo
                    tile.updateInfo(updatedInfo)
                }
            } else {
                tile.setFailed(message: failedMessage)
            }
            if tiles.count == 1, let m = media {
                relayoutSingleCard(with: m)
            }

        case .splitView, .contentOnly:
            guard index < currentInfos.count else { return }

            if let m = media {
                loadedMediaByIndex[index] = m
                if currentMode == .splitView, index < splitSidebarItems.count {
                    splitSidebarItems[index].updateInfo(currentInfos[index])
                    if case .image(let img, _) = m {
                        splitSidebarItems[index].setThumbnail(img)
                    }
                }
                if index == selectedIndex, let contentTile = tiles.first {
                    contentTile.setLoaded(m)
                }
            } else {
                loadedMediaByIndex.removeValue(forKey: index)
                if index == selectedIndex, let contentTile = tiles.first {
                    contentTile.setFailed(message: failedMessage)
                }
            }

            updateSplitView()
        }
    }

    /// Push a disambiguation hint (e.g. "~/Desktop") onto the tile at `index`.
    /// Safe to call before or after the tile's media has loaded.
    func applyHint(at index: Int, hint: String?) {
        guard index < currentInfos.count else { return }
        var info = currentInfos[index]
        info.disambiguationHint = hint
        currentInfos[index] = info

        switch currentMode {
        case .singleCard:
            guard tiles.indices.contains(index) else { return }
            tiles[index].updateInfo(info)
        case .splitView:
            if index < splitSidebarItems.count {
                splitSidebarItems[index].updateInfo(info)
            }
            if index == selectedIndex, let contentTile = tiles.first {
                contentTile.updateInfo(info)
            }
        case .contentOnly:
            if index == selectedIndex, let contentTile = tiles.first {
                contentTile.updateInfo(info)
            }
        }
    }

    func showImage(_ image: NSImage, at point: NSPoint) {
        let info = MediaInfo(url: URL(fileURLWithPath: "/dev/null"), isLocal: false, kind: .image,
                             dimensions: image.size, fileSize: nil, duration: nil)
        showLoading(infos: [info], at: point)
        updateTile(at: 0, with: .image(image, info))
    }

    func showImages(_ images: [NSImage], at point: NSPoint) {
        let infos = images.map {
            MediaInfo(url: URL(fileURLWithPath: "/dev/null"), isLocal: false, kind: .image,
                      dimensions: $0.size, fileSize: nil, duration: nil)
        }
        showLoading(infos: infos, at: point)
        for (i, img) in images.enumerated() {
            updateTile(at: i, with: .image(img, infos[i]))
        }
    }

    func showMedia(_ items: [LoadedMedia], at point: NSPoint) {
        let infos = items.map { $0.info }
        showLoading(infos: infos, at: point)
        for (i, m) in items.enumerated() {
            updateTile(at: i, with: m)
        }
    }

    /// Auto-hide path. With the pin button removed the panel is always
    /// sticky, so this becomes a no-op.  Only explicit close (X button or
    /// re-pressing the hotkey) actually dismisses the panel.
    func hidePanel() {
        // Panel stays visible until the user presses the hotkey again or
        // clicks the close button.
    }

    /// Public close entry-point used by AppDelegate when the user re-presses
    /// the hotkey while a preview is already visible (toggle behaviour).
    /// Also dismisses ContentPanel so both panels close together.
    func closePanel() {
        forceHidePanel(dismissContent: !contentPanelOpenedByTileClick)
    }

    /// Hide PreviewPanel but leave ContentPanel open.
    /// Used by the "single-hit shortcut" path where we open ContentPanel
    /// directly and only want PreviewPanel to go away.
    func closeWithoutAffectingContent() {
        forceHidePanel(dismissContent: false)
    }

    /// Always hide, regardless of pinned state.
    private func forceHidePanel(dismissContent: Bool = true) {
        stopFollowingContentPanel()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isPinned = false
            self?.orderOut(nil)
            self?.teardownTiles()
            if dismissContent {
                ContentPanel.shared.dismiss()
            }
        })
    }

    func clearImage() {
        teardownTiles()
        contentView = NSView(frame: contentView?.frame ?? .zero)
    }



    // MARK: - Container building

    private func buildContainer(infos: [MediaInfo]) -> NSView {
        switch currentMode {
        case .singleCard:  return buildSingleCard(info: infos[0])
        case .splitView:   return buildSplitView(infos: infos)
        case .contentOnly: return buildContentOnlyView(info: infos[0])
        }
    }

    func buildPreviewContainer(infos: [MediaInfo]) -> NSView {
        teardownTiles()
        currentMode = determineMode(for: infos)
        currentInfos = infos
        selectedIndex = currentMode == .splitView ? -1 : 0
        return buildContainer(infos: infos)
    }

    #if DEBUG
    /// Full panel chrome (frosted base + nav bar + content) for SwiftUI previews.
    func buildPreviewRoot(infos: [MediaInfo]) -> NSView {
        let content = buildPreviewContainer(infos: infos)
        return buildRootView(mainContent: content)
    }
    #endif

    // MARK: - Single-card layout

    private func buildSingleCard(info: MediaInfo) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0,
                                        width: singleCardWidth,
                                        height: singleCardImageHeight))
        view.wantsLayer = true
        view.layer?.backgroundColor = Self.darkInset.cgColor
        view.autoresizingMask = [.width, .height]

        let tile = MediaTileView(info: info, style: .singleCard, frame: view.bounds)
        tile.autoresizingMask = [.width, .height]
        tile.onClose = { [weak self] in self?.hidePanel() }
        tile.onOpenExternally = { [weak self] in self?.closePanel() }
        let infoURL = info.url
        tile.onAction = { NSWorkspace.shared.open(infoURL) }
        tile.onDownload = { [weak self, weak tile] in
            guard let tile = tile else { return }
            self?.downloadRemote(url: infoURL, tile: tile)
        }
        tile.onTileTap = { [weak self] in
            guard let self = self, !self.currentInfos.isEmpty else { return }
            self.openInViewer(info: self.currentInfos[0])
        }
        view.addSubview(tile)

        tiles = [tile]
        return view
    }

    private func buildSplitView(infos: [MediaInfo]) -> NSView {
        let sidebarW = userSidebarWidth
        let splitterW = splitterWidth
        let contentW = splitTotalWidth - sidebarW - splitterW
        let totalW = splitTotalWidth

        let itemH = splitItemHeight
        let spacing = splitItemSpacing
        let sidebarTotalH = CGFloat(infos.count) * (itemH + spacing) + splitSidebarPad * 2
        let sidebarH = min(sidebarTotalH, splitMaxHeight)
        let contentH = sidebarH

        let container = NSView(frame: NSRect(x: 0, y: 0, width: totalW, height: contentH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.autoresizingMask = [.width, .height]

        let sidebarContainer = NSView(frame: NSRect(x: 0, y: 0, width: sidebarW, height: contentH))
        sidebarContainer.wantsLayer = true
        sidebarContainer.layer?.backgroundColor = NSColor.clear.cgColor
        sidebarContainer.layer?.masksToBounds = true
        sidebarContainer.autoresizingMask = [.height]

        let frost = Self.makeFrostedBase(cornerRadius: 0)
        frost.frame = sidebarContainer.bounds
        frost.autoresizingMask = [.width, .height]
        sidebarContainer.addSubview(frost)

        let scrollView = NSScrollView(frame: sidebarContainer.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        sidebarContainer.addSubview(scrollView)
        splitSidebarScrollView = scrollView

        let docView = FlippedDocView(frame: NSRect(x: 0, y: 0, width: sidebarW, height: sidebarTotalH))
        splitSidebarDocView = docView

        var newItems: [SplitSidebarItem] = []
        for (i, info) in infos.enumerated() {
            let y = splitSidebarPad + CGFloat(i) * (itemH + spacing)
            let item = SplitSidebarItem(info: info, frame: NSRect(x: splitSidebarPad, y: y,
                                                                   width: sidebarW - splitSidebarPad * 2,
                                                                   height: itemH))
            item.onSelect = { [weak self] in
                self?.selectSplitItem(at: i)
            }
            docView.addSubview(item)
            newItems.append(item)
        }
        scrollView.documentView = docView
        docView.scroll(NSPoint(x: 0, y: 0))

        let splitter = SplitterView(frame: NSRect(x: sidebarW, y: 0, width: splitterW, height: contentH))
        splitter.autoresizingMask = [.minXMargin, .height]
        splitter.onDrag = { [weak self] delta in
            self?.handleSplitterDrag(delta: delta)
        }
        container.addSubview(splitter)
        splitterView = splitter

        let contentView = NSView(frame: NSRect(x: sidebarW + splitterW, y: 0, width: contentW, height: contentH))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = Self.darkInset.cgColor
        contentView.layer?.masksToBounds = true
        contentView.autoresizingMask = [.width, .height]
        splitContentView = contentView

        // Identity toolbar pinned to the top of the content panel (frosted bar
        // with filename + path·modified subtitle on the left, Reveal-in-Finder
        // button on the right). Mirrors ContentViewerWindow's chrome. Sits as a
        // sibling of the media body so it survives the per-selection rebuild.
        let toolbar = PanelStyle.makeBarBlur()
        toolbar.frame = NSRect(x: 0, y: contentH - splitToolbarHeight,
                               width: contentW, height: splitToolbarHeight)
        toolbar.autoresizingMask = [.width, .minYMargin]
        PanelStyle.addHairline(to: toolbar, edge: .minY)

        let titleLbl = NSTextField(labelWithString: "")
        titleLbl.font = PanelStyle.headline
        titleLbl.textColor = PanelStyle.textPrimary
        titleLbl.lineBreakMode = .byTruncatingMiddle
        titleLbl.maximumNumberOfLines = 1
        titleLbl.autoresizingMask = [.width]
        toolbar.addSubview(titleLbl)
        splitToolbarTitle = titleLbl

        let subtitleLbl = NSTextField(labelWithString: "")
        subtitleLbl.font = PanelStyle.caption
        subtitleLbl.textColor = PanelStyle.textSecondary
        subtitleLbl.lineBreakMode = .byTruncatingHead   // keep the path tail
        subtitleLbl.maximumNumberOfLines = 1
        subtitleLbl.autoresizingMask = [.width]
        toolbar.addSubview(subtitleLbl)
        splitToolbarSubtitle = subtitleLbl

        let folderBtn = PanelStyle.makeIconButton(symbol: "folder",
                                                  tooltip: "Reveal in Finder".localized,
                                                  target: self, action: #selector(splitFolderTapped))
        folderBtn.autoresizingMask = [.minXMargin]
        toolbar.addSubview(folderBtn)
        splitFolderBtn = folderBtn

        contentView.addSubview(toolbar)
        splitToolbar = toolbar

        // Media/webview body fills the area below the toolbar.
        let body = NSView(frame: NSRect(x: 0, y: 0, width: contentW,
                                        height: contentH - splitToolbarHeight))
        body.autoresizingMask = [.width, .height]
        contentView.addSubview(body)
        splitContentBody = body

        container.addSubview(sidebarContainer)
        container.addSubview(contentView)

        layoutSplitToolbar()

        splitSidebarContainer = sidebarContainer
        splitSidebarItems = newItems
        if !splitSidebarItems.isEmpty {
            selectSplitItem(at: 0)
        }

        return container
    }

    private func buildContentOnlyView(info: MediaInfo) -> NSView {
        let contentW = splitTotalWidth
        let contentH: CGFloat = splitMaxHeight

        let container = NSView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH))
        container.wantsLayer = true
        container.layer?.backgroundColor = Self.darkInset.cgColor
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]

        let contentView = NSView(frame: container.bounds)
        contentView.autoresizingMask = [.width, .height]
        container.addSubview(contentView)
        splitContentView = contentView

        loadContent(for: info, into: contentView)

        return container
    }

    private func selectSplitItem(at index: Int) {
        guard index < currentInfos.count else { return }
        selectedIndex = index

        for (i, item) in splitSidebarItems.enumerated() {
            item.isSelected = (i == index)
        }

        guard let body = splitContentBody else { return }

        for subview in body.subviews {
            subview.removeFromSuperview()
        }
        tiles.removeAll()
        contentWebView = nil

        let info = currentInfos[index]
        loadContent(for: info, into: body)

        updateSplitToolbar(for: info)

        if ContentPanel.shared.isVisible {
            ContentPanel.shared.load(info: info)
        }

        if let docView = splitSidebarDocView,
           index < splitSidebarItems.count {
            docView.scrollToVisible(splitSidebarItems[index].frame)
        }
    }

    /// Refresh the split-view toolbar's identity (filename + path·modified)
    /// for the given selection, and hide the folder button for remote items.
    private func updateSplitToolbar(for info: MediaInfo) {
        splitToolbarTitle?.stringValue = info.filename
        splitToolbarSubtitle?.stringValue = ContentViewerWindow.subtitleString(for: info.url)
        splitToolbarSubtitle?.toolTip = info.isLocal ? info.url.path : info.url.absoluteString
        // The folder button only makes sense for files that exist on disk.
        splitFolderBtn?.isHidden = !info.isLocal
        layoutSplitToolbar()
    }

    /// Position the toolbar's identity labels (filename over subtitle) and the
    /// right-aligned folder button within the current toolbar width.
    private func layoutSplitToolbar() {
        guard let toolbar = splitToolbar else { return }
        let barW = toolbar.bounds.width
        let barH = toolbar.bounds.height
        let leftMargin: CGFloat = 16
        let rightMargin: CGFloat = 12
        let folderSize: CGFloat = 28
        let labelGap: CGFloat = 12

        let folderHidden = splitFolderBtn?.isHidden ?? true
        let folderX = barW - rightMargin - folderSize
        splitFolderBtn?.frame = NSRect(x: folderX, y: (barH - folderSize) / 2,
                                       width: folderSize, height: folderSize)

        let identityRight = folderHidden ? (barW - rightMargin) : (folderX - labelGap)
        let identityWidth = max(60, identityRight - leftMargin)
        splitToolbarTitle?.frame    = NSRect(x: leftMargin, y: barH - 29, width: identityWidth, height: 18)
        splitToolbarSubtitle?.frame = NSRect(x: leftMargin, y: 9, width: identityWidth, height: 15)
    }

    @objc private func splitFolderTapped() {
        guard selectedIndex >= 0, selectedIndex < currentInfos.count else { return }
        let info = currentInfos[selectedIndex]
        guard info.isLocal else { return }
        NSWorkspace.shared.activateFileViewerSelecting([info.url])
    }

    private func loadContent(for info: MediaInfo, into container: NSView) {
        switch info.kind {
        case .image, .video:
            let tile = MediaTileView(info: info, style: .singleCard, frame: container.bounds)
            tile.autoresizingMask = [.width, .height]
            tile.onClose = { [weak self] in self?.hidePanel() }
            let infoURL = info.url
            tile.onAction = { NSWorkspace.shared.open(infoURL) }
            tile.onDownload = { [weak self, weak tile] in
                guard let tile = tile else { return }
                self?.downloadRemote(url: infoURL, tile: tile)
            }
            tile.onTileTap = { [weak self] in
                guard let self = self, !self.currentInfos.isEmpty else { return }
                self.openInViewer(info: self.currentInfos[self.selectedIndex])
            }
            container.addSubview(tile)
            tiles = [tile]

            if let media = loadedMediaByIndex[selectedIndex] {
                tile.setLoaded(media)
            }

        case .markdown, .text, .pdf, .webPage:
            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: container.bounds, configuration: config)
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
            contentWebView = webView

            switch info.kind {
            case .markdown:
                renderMarkdownView(url: info.url, webView: webView)
            case .text:
                renderHighlightedCode(url: info.url, webView: webView)
            case .pdf:
                if info.url.isFileURL {
                    webView.loadFileURL(info.url, allowingReadAccessTo: info.url.deletingLastPathComponent())
                } else {
                    webView.load(URLRequest(url: info.url))
                }
            case .webPage:
                webView.load(URLRequest(url: info.url))
            default:
                break
            }

        default:
            let tile = MediaTileView(info: info, style: .singleCard, frame: container.bounds)
            tile.autoresizingMask = [.width, .height]
            tile.onClose = { [weak self] in self?.hidePanel() }
            tile.onOpenExternally = { [weak self] in self?.closePanel() }
            container.addSubview(tile)
            tiles = [tile]
        }
    }

    private func renderMarkdownView(url: URL, webView: WKWebView) {
        Task.detached { [weak webView] in
            let raw = await ContentViewerWindow.fetchTextContent(from: url)
            let html = ContentViewerWindow.wrapMarkdownInHTML(raw)
            await MainActor.run {
                webView?.loadHTMLString(html, baseURL: url)
            }
        }
    }

    private func renderHighlightedCode(url: URL, webView: WKWebView) {
        Task.detached { [weak webView] in
            let raw = await ContentViewerWindow.fetchTextContent(from: url)
            let lang = ContentViewerWindow.languageIdentifier(for: url)
            let html = ContentViewerWindow.wrapCodeInHTML(raw, language: lang)
            await MainActor.run {
                webView?.loadHTMLString(html, baseURL: url)
            }
        }
    }

    private func updateSplitView() {
        switch currentMode {
        case .splitView:
            updateSplitViewLayout()
        case .contentOnly:
            updateContentOnlyLayout()
        default:
            break
        }
    }

    private func updateSplitViewLayout() {
        guard !splitSidebarItems.isEmpty else { return }

        guard let root = contentView else { return }
        let totalW = root.frame.width
        let totalH = root.frame.height
        let contentH = totalH - headerHeight

        let sidebarW = userSidebarWidth
        let splitterW = splitterWidth
        let contentW = totalW - sidebarW - splitterW

        let itemH = splitItemHeight
        let spacing = splitItemSpacing
        let sidebarTotalH = CGFloat(currentInfos.count) * (itemH + spacing) + splitSidebarPad * 2

        navBarView?.frame = NSRect(x: 0, y: totalH - headerHeight,
                                   width: totalW, height: headerHeight)

        splitSidebarContainer?.frame = NSRect(x: 0, y: 0, width: sidebarW, height: contentH)
        splitSidebarScrollView?.frame = NSRect(x: 0, y: 0, width: sidebarW, height: contentH)
        splitSidebarDocView?.frame = NSRect(x: 0, y: 0, width: sidebarW, height: sidebarTotalH)
        splitterView?.frame = NSRect(x: sidebarW, y: 0, width: splitterW, height: contentH)
        splitContentView?.frame = NSRect(x: sidebarW + splitterW, y: 0, width: contentW, height: contentH)
        // Toolbar/body follow via autoresizing; re-flow the labels for the new width.
        layoutSplitToolbar()

        for (i, item) in splitSidebarItems.enumerated() where i < currentInfos.count {
            let y = splitSidebarPad + CGFloat(i) * (itemH + spacing)
            item.frame = NSRect(x: splitSidebarPad, y: y,
                                width: sidebarW - splitSidebarPad * 2, height: itemH)
            item.updateInfo(currentInfos[i])
        }
    }

    private func updateContentOnlyLayout() {
        guard let root = contentView else { return }
        let totalW = root.frame.width
        let totalH = root.frame.height
        let contentH = totalH - headerHeight

        navBarView?.frame = NSRect(x: 0, y: totalH - headerHeight,
                                   width: totalW, height: headerHeight)

        splitContentView?.frame = NSRect(x: 0, y: 0, width: totalW, height: contentH)
    }

    // MARK: - Navigation bar (fixed at top)

    private func buildNavigationBar(width: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.clear.cgColor

        let frost = Self.makeFrostedBase(cornerRadius: 0)
        frost.frame = bar.bounds
        frost.autoresizingMask = [.width, .height]
        bar.addSubview(frost)

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = Self.hairline.cgColor
        sep.autoresizingMask = [.width]
        bar.addSubview(sep)

        let closeBtn = makeIconButton(symbol: "xmark", action: #selector(closeButtonTapped), tint: Self.textDark)
        closeBtn.frame = NSRect(x: 16, y: (headerHeight - 28) / 2, width: 28, height: 28)
        closeBtn.tag = 1
        bar.addSubview(closeBtn)
        singleCloseBtn = closeBtn

        let titleLbl = NSTextField(labelWithString: "Glance".localized)
        titleLbl.textColor = Self.textDark
        titleLbl.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLbl.alignment = .center
        titleLbl.lineBreakMode = .byTruncatingMiddle
        titleLbl.maximumNumberOfLines = 1
        titleLbl.frame = NSRect(x: 52, y: (headerHeight - 22) / 2, width: width - 104, height: 22)
        titleLbl.autoresizingMask = [.width]
        titleLbl.tag = 3
        bar.addSubview(titleLbl)
        singleHeaderTitle = titleLbl

        let loginBtn = makeIconButton(symbol: "person.circle", action: #selector(loginButtonTapped), tint: Self.textDark)
        loginBtn.frame = NSRect(x: width - 44, y: (headerHeight - 28) / 2, width: 28, height: 28)
        loginBtn.autoresizingMask = [.minXMargin]
        bar.addSubview(loginBtn)
        loginButton = loginBtn
        updateLoginButtonState()

        return bar
    }

    // MARK: - Header builder (legacy, used by buildSingleCard / buildList)

    private func makeHeaderBar(width: CGFloat, title: String,
                               leftSymbol: String, leftAction: Selector,
                               rightSymbol: String, rightAction: Selector,
                               captureTitleForSingle: Bool) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Self.resolvedCG(Self.panelBackground)

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = Self.resolvedCG(Self.separator)
        sep.autoresizingMask = [.width]
        bar.addSubview(sep)

        let leftBtn = makeIconButton(symbol: leftSymbol, action: leftAction, tint: Self.textDark)
        leftBtn.frame = NSRect(x: 12, y: (headerHeight - 24) / 2, width: 24, height: 24)
        leftBtn.tag = 1
        bar.addSubview(leftBtn)

        let rightBtn = makeIconButton(symbol: rightSymbol, action: rightAction, tint: Self.textDark)
        rightBtn.frame = NSRect(x: width - 36, y: (headerHeight - 24) / 2, width: 24, height: 24)
        rightBtn.tag = 2
        bar.addSubview(rightBtn)

        if captureTitleForSingle {
            rightBtn.isHidden = true
            singlePinBtn = nil
            singleCloseBtn = leftBtn
            leftBtn.isHidden = false
        }

        let titleLbl = NSTextField(labelWithString: title)
        titleLbl.textColor = Self.textDark
        titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLbl.alignment = .center
        titleLbl.lineBreakMode = .byTruncatingMiddle
        titleLbl.maximumNumberOfLines = 1
        titleLbl.frame = NSRect(x: 48, y: (headerHeight - 18) / 2, width: width - 96, height: 18)
        titleLbl.tag = 3
        bar.addSubview(titleLbl)
        if captureTitleForSingle {
            singleHeaderTitle = titleLbl
        }

        return bar
    }

    private func makeIconButton(symbol: String, action: Selector, tint: NSColor) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .recessed
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        btn.imagePosition = .imageOnly
        btn.isBordered = false
        btn.target = self
        btn.action = action
        btn.contentTintColor = tint
        return btn
    }

    // MARK: - Pills (inside dark inset)

    /// Small rounded badge with white text on a translucent dark fill.
    private func makePill(text: String, light: Bool) -> NSView {
        let lbl = NSTextField(labelWithString: text)
        lbl.textColor = .white
        lbl.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        lbl.lineBreakMode = .byTruncatingMiddle
        lbl.maximumNumberOfLines = 1
        lbl.tag = 99

        let textSize = lbl.intrinsicContentSize
        let padding: CGFloat = 10
        let pill = NSView(frame: NSRect(x: 0, y: 0,
                                        width: min(textSize.width + padding * 2, 200),
                                        height: 22))
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 11
        pill.layer?.masksToBounds = true
        pill.layer?.backgroundColor = (light ? Self.pillBackgroundLight : Self.pillBackground).cgColor

        lbl.frame = NSRect(x: padding, y: 3, width: pill.bounds.width - padding * 2, height: 16)
        pill.addSubview(lbl)
        return pill
    }

    /// Multi-line metadata pill shown below the image inside the dark inset.
    private func makeMetaPill(info: MediaInfo) -> NSView {
        let pill = NSView(frame: .zero)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 10
        pill.layer?.masksToBounds = true
        pill.layer?.backgroundColor = Self.pillBackground.cgColor

        let name = NSTextField(labelWithString: info.filename)
        name.textColor = .white
        name.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        name.alignment = .center
        name.lineBreakMode = .byTruncatingMiddle
        name.maximumNumberOfLines = 1
        pill.addSubview(name)
        metaPillFilename = name

        let meta = NSTextField(labelWithString: metaLineString(for: info))
        meta.textColor = Self.textOnDarkSecondary
        meta.font = NSFont.systemFont(ofSize: 10)
        meta.alignment = .center
        meta.lineBreakMode = .byTruncatingTail
        meta.maximumNumberOfLines = 3
        meta.usesSingleLineMode = false
        pill.addSubview(meta)
        metaPillMeta = meta

        // Frame children once the pill has its frame set:
        DispatchQueue.main.async { [weak pill, weak name, weak meta] in
            guard let pill = pill else { return }
            let w = pill.bounds.width
            let h = pill.bounds.height
            name?.frame = NSRect(x: 8, y: h - 18, width: w - 16, height: 14)
            meta?.frame = NSRect(x: 8, y: 4, width: w - 16, height: h - 22)
        }
        return pill
    }

    // MARK: - Filmstrip & dots

    private func makeFilmstrip(width: CGFloat, count: Int, selected: Int) -> NSView {
        let strip = NSView(frame: NSRect(x: 0, y: 0, width: width, height: filmstripHeight))

        let visibleCount = min(5, max(count, 1))
        let thumbH: CGFloat = 44
        let thumbW: CGFloat = 44
        let gap: CGFloat = 6
        let totalW = CGFloat(visibleCount) * thumbW + CGFloat(visibleCount - 1) * gap
        var x = (width - totalW) / 2
        let y = (filmstripHeight - thumbH) / 2

        for i in 0..<visibleCount {
            let thumb = NSView(frame: NSRect(x: x, y: y, width: thumbW, height: thumbH))
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 6
            thumb.layer?.masksToBounds = true
            thumb.layer?.backgroundColor = Self.resolvedCG(Self.thumbPlaceholder)
            if i == selected {
                thumb.layer?.borderColor = Self.filmstripBorder.cgColor
                thumb.layer?.borderWidth = 2
            }
            strip.addSubview(thumb)
            x += thumbW + gap
        }
        return strip
    }

    private func makeDots(width: CGFloat, count: Int, selected: Int) -> NSView {
        let dotsView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: dotsHeight))
        let visibleCount = min(5, max(count, 1))
        let dotSize: CGFloat = 5
        let gap: CGFloat = 5
        let totalW = CGFloat(visibleCount) * dotSize + CGFloat(visibleCount - 1) * gap
        var x = (width - totalW) / 2
        let y = (dotsHeight - dotSize) / 2

        for i in 0..<visibleCount {
            let dot = NSView(frame: NSRect(x: x, y: y, width: dotSize, height: dotSize))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = dotSize / 2
            dot.layer?.backgroundColor = (i == selected
                ? NSColor.white
                : NSColor(white: 1, alpha: 0.35)).cgColor
            dotsView.addSubview(dot)
            x += dotSize + gap
        }
        return dotsView
    }

    // MARK: - Bottom info bar

    private func makeBottomInfoBar(width: CGFloat, info: MediaInfo) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: bottomBarHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Self.bottomBar.cgColor

        let nameLbl = NSTextField(labelWithString: info.filename)
        nameLbl.textColor = Self.textOnDark
        nameLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLbl.lineBreakMode = .byTruncatingMiddle
        nameLbl.maximumNumberOfLines = 1
        nameLbl.frame = NSRect(x: 16, y: bottomBarHeight - 26, width: width - 32, height: 16)
        nameLbl.autoresizingMask = [.width]
        bar.addSubview(nameLbl)
        bottomFilenameLabel = nameLbl

        let dimsLbl = NSTextField(labelWithString: dimsString(for: info))
        dimsLbl.textColor = Self.textOnDarkSecondary
        dimsLbl.font = NSFont.systemFont(ofSize: 11)
        dimsLbl.lineBreakMode = .byTruncatingTail
        dimsLbl.maximumNumberOfLines = 1
        dimsLbl.frame = NSRect(x: 16, y: bottomBarHeight - 44, width: width - 32, height: 14)
        dimsLbl.autoresizingMask = [.width]
        bar.addSubview(dimsLbl)
        bottomDimsLabel = dimsLbl

        let sizeLbl = NSTextField(labelWithString: sizeFormatString(for: info))
        sizeLbl.textColor = Self.textOnDarkSecondary
        sizeLbl.font = NSFont.systemFont(ofSize: 11)
        sizeLbl.lineBreakMode = .byTruncatingTail
        sizeLbl.maximumNumberOfLines = 1
        sizeLbl.frame = NSRect(x: 16, y: 10, width: width - 32, height: 14)
        sizeLbl.autoresizingMask = [.width]
        bar.addSubview(sizeLbl)
        bottomSizeLabel = sizeLbl

        return bar
    }

    private func updateSingleCardLabels(info: MediaInfo) {
        singleHeaderTitle?.stringValue = info.filename
        topPillLabel?.stringValue = info.filename
        metaPillFilename?.stringValue = info.filename
        metaPillMeta?.stringValue = metaLineString(for: info)
        bottomFilenameLabel?.stringValue = info.filename
        bottomDimsLabel?.stringValue = dimsString(for: info)
        bottomSizeLabel?.stringValue = sizeFormatString(for: info)
    }

    // MARK: - Strings

    private func dimsString(for info: MediaInfo) -> String {
        if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
            return "\(Int(dim.width)) × \(Int(dim.height))"
        }
        return info.isLocal ? "—" : ""
    }

    private func sizeFormatString(for info: MediaInfo) -> String {
        var parts: [String] = []
        if let bytes = info.fileSize {
            let f = ByteCountFormatter()
            f.countStyle = .file
            parts.append(f.string(fromByteCount: bytes))
        }
        if !info.formatName.isEmpty {
            parts.append(info.formatName)
        }
        if info.isVideo, let dur = info.duration {
            let total = Int(dur.rounded())
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        return parts.joined(separator: " • ")
    }

    private func metaLineString(for info: MediaInfo) -> String {
        var parts: [String] = []
        if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
            parts.append("\(Int(dim.width)) × \(Int(dim.height))")
        }
        if let bytes = info.fileSize {
            let f = ByteCountFormatter()
            f.countStyle = .file
            parts.append(f.string(fromByteCount: bytes))
        }
        if !info.formatName.isEmpty {
            parts.append(info.formatName)
        }
        return parts.joined(separator: " • ")
    }

    @objc private func closeButtonTapped() {
        forceHidePanel(dismissContent: !contentPanelOpenedByTileClick)
    }

    @objc private func actionButtonTapped() {
        togglePin()
    }

    @objc private func loginButtonTapped() {
        let panel = LoginPanel.shared
        let btnFrame = self.frame
        let point = CGPoint(x: btnFrame.maxX - 200, y: btnFrame.maxY - 10)
        panel.show(at: point)
    }

    private func updateLoginButtonState() {
        guard let button = loginButton else { return }
        let signedIn = AuthManager.shared.isSignedIn
        let symbol = signedIn ? "person.crop.circle.fill" : "person.circle"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: signedIn ? "Account".localized : "Sign In".localized)
        button.contentTintColor = signedIn ? NSColor.systemBlue : Self.textDark
        button.toolTip = signedIn ? "Account".localized : "Sign In".localized
    }

    /// Downloads a remote URL to ~/Downloads. Drives the tile's progress UI;
    /// after success the tile's icon flips to the "locate" glyph and subsequent
    /// clicks open the saved file. The progress animation is held for at least
    /// `minDownloadAnimationDuration` so the user always sees the spinner.
    private func downloadRemote(url: URL, tile: MediaTileView) {
        tile.setDownloadState(.downloading)
        let started = Date()
        let minDuration: TimeInterval = 0.5

        let downloads = FileManager.default.urls(for: .downloadsDirectory,
                                                  in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let dest = uniqueDestination(in: downloads, filename: url.lastPathComponent)

        let task = URLSession.shared.downloadTask(with: url) { [weak tile] tempURL, _, _ in
            let elapsed = Date().timeIntervalSince(started)
            let delay = max(0, minDuration - elapsed)

            let apply: (DownloadOutcome) -> Void = { outcome in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    switch outcome {
                    case .ok(let url):  tile?.setDownloadState(.downloaded, fileURL: url)
                    case .failed:       tile?.setDownloadState(.failed)
                    }
                }
            }

            guard let tempURL = tempURL else { apply(.failed); return }
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                apply(.ok(dest))
            } catch {
                apply(.failed)
            }
        }
        task.resume()
    }

    private enum DownloadOutcome {
        case ok(URL)
        case failed
    }

    private func openInViewer(info: MediaInfo) {
        contentPanelOpenedByTileClick = true
        let panel = ContentPanel.shared
        panel.load(info: info)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func uniqueDestination(in dir: URL, filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = dir.appendingPathComponent(filename)
        var idx = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(idx))" : "\(base) (\(idx)).\(ext)"
            candidate = dir.appendingPathComponent(name)
            idx += 1
        }
        return candidate
    }

    private func togglePin() {
        isPinned.toggle()
        animatePinTransition()
        singleCloseBtn?.isHidden = !isPinned
    }

    private func animatePinTransition() {
        guard let btn = singlePinBtn, let lyr = btn.layer else { return }

        // Rotate around the button's center.
        if lyr.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            lyr.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            lyr.position = CGPoint(x: btn.frame.midX, y: btn.frame.midY)
        }

        let angle: CGFloat = isPinned ? (.pi / 4) : 0   // +45° = counter-clockwise (left)
        let rot = CABasicAnimation(keyPath: "transform.rotation.z")
        rot.fromValue = lyr.value(forKeyPath: "transform.rotation.z")
        rot.toValue = angle
        rot.duration = 0.22
        rot.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rot.fillMode = .forwards
        rot.isRemovedOnCompletion = false
        lyr.add(rot, forKey: "rotate")
        lyr.setValue(angle, forKeyPath: "transform.rotation.z")

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            btn.animator().alphaValue = isPinned ? 1.0 : 0.45
        }
    }

    // MARK: - Relayout

    private func relayoutSingleCard(with media: LoadedMedia) {
        guard let tile = tiles.first else { return }
        // Keep the fixed 9:16 portrait frame; only refresh the tile's internal layers.
        tile.relayoutChildren()
    }

    private func relayoutHeaderBar(_ bar: NSView, width: CGFloat) {
        for sv in bar.subviews {
            switch sv.tag {
            case 1: sv.frame = NSRect(x: 12, y: (headerHeight - 24) / 2, width: 24, height: 24)
            case 2:
                let pinSize: CGFloat = 18
                sv.frame = NSRect(x: width - pinSize - 10,
                                  y: (headerHeight - pinSize) / 2,
                                  width: pinSize, height: pinSize)
            case 3: sv.frame = NSRect(x: 48, y: (headerHeight - 18) / 2,
                                       width: width - 96, height: 18)
            default: sv.frame = NSRect(x: 0, y: 0, width: width, height: 1)
            }
        }
    }

    private func relayoutPanel(contentSize: NSSize) {
        // Default placement is centered on the cursor's screen (clamped fully
        // on-screen). A position the user deliberately dragged to is honored
        // instead — still clamped so it can't end up off a smaller display.
        if hasUserResized, let savedSize = userSetSize {
            if let saved = savedPosition {
                var frame = saved
                frame.size = savedSize
                setFrame(ScreenManager.shared.clampedToVisible(frame), display: true)
            } else {
                let frame = ScreenManager.shared.centeredFrame(for: savedSize, near: anchorPoint)
                setFrame(frame, display: true)
            }
        } else if let saved = savedPosition {
            var frame = saved
            frame.size = contentSize
            setFrame(ScreenManager.shared.clampedToVisible(frame), display: true)
        } else {
            let frame = ScreenManager.shared.centeredFrame(for: contentSize, near: anchorPoint)
            setFrame(frame, display: true)
        }
    }

    private func teardownTiles() {
        for tile in tiles { tile.teardown() }
        tiles.removeAll()
        currentInfos.removeAll()
        loadedMediaByIndex.removeAll()
        singleHeaderTitle = nil
        singleCloseBtn = nil
        singlePinBtn = nil
        splitSidebarScrollView = nil
        splitSidebarDocView = nil
        splitContentView = nil
        splitSidebarContainer = nil
        splitterView = nil
        splitToolbar = nil
        splitContentBody = nil
        splitToolbarTitle = nil
        splitToolbarSubtitle = nil
        splitFolderBtn = nil
        contentWebView = nil
        splitSidebarItems.removeAll()
        bottomFilenameLabel = nil
        bottomDimsLabel = nil
        bottomSizeLabel = nil
        topPillLabel = nil
        metaPillFilename = nil
        metaPillMeta = nil
    }

    private func handleSplitterDrag(delta: CGFloat) {
        let newWidth = userSidebarWidth + delta
        let clamped = max(splitSidebarMinWidth, min(splitSidebarMaxWidth, newWidth))
        guard clamped != userSidebarWidth else { return }
        userSidebarWidth = clamped
        updateSplitViewLayout()
    }
}

final class SplitterView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var lastX: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        lastX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        let currentX = event.locationInWindow.x
        let delta = currentX - lastX
        lastX = currentX
        onDrag?(delta)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}

final class SplitSidebarItem: NSView {
    var info: MediaInfo
    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }
    var onSelect: (() -> Void)?

    private let thumbnailLayer = CALayer()
    private let nameLabel = NSTextField()
    private let metaLabel = NSTextField()
    private let selectionIndicator = NSView()

    init(info: MediaInfo, frame: NSRect) {
        self.info = info
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        selectionIndicator.wantsLayer = true
        selectionIndicator.layer?.backgroundColor = NSColor.systemBlue.cgColor
        selectionIndicator.layer?.cornerRadius = 1.5
        selectionIndicator.isHidden = true
        addSubview(selectionIndicator)

        thumbnailLayer.contentsGravity = .resizeAspectFill
        thumbnailLayer.masksToBounds = true
        thumbnailLayer.cornerRadius = 4
        layer?.addSublayer(thumbnailLayer)

        if info.kind != .image && info.kind != .video {
            let icon = FileTypeIcon.makeImage(for: info, size: CGSize(width: 48, height: 48))
            thumbnailLayer.contents = icon
        }

        nameLabel.stringValue = info.filename
        nameLabel.textColor = .white
        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.backgroundColor = .clear
        addSubview(nameLabel)

        metaLabel.textColor = NSColor(white: 1, alpha: 0.55)
        metaLabel.font = NSFont.systemFont(ofSize: 10)
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.maximumNumberOfLines = 1
        metaLabel.isEditable = false
        metaLabel.isBordered = false
        metaLabel.backgroundColor = .clear
        addSubview(metaLabel)

        updateMeta()
        updateAppearance()
        relayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateInfo(_ newInfo: MediaInfo) {
        self.info = newInfo
        nameLabel.stringValue = newInfo.filename
        updateMeta()
    }

    private func updateMeta() {
        var parts: [String] = []
        if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
            parts.append("\(Int(dim.width)) × \(Int(dim.height))")
        }
        if let bytes = info.fileSize {
            let f = ByteCountFormatter()
            f.countStyle = .file
            parts.append(f.string(fromByteCount: bytes))
        }
        metaLabel.stringValue = parts.joined(separator: " · ")
    }

    func setThumbnail(_ image: NSImage) {
        thumbnailLayer.contents = image
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
            selectionIndicator.isHidden = false
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            selectionIndicator.isHidden = true
        }
    }

    private func relayout() {
        let thumbSize: CGFloat = 48
        let pad: CGFloat = 8
        let textX = pad + thumbSize + pad
        let textW = bounds.width - textX - pad

        selectionIndicator.frame = NSRect(x: 0, y: 4, width: 3, height: bounds.height - 8)
        thumbnailLayer.frame = NSRect(x: pad, y: (bounds.height - thumbSize) / 2, width: thumbSize, height: thumbSize)
        nameLabel.frame = NSRect(x: textX, y: bounds.height / 2 - 2, width: textW, height: 16)
        metaLabel.frame = NSRect(x: textX, y: bounds.height / 2 - 18, width: textW, height: 14)
    }

    override func layout() {
        super.layout()
        relayout()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

final class FlippedDocView: NSView {
    override var isFlipped: Bool { true }
}

final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - Tile view

final class MediaTileView: NSView {
    enum Style { case singleCard, masonry }

    var info: MediaInfo
    let style: Style

    private var mediaContainer: NSView!
    private let imageLayer = CALayer()
    private let spinner = NSProgressIndicator()
    private let loadingLabel = NSTextField(labelWithString: "Searching…".localized)
    private let shimmerLayer = CAGradientLayer()
    private var downloadBtn: NSButton?
    private let downloadSpinner = NSProgressIndicator()
    private var downloadState: DownloadState = .idle
    private var downloadedFileURL: URL?

    enum DownloadState { case idle, downloading, downloaded, failed }

    // Masonry overlay
    private let overlayGradient = CAGradientLayer()
    private var filenameLabel: NSTextField?
    private var dimsLabel: NSTextField?
    private var sizeLabel: NSTextField?
    private var pathLabel: NSTextField?

    private var playerView: AVPlayerView?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    var onClose: (() -> Void)?
    var onAction: (() -> Void)?
    var onDownload: (() -> Void)?
    /// Called when the user clicks anywhere on the tile body (used to open
    /// markdown/webpage tiles in the viewer window).
    var onTileTap: (() -> Void)?
    /// Called after the tile hands its content off to an external app
    /// (e.g. revealing a folder in Finder) so the panel can dismiss itself.
    var onOpenExternally: (() -> Void)?

    private var openableIconView: NSImageView?
    /// Type-specific SF Symbol shown behind the spinner while the tile is
    /// still loading. Hidden once `setLoaded` runs.
    private var placeholderIconView: NSImageView?
    /// "Reveal in Finder" overlay shown on local markdown / text tiles —
    /// gives the user a one-click jump to the file's folder without
    /// triggering the tile's openable-viewer click.
    private var locateBtn: NSButton?

    init(info: MediaInfo, style: Style, frame: NSRect) {
        self.info = info
        self.style = style
        super.init(frame: frame)
        wantsLayer = true

        switch style {
        case .singleCard:
            layer?.backgroundColor = NSColor(white: 0.03, alpha: 1).cgColor

            mediaContainer = PassthroughView()
            mediaContainer.wantsLayer = true
            mediaContainer.layer?.masksToBounds = true
            mediaContainer.layer?.backgroundColor = NSColor(white: 0.03, alpha: 1).cgColor
            addSubview(mediaContainer)

            let ambientGradient = CAGradientLayer()
            ambientGradient.colors = [
                NSColor(white: 0.08, alpha: 1).cgColor,
                NSColor(white: 0.03, alpha: 1).cgColor
            ]
            ambientGradient.locations = [0.0, 1.0]
            ambientGradient.startPoint = CGPoint(x: 0.5, y: 0)
            ambientGradient.endPoint = CGPoint(x: 0.5, y: 1)
            mediaContainer.layer?.addSublayer(ambientGradient)

            shimmerLayer.colors = [
                NSColor(white: 1, alpha: 0).cgColor,
                NSColor(white: 1, alpha: 0.04).cgColor,
                NSColor(white: 1, alpha: 0).cgColor
            ]
            shimmerLayer.locations = [0.0, 0.5, 1.0]
            shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
            shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
            mediaContainer.layer?.addSublayer(shimmerLayer)
            startShimmer()

            imageLayer.contentsGravity = .resizeAspect
            imageLayer.masksToBounds = true
            mediaContainer.layer?.addSublayer(imageLayer)

            overlayGradient.colors = [
                NSColor(white: 0, alpha: 0.94).cgColor,
                NSColor(white: 0, alpha: 0.60).cgColor,
                NSColor(white: 0, alpha: 0.0).cgColor
            ]
            overlayGradient.locations = [0.0, 0.35, 1.0]
            overlayGradient.startPoint = CGPoint(x: 0.5, y: 0)
            overlayGradient.endPoint = CGPoint(x: 0.5, y: 1)
            overlayGradient.isHidden = true
            mediaContainer.layer?.addSublayer(overlayGradient)

            let nameLbl = NSTextField(labelWithString: info.filename)
            nameLbl.textColor = .white
            nameLbl.font = NSFont.systemFont(ofSize: 17, weight: .bold)
            nameLbl.lineBreakMode = .byTruncatingMiddle
            nameLbl.maximumNumberOfLines = 1
            nameLbl.isHidden = true
            addSubview(nameLbl)
            filenameLabel = nameLbl

            let dimsLbl = NSTextField(labelWithString: "")
            dimsLbl.textColor = NSColor(white: 1, alpha: 0.75)
            dimsLbl.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            dimsLbl.lineBreakMode = .byTruncatingTail
            dimsLbl.maximumNumberOfLines = 3
            dimsLbl.usesSingleLineMode = false
            dimsLbl.isHidden = true
            addSubview(dimsLbl)
            dimsLabel = dimsLbl

            let sizeLbl = NSTextField(labelWithString: "")
            sizeLbl.isHidden = true
            addSubview(sizeLbl)
            sizeLabel = sizeLbl

        case .masonry:
            // Translucent glass card sitting on the frosted base, with a
            // hairline edge; the image itself rests on a dark canvas.
            layer?.cornerRadius = 14
            layer?.masksToBounds = true
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
            layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
            layer?.borderWidth = 1

            mediaContainer = PassthroughView()
            mediaContainer.wantsLayer = true
            mediaContainer.layer?.masksToBounds = true
            mediaContainer.layer?.backgroundColor = NSColor(white: 0.04, alpha: 1).cgColor
            addSubview(mediaContainer)

            shimmerLayer.colors = [
                NSColor(white: 1, alpha: 0).cgColor,
                NSColor(white: 1, alpha: 0.06).cgColor,
                NSColor(white: 1, alpha: 0).cgColor
            ]
            shimmerLayer.locations = [0.0, 0.5, 1.0]
            shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
            shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
            mediaContainer.layer?.addSublayer(shimmerLayer)
            startShimmer()

            imageLayer.contentsGravity = .resizeAspectFill
            imageLayer.masksToBounds = true
            mediaContainer.layer?.addSublayer(imageLayer)

            overlayGradient.colors = [
                NSColor(white: 0, alpha: 0.92).cgColor,
                NSColor(white: 0, alpha: 0.72).cgColor,
                NSColor(white: 0, alpha: 0.0).cgColor
            ]
            overlayGradient.locations = [0.0, 0.35, 1.0]
            overlayGradient.startPoint = CGPoint(x: 0.5, y: 0)
            overlayGradient.endPoint = CGPoint(x: 0.5, y: 1)
            overlayGradient.isHidden = true
            mediaContainer.layer?.addSublayer(overlayGradient)

            let nameLbl = NSTextField(labelWithString: info.filename)
            nameLbl.textColor = .white
            nameLbl.font = NSFont.systemFont(ofSize: 14, weight: .bold)
            nameLbl.lineBreakMode = .byTruncatingMiddle
            nameLbl.maximumNumberOfLines = 1
            nameLbl.isHidden = true
            addSubview(nameLbl)
            filenameLabel = nameLbl

            let dimsLbl = NSTextField(labelWithString: "")
            dimsLbl.textColor = NSColor(white: 1, alpha: 0.85)
            dimsLbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            dimsLbl.lineBreakMode = .byTruncatingTail
            dimsLbl.maximumNumberOfLines = 3
            dimsLbl.usesSingleLineMode = false
            dimsLbl.isHidden = true
            addSubview(dimsLbl)
            dimsLabel = dimsLbl

            let sizeLbl = NSTextField(labelWithString: "")
            sizeLbl.isHidden = true
            addSubview(sizeLbl)
            sizeLabel = sizeLbl

            let pathLbl = NSTextField(labelWithString: "")
            pathLbl.textColor = NSColor(white: 1, alpha: 0.55)
            pathLbl.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            pathLbl.lineBreakMode = .byTruncatingMiddle
            pathLbl.maximumNumberOfLines = 1
            pathLbl.isHidden = true
            addSubview(pathLbl)
            pathLabel = pathLbl
        }

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.usesThreadedAnimation = true
        spinner.appearance = NSAppearance(named: .vibrantDark)
        spinner.startAnimation(nil)
        addSubview(spinner)

        loadingLabel.textColor = NSColor(white: 1, alpha: 0.85)
        loadingLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        loadingLabel.alignment = .center
        loadingLabel.maximumNumberOfLines = 1
        addSubview(loadingLabel)

        // Action button + companion spinner. Remote items start in .idle
        // (click → download). Local items start in .downloaded with the
        // existing path (click → open).
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .recessed
        btn.imagePosition = .imageOnly
        btn.isBordered = false
        btn.target = self
        btn.action = #selector(downloadTapped)
        addSubview(btn)
        downloadBtn = btn

        downloadSpinner.style = .spinning
        downloadSpinner.controlSize = .small
        downloadSpinner.isIndeterminate = true
        downloadSpinner.usesThreadedAnimation = true
        downloadSpinner.appearance = NSAppearance(named: .vibrantDark)
        downloadSpinner.isHidden = true
        addSubview(downloadSpinner)

        if info.hasIconContent {
            // Tile body is the action target — no download/open button.
            // Covers markdown/text/webpage (open in viewer) and .other
            // (reveal in Finder).
            downloadBtn?.isHidden = true
            downloadSpinner.isHidden = true
        } else if info.kind == .image || info.kind == .video {
            downloadBtn?.isHidden = true
            downloadSpinner.isHidden = true
        } else if info.isLocal {
            setDownloadState(.downloaded, fileURL: info.url)
        } else {
            setDownloadState(.idle)
        }

        installLocateButtonIfNeeded(for: info)

        relayoutChildren()
    }

    /// For local markdown / text files (the tile-clicks-into-viewer kinds),
    /// drop a small folder badge in the bottom-right corner. Clicking it
    /// jumps to Finder with the file pre-selected, instead of opening the
    /// in-app viewer.
    private func installLocateButtonIfNeeded(for info: MediaInfo) {
        guard info.isLocal,
              info.kind == .markdown || info.kind == .text || info.kind == .folder else { return }

        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .recessed
        btn.imagePosition = .imageOnly
        btn.isBordered = false
        btn.target = self
        btn.action = #selector(locateTapped)
        btn.image = NSImage(systemSymbolName: "folder.fill",
                             accessibilityDescription: "Reveal in Finder".localized)
        btn.contentTintColor = .white
        btn.toolTip = "Reveal in Finder".localized
        addSubview(btn)
        locateBtn = btn
    }

    @objc private func locateTapped() {
        NSWorkspace.shared.activateFileViewerSelecting([info.url])
    }

    /// Install a kind-specific colored icon behind the spinner so each tile
    /// is recognisable before its content loads. For image / video tiles the
    /// thumbnail or video frame replaces the icon on success; for openable
    /// kinds (markdown / text / webpage) the icon stays as the tile's content.
    private func installPlaceholderIcon(for info: MediaInfo) {
        let canvas = CGSize(width: 220, height: 220)
        let icon = NSImageView()
        icon.image = FileTypeIcon.makeImage(for: info, size: canvas)
        icon.imageScaling = .scaleProportionallyUpOrDown
        // Dim slightly while loading — the real content takes over on success.
        icon.alphaValue = info.opensInViewer ? 1.0 : 0.85
        mediaContainer.addSubview(icon)
        placeholderIconView = icon
    }

    @objc private func downloadTapped() {
        switch downloadState {
        case .idle, .failed:
            onDownload?()
        case .downloading:
            break  // already in flight
        case .downloaded:
            // Now that the file is on disk (either it was local, or the
            // remote download finished), this button reveals it in Finder
            // rather than opening it. Tile body click is the "open" path.
            if let url = downloadedFileURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    func setDownloadState(_ state: DownloadState, fileURL: URL? = nil) {
        downloadState = state
        downloadedFileURL = fileURL
        switch state {
        case .idle:
            downloadBtn?.image = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                          accessibilityDescription: "Download".localized)
            downloadBtn?.contentTintColor = .white
            downloadBtn?.isHidden = false
            downloadSpinner.stopAnimation(nil)
            downloadSpinner.isHidden = true
        case .downloading:
            downloadBtn?.isHidden = true
            downloadSpinner.isHidden = false
            downloadSpinner.startAnimation(nil)
        case .downloaded:
            // Folder badge — clicking reveals the file in Finder.
            downloadBtn?.image = NSImage(systemSymbolName: "folder.fill",
                                          accessibilityDescription: "Reveal in Finder".localized)
            downloadBtn?.contentTintColor = .white
            downloadBtn?.toolTip = "Reveal in Finder".localized
            downloadBtn?.isHidden = false
            downloadSpinner.stopAnimation(nil)
            downloadSpinner.isHidden = true
        case .failed:
            downloadBtn?.image = NSImage(systemSymbolName: "exclamationmark.circle.fill",
                                          accessibilityDescription: "Download failed".localized)
            downloadBtn?.contentTintColor = .systemRed
            downloadBtn?.isHidden = false
            downloadSpinner.stopAnimation(nil)
            downloadSpinner.isHidden = true
        }
    }

    private func startShimmer() {
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-0.5, 0.0, 0.5]
        anim.toValue   = [0.5, 1.0, 1.5]
        anim.duration = 1.2
        anim.repeatCount = .infinity
        shimmerLayer.add(anim, forKey: "shimmer")
    }

    private func stopShimmer() {
        shimmerLayer.removeAnimation(forKey: "shimmer")
        shimmerLayer.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func relayoutChildren() {
        let spinnerSize: CGFloat = 20
        if let placeholder = placeholderIconView {
            let side = min(bounds.width, bounds.height) * 0.42
            placeholder.frame = NSRect(
                x: (bounds.width  - side) / 2,
                y: (bounds.height - side) / 2,
                width: side, height: side
            )
        }
        if let openable = openableIconView {
            let side = min(bounds.width, bounds.height) * 0.68
            openable.frame = NSRect(
                x: (bounds.width  - side) / 2,
                y: (bounds.height - side) / 2,
                width: side, height: side
            )
        }
        let hasHint = info.disambiguationHint != nil && !info.disambiguationHint!.isEmpty
        switch style {
        case .singleCard:
            mediaContainer.frame = bounds
            imageLayer.frame = mediaContainer.bounds
            playerView?.frame = mediaContainer.bounds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let gradH: CGFloat = hasHint ? 120 : 96
            overlayGradient.frame = NSRect(x: 0, y: 0, width: bounds.width, height: gradH)
            shimmerLayer.frame = mediaContainer.bounds
            CATransaction.commit()
            spinner.frame = NSRect(
                x: bounds.midX - spinnerSize / 2,
                y: bounds.midY - spinnerSize / 2 + 8,
                width: spinnerSize, height: spinnerSize
            )
            loadingLabel.frame = NSRect(x: 0, y: bounds.midY - 18,
                                         width: bounds.width, height: 14)
            let textX: CGFloat = 14
            let dlBtnSize: CGFloat = 34
            let dlReserved = (downloadBtn != nil) ? (dlBtnSize + 12) : 14
            let textW = bounds.width - textX - dlReserved
            let dimsHeight: CGFloat = hasHint ? 34 : 18
            let filenameY: CGFloat = hasHint ? 52 : 36
            let filenameHeight: CGFloat = hasHint ? 20 : 22
            filenameLabel?.frame = NSRect(x: textX, y: filenameY, width: textW, height: filenameHeight)
            dimsLabel?.frame     = NSRect(x: textX, y: 14, width: textW, height: dimsHeight)
            sizeLabel?.frame     = .zero
            downloadBtn?.frame = NSRect(
                x: bounds.width - dlBtnSize - 10,
                y: 22,
                width: dlBtnSize, height: dlBtnSize
            )
            downloadSpinner.frame = NSRect(
                x: bounds.width - dlBtnSize - 10 + (dlBtnSize - 20) / 2,
                y: 22 + (dlBtnSize - 20) / 2,
                width: 20, height: 20
            )
            locateBtn?.frame = NSRect(
                x: bounds.width - dlBtnSize - 10,
                y: 22,
                width: dlBtnSize, height: dlBtnSize
            )

        case .masonry:
            mediaContainer.frame = NSRect(x: 0, y: 14, width: bounds.width, height: bounds.height - 14)
            imageLayer.frame = mediaContainer.bounds
            playerView?.frame = mediaContainer.bounds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let gradientH: CGFloat = hasHint ? 100 : 76
            overlayGradient.frame = NSRect(x: 0, y: 0, width: bounds.width, height: gradientH)
            shimmerLayer.frame = mediaContainer.bounds
            CATransaction.commit()
            spinner.frame = NSRect(
                x: bounds.midX - spinnerSize / 2,
                y: bounds.midY - spinnerSize / 2 + 6,
                width: spinnerSize, height: spinnerSize
            )
            loadingLabel.frame = NSRect(x: 0, y: bounds.midY - 18,
                                         width: bounds.width, height: 14)

            let textX: CGFloat = 8
            let dlBtnSizeM: CGFloat = 28
            let dlReservedM = (downloadBtn != nil) ? (dlBtnSizeM + 10) : 8
            let textW = bounds.width - textX - dlReservedM
            let dimsHeight: CGFloat = hasHint ? 28 : 14
            let filenameY: CGFloat = hasHint ? 42 : 28
            let filenameHeight: CGFloat = hasHint ? 14 : 18
            filenameLabel?.frame = NSRect(x: textX, y: filenameY, width: textW, height: filenameHeight)
            dimsLabel?.frame     = NSRect(x: textX, y: 10, width: textW, height: dimsHeight)
            sizeLabel?.frame     = .zero
            pathLabel?.frame     = NSRect(x: textX, y: 0, width: textW, height: 12)
            downloadBtn?.frame = NSRect(
                x: bounds.width - dlBtnSizeM - 6,
                y: 14,
                width: dlBtnSizeM, height: dlBtnSizeM
            )
            downloadSpinner.frame = NSRect(
                x: bounds.width - dlBtnSizeM - 6 + (dlBtnSizeM - 18) / 2,
                y: 14 + (dlBtnSizeM - 18) / 2,
                width: 18, height: 18
            )
            locateBtn?.frame = NSRect(
                x: bounds.width - dlBtnSizeM - 6,
                y: 14,
                width: dlBtnSizeM, height: dlBtnSizeM
            )
        }
    }

    func setLoaded(_ media: LoadedMedia) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        loadingLabel.isHidden = true
        stopShimmer()
        overlayGradient.isHidden = false
        filenameLabel?.isHidden = false
        dimsLabel?.isHidden = false
        pathLabel?.isHidden = false

        switch media {
        case .image(let img, let info):
            imageLayer.contents = img
            placeholderIconView?.removeFromSuperview()
            placeholderIconView = nil
            updateText(with: info)
        case .video(let url, _, let info):
            attachPlayer(url: url)
            placeholderIconView?.removeFromSuperview()
            placeholderIconView = nil
            updateText(with: info)
        case .openable(let info):
            // Markdown / text / webpage tile — promote the loading placeholder
            // icon to the final content glyph (larger, fully opaque).
            showOpenablePlaceholder(for: info)
            updateText(with: info)
        }
    }

    func setFailed(message: String? = nil) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        stopShimmer()
        overlayGradient.isHidden = false
        placeholderIconView?.alphaValue = 0.35

        if let token = info.searchToken, !token.isEmpty {
            // Spotlight search failure — show the token we were looking for.
            loadingLabel.stringValue = "File not found".localized
            loadingLabel.textColor = .systemRed
            filenameLabel?.stringValue = token
            filenameLabel?.isHidden = false
            dimsLabel?.stringValue = message ?? "No matching file found".localized
            dimsLabel?.isHidden = false
            dimsLabel?.textColor = .systemRed
            if style == .masonry {
                pathLabel?.stringValue = info.url.path
                pathLabel?.isHidden = false
            }
        } else {
            // Normal media load failure.
            loadingLabel.stringValue = message ?? "Failed".localized
            loadingLabel.textColor = .systemRed
            filenameLabel?.isHidden = false
            dimsLabel?.isHidden = false
            if style == .masonry {
                dimsLabel?.stringValue = message ?? "Failed to load".localized
                dimsLabel?.textColor = .systemRed
                pathLabel?.stringValue = info.url.path
                pathLabel?.isHidden = false
            }
        }
    }

    func updateInfo(_ newInfo: MediaInfo) {
        self.info = newInfo
        updateText(with: newInfo)
    }

    func teardown() {
        player?.pause()
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player = nil
        playerView?.player = nil
    }

    private func showOpenablePlaceholder(for info: MediaInfo) {
        // Drop the loading-state placeholder before installing the final glyph
        // so they don't stack.
        placeholderIconView?.removeFromSuperview()
        placeholderIconView = nil

        let canvas = CGSize(width: 220, height: 220)
        let icon = openableIconView ?? NSImageView()
        icon.image = FileTypeIcon.makeImage(for: info, size: canvas)
        icon.imageScaling = .scaleProportionallyUpOrDown
        if icon.superview == nil {
            mediaContainer.addSubview(icon)
            openableIconView = icon
        }
        // Larger than the loading-state placeholder — this is the final
        // content for openable tiles, so let it dominate the card.
        let side = min(bounds.width, bounds.height) * 0.68
        icon.frame = NSRect(x: (bounds.width  - side) / 2,
                             y: (bounds.height - side) / 2,
                             width: side, height: side)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        switch info.kind {
        case .image, .webPage, .markdown, .text, .pdf:
            onTileTap?()
        case .other, .folder:
            if info.isLocal {
                if info.url.pathExtension.lowercased() == "app" {
                    NSWorkspace.shared.open(info.url)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([info.url])
                }
            } else {
                NSWorkspace.shared.open(info.url)
            }
            if info.kind == .folder {
                onOpenExternally?()
            }
        default:
            NSWorkspace.shared.open(info.url)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if info.isVideo {
            enclosingScrollView?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func attachPlayer(url: URL) {
        let pv = PassthroughPlayerView(frame: mediaContainer.bounds)
        pv.controlsStyle = .none
        pv.videoGravity = (style == .singleCard) ? .resizeAspect : .resizeAspectFill
        let p = AVPlayer(url: url)
        p.isMuted = true
        pv.player = p
        mediaContainer.addSubview(pv)
        playerView = pv
        player = p

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { [weak p] _ in
            p?.seek(to: .zero); p?.play()
        }
        p.play()
    }

    private func updateText(with info: MediaInfo) {
        switch info.kind {
        case .image, .video:
            applyMediaText(info: info)
        case .markdown, .text, .pdf:
            filenameLabel?.stringValue = info.filename
            var pieces: [String] = []
            if !info.formatName.isEmpty { pieces.append(info.formatName) }
            if let bytes = info.fileSize {
                let f = ByteCountFormatter()
                f.countStyle = .file
                pieces.append(f.string(fromByteCount: bytes))
            }
            let metaLine = pieces.joined(separator: " · ")
            if let hint = info.disambiguationHint, !hint.isEmpty {
                let hintText = String(format: "in %@".localized, hint)
                dimsLabel?.stringValue = "\(metaLine)\n\(hintText)"
            } else {
                dimsLabel?.stringValue = metaLine
            }
            sizeLabel?.stringValue = ""
            if style == .masonry {
                pathLabel?.stringValue = info.url.path
                pathLabel?.isHidden = false
            }
        case .webPage:
            filenameLabel?.stringValue = info.url.host ?? info.filename
            dimsLabel?.stringValue = info.url.absoluteString
            sizeLabel?.stringValue = ""
            if style == .masonry {
                pathLabel?.stringValue = info.url.absoluteString
                pathLabel?.isHidden = false
            }
        case .other:
            filenameLabel?.stringValue = info.filename
            var pieces: [String] = []
            if !info.formatName.isEmpty { pieces.append(info.formatName) }
            if let bytes = info.fileSize {
                let f = ByteCountFormatter()
                f.countStyle = .file
                pieces.append(f.string(fromByteCount: bytes))
            }
            let metaLine = pieces.joined(separator: " · ")
            if let hint = info.disambiguationHint, !hint.isEmpty {
                let hintText = String(format: "in %@".localized, hint)
                dimsLabel?.stringValue = "\(metaLine)\n\(hintText)"
            } else {
                dimsLabel?.stringValue = metaLine
            }
            sizeLabel?.stringValue = ""
            if style == .masonry {
                pathLabel?.stringValue = info.url.path
                pathLabel?.isHidden = false
            }
        case .folder:
            filenameLabel?.stringValue = info.filename
            var pieces: [String] = []
            if let bytes = info.fileSize {
                let f = ByteCountFormatter()
                f.countStyle = .file
                pieces.append(f.string(fromByteCount: bytes))
            }
            let metaLine = pieces.joined(separator: " · ")
            if let hint = info.disambiguationHint, !hint.isEmpty {
                let hintText = String(format: "in %@".localized, hint)
                dimsLabel?.stringValue = pieces.isEmpty ? hintText : "\(metaLine)\n\(hintText)"
            } else {
                dimsLabel?.stringValue = pieces.isEmpty ? "Folder".localized : metaLine
            }
            sizeLabel?.stringValue = ""
            if style == .masonry {
                pathLabel?.stringValue = info.url.path
                pathLabel?.isHidden = false
            }
        }
    }

    private func applyMediaText(info: MediaInfo) {
        filenameLabel?.stringValue = info.filename

        var pieces: [String] = []
        if let dim = info.dimensions, dim.width > 0, dim.height > 0 {
            pieces.append("\(Int(dim.width)) × \(Int(dim.height))")
        }
        if let bytes = info.fileSize {
            let f = ByteCountFormatter()
            f.countStyle = .file
            pieces.append(f.string(fromByteCount: bytes))
        }
        if !info.formatName.isEmpty { pieces.append(info.formatName) }

        let metaLine = pieces.joined(separator: " · ")
        if let hint = info.disambiguationHint, !hint.isEmpty {
            let hintText = String(format: "in %@".localized, hint)
            dimsLabel?.stringValue = "\(metaLine)\n\(hintText)"
        } else {
            dimsLabel?.stringValue = metaLine
        }
        sizeLabel?.stringValue = ""

        if style == .masonry {
            let path = info.url.isFileURL ? info.url.path : info.url.absoluteString
            pathLabel?.stringValue = path
            pathLabel?.isHidden = false
        }
    }
}

final class PassthroughPlayerView: AVPlayerView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
