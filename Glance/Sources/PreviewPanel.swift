import AppKit
import AVKit
import AVFoundation
import WebKit

class PreviewPanel: NSPanel {
    // MARK: - Layout constants
    private let anchorOffset = CGPoint(x: 20, y: 0)
    private let panelCornerRadius: CGFloat = 16
    private let headerHeight: CGFloat = 48
    /// Fixed width for single-card view; height follows a 9:16 portrait ratio.
    private let singleCardWidth: CGFloat = 300
    private var singleCardImageHeight: CGFloat { singleCardWidth * 16 / 9 }
    private let bottomBarHeight: CGFloat = 72

    // Single-card middle area (around the dark inset)
    private let middlePadding: CGFloat = 18
    private let insetCornerRadius: CGFloat = 18
    private let insetTopArea: CGFloat = 48        // space above the image for anchor + filename pill
    private let metaPillArea: CGFloat = 56        // filename/meta pill below image
    private let filmstripHeight: CGFloat = 56
    private let dotsHeight: CGFloat = 18
    private let insetHorizontalPad: CGFloat = 16  // space between image and dark inset sides
    private let insetBottomPad: CGFloat = 10

    // Multi-image masonry
    private let masonryHorizontalPad: CGFloat = 8
    private let masonryTopPad: CGFloat = 6      // small gap below header
    private let masonryBottomPad: CGFloat = 8
    private let masonryColumnSpacing: CGFloat = 8
    private let masonryRowSpacing: CGFloat = 8
    private let masonryColumnWidth: CGFloat = 150
    private let masonryColumns: Int = 2
    /// Max visible cards-area height before the masonry view starts scrolling.
    /// Fits exactly 2 rows (4 cards).
    private let masonryMaxScrollHeight: CGFloat = 560

    // Colors. The semantic ones (windowBackgroundColor, labelColor, etc.)
    // are dynamic NSColors that resolve against NSApp.effectiveAppearance,
    // so flipping the Theme menu updates the panel on next rebuild.
    fileprivate static let panelBackground   = NSColor.windowBackgroundColor
    fileprivate static let middleBackground  = NSColor.underPageBackgroundColor
    /// Always-dark image canvas — stays dark in light mode too because the
    /// image needs a neutral dark frame to read against.
    fileprivate static let darkInset         = NSColor(white: 0.07, alpha: 1)
    fileprivate static let bottomBar         = NSColor(white: 0.32, alpha: 1)
    fileprivate static let separator         = NSColor.separatorColor
    fileprivate static let pillBackground    = NSColor(white: 1, alpha: 0.10)
    fileprivate static let pillBackgroundLight = NSColor(white: 1, alpha: 0.16)
    fileprivate static let textDark          = NSColor.labelColor
    fileprivate static let textSecondary     = NSColor.secondaryLabelColor
    fileprivate static let textOnDark        = NSColor.white
    fileprivate static let textOnDarkSecondary = NSColor(white: 1, alpha: 0.70)
    fileprivate static let thumbPlaceholder  = NSColor.tertiaryLabelColor
    fileprivate static let filmstripBorder   = NSColor.systemBlue
    fileprivate static let accentBlue        = NSColor.systemBlue

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
    private var currentMode: Mode = .grid
    private var currentInfos: [MediaInfo] = []
    private var selectedIndex: Int = 0

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
    private weak var masonryScrollView: NSScrollView?
    private weak var masonryDocView: NSView?

    /// When pinned, hidePanel() is ignored and the close (X) button shows.
    /// New previews via showLoading() reset this to false.
    private var isPinned: Bool = false
    /// Frame saved after the user manually drags the panel.  Used so the
    /// next preview opens in the same spot rather than re-snapping to the
    /// mouse cursor.
    private var savedPosition: NSRect?

    private var followTimer: Timer?
    private var lastSyncedFrame: NSRect = .zero
    private var escapeLocalMonitor: Any?
    private var escapeGlobalMonitor: Any?

    private enum Mode { case singleCard, grid }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
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
            self?.savedPosition = self?.frame
        }
        NotificationCenter.default.addObserver(
            forName: .init("ContentPanelDidClose"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forceHidePanel()
        }
        NotificationCenter.default.addObserver(
            forName: .authDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateLoginButtonState()
        }
        installEscapeKeyMonitors()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        forceHidePanel()
    }

    private func installEscapeKeyMonitors() {
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.shouldCloseForEscape(event) else { return event }
            self.forceHidePanel()
            return nil
        }

        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.shouldCloseForEscape(event) else { return }
            DispatchQueue.main.async {
                self.forceHidePanel()
            }
        }
    }

    private func shouldCloseForEscape(_ event: NSEvent) -> Bool {
        isVisible && event.keyCode == 53
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
        guard followTimer == nil else { return }
        lastSyncedFrame = self.frame
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let currentFrame = self.frame
            guard !NSEqualRects(currentFrame, self.lastSyncedFrame) else { return }
            self.lastSyncedFrame = currentFrame
            ContentPanel.shared.syncPosition(to: currentFrame)
        }
    }

    func stopFollowingContentPanel() {
        followTimer?.invalidate()
        followTimer = nil
    }

    // MARK: - Public API

    func showLoading(infos: [MediaInfo], at mouseLocation: NSPoint) {
        guard !infos.isEmpty else {
            forceHidePanel()
            return
        }
        ContentPanel.shared.resetFollowState()
        startFollowingContentPanel()
        teardownTiles()
        anchorPoint = mouseLocation
        currentMode = infos.count == 1 ? .singleCard : .grid
        currentInfos = infos
        selectedIndex = 0

        let mainContent = buildContainer(infos: infos)
        let root = buildRootView(mainContent: mainContent)

        relayoutPanel(contentSize: root.frame.size)
        contentView = root

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    private func buildRootView(mainContent: NSView) -> NSView {
        let navBar = buildNavigationBar(width: mainContent.frame.width)
        let rootWidth = mainContent.frame.width
        let rootHeight = headerHeight + mainContent.frame.height

        let root = NSView(frame: NSRect(x: 0, y: 0, width: rootWidth, height: rootHeight))
        root.wantsLayer = true
        root.layer?.cornerRadius = panelCornerRadius
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = Self.resolvedCG(Self.panelBackground)

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
        guard tiles.indices.contains(index) else { return }
        let tile = tiles[index]
        if let m = media {
            tile.setLoaded(m)
            if index < currentInfos.count {
                var updatedInfo = currentInfos[index]
                updatedInfo.dimensions = m.naturalSize
                currentInfos[index] = updatedInfo
                tile.updateInfo(updatedInfo)
                // Header title is intentionally static ("Glance") — do
                // not overwrite it with the filename when media finishes loading.
            }
        } else {
            tile.setFailed(message: failedMessage)
        }
        if currentMode == .singleCard, tiles.count == 1, let m = media {
            relayoutSingleCard(with: m)
        } else if currentMode == .grid {
            relayoutMasonry()
        }
    }

    /// Push a disambiguation hint (e.g. "~/Desktop") onto the tile at `index`.
    /// Safe to call before or after the tile's media has loaded.
    func applyHint(at index: Int, hint: String?) {
        guard tiles.indices.contains(index), index < currentInfos.count else { return }
        var info = currentInfos[index]
        info.disambiguationHint = hint
        currentInfos[index] = info
        tiles[index].updateInfo(info)
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
        forceHidePanel(dismissContent: true)
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
            ctx.duration = 0.15
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
        case .singleCard: return buildSingleCard(info: infos[0])
        case .grid:       return buildList(infos: infos)
        }
    }

    func buildPreviewContainer(infos: [MediaInfo]) -> NSView {
        teardownTiles()
        currentMode = infos.count == 1 ? .singleCard : .grid
        currentInfos = infos
        selectedIndex = 0
        return buildContainer(infos: infos)
    }

    // MARK: - Single-card layout

    private func buildSingleCard(info: MediaInfo) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0,
                                        width: singleCardWidth,
                                        height: singleCardImageHeight))
        view.wantsLayer = true
        view.layer?.backgroundColor = Self.darkInset.cgColor

        let tile = MediaTileView(info: info, style: .singleCard, frame: view.bounds)
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
            self.openInViewer(info: self.currentInfos[0])
        }
        view.addSubview(tile)

        tiles = [tile]
        return view
    }

    // MARK: - Multi-image masonry layout

    private func buildList(infos: [MediaInfo]) -> NSView {
        let cols = masonryColumns
        let colW = masonryColumnWidth
        let spacing = masonryColumnSpacing
        let rowSpacing = masonryRowSpacing

        // Two-column shortest-column packing.
        var colHeights = Array(repeating: masonryTopPad, count: cols)
        var visualLayouts: [(x: CGFloat, visualY: CGFloat, w: CGFloat, h: CGFloat)] = []

        for info in infos {
            let shortest = colHeights.enumerated().min(by: { $0.element < $1.element })?.0 ?? 0
            let x = masonryHorizontalPad + CGFloat(shortest) * (colW + spacing)
            let visualY = colHeights[shortest]
            let cardHeight = colW * 16 / 9

            visualLayouts.append((x: x, visualY: visualY, w: colW, h: cardHeight))
            colHeights[shortest] = visualY + cardHeight + rowSpacing
        }

        let cardsBottomVisualY = (colHeights.map { $0 - rowSpacing }.max() ?? masonryTopPad)
        let cardsTotalHeight = cardsBottomVisualY + masonryBottomPad
        let contentWidth = CGFloat(cols) * colW + CGFloat(cols - 1) * spacing + masonryHorizontalPad * 2
        let visibleCardsHeight = min(cardsTotalHeight, masonryMaxScrollHeight)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: visibleCardsHeight))
        container.wantsLayer = true
        let isDark = Self.isDarkAppearance
        container.layer?.backgroundColor = isDark ? NSColor.black.cgColor : Self.resolvedCG(Self.panelBackground)

        let scrollView = NSScrollView(frame: container.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        container.addSubview(scrollView)
        masonryScrollView = scrollView

        let docView = FlippedDocView(frame: NSRect(x: 0, y: 0,
                                                    width: contentWidth,
                                                    height: cardsTotalHeight))
        masonryDocView = docView

        var newTiles: [MediaTileView] = []
        for (i, info) in infos.enumerated() {
            let layout = visualLayouts[i]
            let frame = NSRect(x: layout.x, y: layout.visualY,
                                width: layout.w, height: layout.h)
            let tile = MediaTileView(info: info, style: .masonry, frame: frame)
            let url = info.url
            tile.onDownload = { [weak self, weak tile] in
                guard let tile = tile else { return }
                self?.downloadRemote(url: url, tile: tile)
            }
            tile.onTileTap = { [weak self] in
                guard let self = self, self.currentInfos.indices.contains(i) else { return }
                self.openInViewer(info: self.currentInfos[i])
            }
            docView.addSubview(tile)
            newTiles.append(tile)
        }
        scrollView.documentView = docView
        // Start scrolled to the top of the document.
        docView.scroll(NSPoint(x: 0, y: 0))

        tiles = newTiles
        return container
    }

    private func relayoutMasonry() {
        guard currentMode == .grid, !tiles.isEmpty else { return }
        let cols = masonryColumns
        let colW = masonryColumnWidth
        let spacing = masonryColumnSpacing
        let rowSpacing = masonryRowSpacing

        var colHeights = Array(repeating: masonryTopPad, count: cols)
        var visualLayouts: [(x: CGFloat, visualY: CGFloat, w: CGFloat, h: CGFloat)] = []

        for info in currentInfos {
            let shortest = colHeights.enumerated().min(by: { $0.element < $1.element })?.0 ?? 0
            let x = masonryHorizontalPad + CGFloat(shortest) * (colW + spacing)
            let visualY = colHeights[shortest]
            let cardHeight = colW * 16 / 9
            visualLayouts.append((x: x, visualY: visualY, w: colW, h: cardHeight))
            colHeights[shortest] = visualY + cardHeight + rowSpacing
        }

        let cardsBottomVisualY = (colHeights.map { $0 - rowSpacing }.max() ?? masonryTopPad)
        let cardsTotalHeight = cardsBottomVisualY + masonryBottomPad
        let contentWidth = CGFloat(cols) * colW + CGFloat(cols - 1) * spacing + masonryHorizontalPad * 2
        let visibleCardsHeight = min(cardsTotalHeight, masonryMaxScrollHeight)
        let totalHeight = headerHeight + visibleCardsHeight

        guard let root = contentView else { return }
        root.frame = NSRect(x: 0, y: 0, width: contentWidth, height: totalHeight)

        // Reposition the navigation bar at the top of the root view.
        navBarView?.frame = NSRect(x: 0, y: totalHeight - headerHeight,
                                   width: contentWidth, height: headerHeight)

        masonryScrollView?.frame = NSRect(x: 0, y: 0,
                                           width: contentWidth,
                                           height: visibleCardsHeight)
        masonryDocView?.frame = NSRect(x: 0, y: 0,
                                        width: contentWidth,
                                        height: cardsTotalHeight)

        // Tiles live in a flipped document view — visualY maps directly.
        for (i, layout) in visualLayouts.enumerated() where i < tiles.count {
            tiles[i].frame = NSRect(x: layout.x, y: layout.visualY,
                                     width: layout.w, height: layout.h)
            tiles[i].relayoutChildren()
        }
        relayoutPanel(contentSize: NSSize(width: contentWidth, height: totalHeight))
    }

    // MARK: - Navigation bar (fixed at top)

    private func buildNavigationBar(width: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Self.resolvedCG(Self.panelBackground)

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = Self.resolvedCG(Self.separator)
        sep.autoresizingMask = [.width]
        bar.addSubview(sep)

        let closeBtn = makeIconButton(symbol: "xmark", action: #selector(closeButtonTapped), tint: Self.textDark)
        closeBtn.frame = NSRect(x: 12, y: (headerHeight - 24) / 2, width: 24, height: 24)
        closeBtn.tag = 1
        bar.addSubview(closeBtn)
        singleCloseBtn = closeBtn

        let titleLbl = NSTextField(labelWithString: "Glance".localized)
        titleLbl.textColor = Self.textDark
        titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLbl.alignment = .center
        titleLbl.lineBreakMode = .byTruncatingMiddle
        titleLbl.maximumNumberOfLines = 1
        titleLbl.frame = NSRect(x: 48, y: (headerHeight - 18) / 2, width: width - 96, height: 18)
        titleLbl.autoresizingMask = [.width]
        titleLbl.tag = 3
        bar.addSubview(titleLbl)
        singleHeaderTitle = titleLbl

        let loginBtn = makeIconButton(symbol: "person.circle", action: #selector(loginButtonTapped), tint: Self.textDark)
        loginBtn.frame = NSRect(x: width - 36, y: (headerHeight - 24) / 2, width: 24, height: 24)
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
        meta.maximumNumberOfLines = 2
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
        forceHidePanel()
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
        let panel = ContentPanel.shared
        panel.load(info: info)

        let mainFrame = self.frame
        let contentSize = NSSize(width: 700, height: 600)
        let originX = mainFrame.maxX
        let originY = mainFrame.maxY - contentSize.height
        let frame = NSRect(origin: CGPoint(x: originX, y: originY), size: contentSize)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        if currentMode == .singleCard {
            forceHidePanel()
        }
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
        if let saved = savedPosition {
            var frame = saved
            frame.size = contentSize
            setFrame(frame, display: true)
        } else {
            let frame = ScreenManager.shared.adjustedFrame(for: contentSize, at: anchorPoint, offset: anchorOffset)
            setFrame(frame, display: true)
        }
    }

    private func teardownTiles() {
        for tile in tiles { tile.teardown() }
        tiles.removeAll()
        currentInfos.removeAll()
        singleHeaderTitle = nil
        singleCloseBtn = nil
        singlePinBtn = nil
        masonryScrollView = nil
        masonryDocView = nil
        bottomFilenameLabel = nil
        bottomDimsLabel = nil
        bottomSizeLabel = nil
        topPillLabel = nil
        metaPillFilename = nil
        metaPillMeta = nil
    }
}

/// Flipped document view so masonry tiles can be laid out with visualY
/// (increasing downward) — matches how `relayoutMasonry` computes positions.
final class FlippedDocView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Tile view

final class MediaTileView: NSView {
    enum Style { case singleCard, masonry }

    var info: MediaInfo
    let style: Style

    private let mediaContainer = NSView()
    private let imageLayer = CALayer()
    private let spinner = NSProgressIndicator()
    private let loadingLabel = NSTextField(labelWithString: "Loading…".localized)
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

    private var playerView: AVPlayerView?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    var onClose: (() -> Void)?
    var onAction: (() -> Void)?
    var onDownload: (() -> Void)?
    /// Called when the user clicks anywhere on the tile body (used to open
    /// markdown/webpage tiles in the viewer window).
    var onTileTap: (() -> Void)?

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
            layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor

            mediaContainer.wantsLayer = true
            mediaContainer.layer?.masksToBounds = true
            mediaContainer.layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
            addSubview(mediaContainer)

            // Subtle shimmer while the image loads.
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

            imageLayer.contentsGravity = .resizeAspect
            imageLayer.masksToBounds = true
            mediaContainer.layer?.addSublayer(imageLayer)

            // Bottom dark gradient + filename/dims/size labels overlaid on the image.
            overlayGradient.colors = [
                NSColor(white: 0, alpha: 0.85).cgColor,
                NSColor(white: 0, alpha: 0.45).cgColor,
                NSColor(white: 0, alpha: 0.0).cgColor
            ]
            overlayGradient.locations = [0.0, 0.55, 1.0]
            overlayGradient.startPoint = CGPoint(x: 0.5, y: 0)
            overlayGradient.endPoint = CGPoint(x: 0.5, y: 1)
            overlayGradient.isHidden = true
            mediaContainer.layer?.addSublayer(overlayGradient)

            let nameLbl = NSTextField(labelWithString: info.filename)
            nameLbl.textColor = .white
            nameLbl.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            nameLbl.lineBreakMode = .byTruncatingMiddle
            nameLbl.maximumNumberOfLines = 1
            nameLbl.isHidden = true
            addSubview(nameLbl)
            filenameLabel = nameLbl

            let dimsLbl = NSTextField(labelWithString: "")
            dimsLbl.textColor = NSColor(white: 1, alpha: 0.85)
            dimsLbl.font = NSFont.systemFont(ofSize: 12)
            dimsLbl.lineBreakMode = .byTruncatingTail
            dimsLbl.maximumNumberOfLines = 1
            dimsLbl.isHidden = true
            addSubview(dimsLbl)
            dimsLabel = dimsLbl

            // Retained for API compatibility; the meta line collapses
            // dimensions + size + format into `dimsLabel`, so this stays
            // hidden and off-frame.
            let sizeLbl = NSTextField(labelWithString: "")
            sizeLbl.isHidden = true
            addSubview(sizeLbl)
            sizeLabel = sizeLbl

        case .masonry:
            // Image fills the entire card; text overlay sits in the top-left.
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let tileBg = isDark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.18, alpha: 1)
            layer?.cornerRadius = 8
            layer?.masksToBounds = true
            layer?.backgroundColor = tileBg.cgColor

            mediaContainer.wantsLayer = true
            mediaContainer.layer?.masksToBounds = true
            mediaContainer.layer?.backgroundColor = tileBg.cgColor
            addSubview(mediaContainer)

            // Animated shimmer band — moves left→right while the image is loading.
            shimmerLayer.colors = [
                NSColor(white: 1, alpha: 0).cgColor,
                NSColor(white: 1, alpha: 0.10).cgColor,
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

            // Dark gradient on the bottom edge so the white text overlay is readable.
            // Must live above the image layer (same container) and below the text NSTextFields.
            overlayGradient.colors = [
                NSColor(white: 0, alpha: 0.88).cgColor,
                NSColor(white: 0, alpha: 0.75).cgColor,
                NSColor(white: 0, alpha: 0.0).cgColor
            ]
            overlayGradient.locations = [0.0, 0.55, 1.0]
            overlayGradient.startPoint = CGPoint(x: 0.5, y: 0)
            overlayGradient.endPoint = CGPoint(x: 0.5, y: 1)
            overlayGradient.isHidden = true
            mediaContainer.layer?.addSublayer(overlayGradient)

            let nameLbl = NSTextField(labelWithString: info.filename)
            nameLbl.textColor = .white
            nameLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            nameLbl.lineBreakMode = .byTruncatingMiddle
            nameLbl.maximumNumberOfLines = 1
            nameLbl.isHidden = true
            addSubview(nameLbl)
            filenameLabel = nameLbl

            let dimsLbl = NSTextField(labelWithString: "")
            dimsLbl.textColor = NSColor(white: 1, alpha: 0.95)
            dimsLbl.font = NSFont.systemFont(ofSize: 11)
            dimsLbl.lineBreakMode = .byTruncatingTail
            dimsLbl.maximumNumberOfLines = 1
            dimsLbl.isHidden = true
            addSubview(dimsLbl)
            dimsLabel = dimsLbl

            // Retained for API compatibility; meta info collapses into dimsLabel.
            let sizeLbl = NSTextField(labelWithString: "")
            sizeLbl.isHidden = true
            addSubview(sizeLbl)
            sizeLabel = sizeLbl
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
              info.kind == .markdown || info.kind == .text else { return }

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
        switch style {
        case .singleCard:
            mediaContainer.frame = bounds
            imageLayer.frame = mediaContainer.bounds
            playerView?.frame = mediaContainer.bounds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let gradH: CGFloat = 96
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
            // Two-row overlay: big filename above, single meta line below.
            filenameLabel?.frame = NSRect(x: textX, y: 36, width: textW, height: 22)
            dimsLabel?.frame     = NSRect(x: textX, y: 14, width: textW, height: 18)
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
            mediaContainer.frame = bounds
            imageLayer.frame = mediaContainer.bounds
            playerView?.frame = mediaContainer.bounds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let gradientH: CGFloat = 76
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
            // Two-row overlay: filename + one merged meta line.
            filenameLabel?.frame = NSRect(x: textX, y: 28, width: textW, height: 18)
            dimsLabel?.frame     = NSRect(x: textX, y: 10, width: textW, height: 14)
            sizeLabel?.frame     = .zero
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
        loadingLabel.stringValue = message ?? "Failed".localized
        loadingLabel.textColor = .systemRed
        stopShimmer()
        filenameLabel?.isHidden = false
        dimsLabel?.isHidden = false
        overlayGradient.isHidden = false
        // Dim the kind placeholder so the "Failed" label reads clearly.
        placeholderIconView?.alphaValue = 0.35
        if style == .masonry {
            dimsLabel?.stringValue = message ?? "Failed to load".localized
            dimsLabel?.textColor = .systemRed
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

    override func mouseDown(with event: NSEvent) {
        switch info.kind {
        case .image, .webPage, .markdown, .text, .pdf:
            onTileTap?()
        case .other:
            if info.isLocal {
                if info.url.pathExtension.lowercased() == "app" {
                    NSWorkspace.shared.open(info.url)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([info.url])
                }
            } else {
                NSWorkspace.shared.open(info.url)
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
            // Plain-text-ish file: format + optional location hint, joined.
            filenameLabel?.stringValue = info.filename
            var pieces: [String] = []
            if !info.formatName.isEmpty { pieces.append(info.formatName) }
            if let bytes = info.fileSize {
                let f = ByteCountFormatter()
                f.countStyle = .file
                pieces.append(f.string(fromByteCount: bytes))
            }
            if let hint = info.disambiguationHint, !hint.isEmpty {
                pieces.append(String(format: "in %@".localized, hint))
            }
            dimsLabel?.stringValue = pieces.joined(separator: " · ")
            sizeLabel?.stringValue = ""
        case .webPage:
            // Show host on the filename line, full URL on the meta line.
            filenameLabel?.stringValue = info.url.host ?? info.filename
            dimsLabel?.stringValue = info.url.absoluteString
            sizeLabel?.stringValue = ""
        case .other:
            // Non-previewable file — show extension/size/hint as the meta line.
            filenameLabel?.stringValue = info.filename
            var pieces: [String] = []
            if !info.formatName.isEmpty { pieces.append(info.formatName) }
            if let bytes = info.fileSize {
                let f = ByteCountFormatter()
                f.countStyle = .file
                pieces.append(f.string(fromByteCount: bytes))
            }
            if let hint = info.disambiguationHint, !hint.isEmpty {
                pieces.append(String(format: "in %@".localized, hint))
            }
            dimsLabel?.stringValue = pieces.joined(separator: " · ")
            sizeLabel?.stringValue = ""
        }
    }

    private func applyMediaText(info: MediaInfo) {
        filenameLabel?.stringValue = info.filename

        // One-line meta: dimensions · size · format · location-hint.
        // The line truncates with an ellipsis if too long; trailing labels
        // (hint, format) are dropped first by virtue of order.
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
        if let hint = info.disambiguationHint, !hint.isEmpty {
            pieces.append(String(format: "in %@".localized, hint))
        }
        dimsLabel?.stringValue = pieces.joined(separator: " · ")
        sizeLabel?.stringValue = ""
    }
}

final class PassthroughPlayerView: AVPlayerView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
