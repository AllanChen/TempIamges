import AppKit
import UniformTypeIdentifiers
import ImageIO
import WebKit
import Vision

final class ImageInspectSession {
    enum Mode { case focus, browse, compare }
    enum ComparisonStyle { case sideBySide, slider }

    var infos: [MediaInfo]
    var images: [NSImage?]
    var focusedIndex: Int
    var mode: Mode
    var compareIndices: (Int, Int)?
    var comparisonStyle: ComparisonStyle = .sideBySide
    /// Which compare slot a filmstrip tap replaces: 0 = left (A), 1 = right (B).
    var activeCompareSlot = 1
    var metadata: [ImageTechnicalMetadata?]
    var failedIndices = Set<Int>()

    init(infos: [MediaInfo], images: [NSImage?], focusedIndex: Int, mode: Mode? = nil) {
        self.infos = infos
        self.images = images
        self.focusedIndex = min(max(0, focusedIndex), max(0, infos.count - 1))
        // Multiple items still open as a single-image Focus view. The
        // filmstrip remains available; Compare is entered explicitly.
        self.mode = mode ?? .focus
        self.metadata = Array(repeating: nil, count: infos.count)
        if self.mode == .compare, infos.count >= 2 {
            compareIndices = (0, 1)
        }
    }
}

final class ImageInspectWindow: NSWindow, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onOpenVideo: ((MediaInfo) -> Void)?
    var onOpenContent: ((MediaInfo) -> Void)?

    private let imageLoader: ImageLoader
    private let pathDetector = PathDetector()
    private var session: ImageInspectSession?
    private var loadGeneration = UUID()

    private let focusButton = InspectToolbarButton(symbol: "photo", tooltip: "Focus".localized)
    private let sideBySideButton = InspectToolbarButton(symbol: "rectangle.split.2x1", tooltip: "Side by side".localized)
    private let sliderButton = InspectToolbarButton(symbol: "slider.horizontal.3", tooltip: "Slider".localized)
    private let infoButton = InspectToolbarButton(symbol: "info.circle", tooltip: "Image information".localized)
    private let revealButton = InspectToolbarButton(symbol: "folder", tooltip: "Reveal in Finder".localized)
    private let openURLButton = InspectToolbarButton(symbol: "globe", tooltip: "Open image URL".localized)
    private let actionsButton = InspectToolbarButton(symbol: "ellipsis", tooltip: "Actions".localized)
    private let widgetMarketButton = InspectToolbarButton(symbol: "square.grid.2x2", tooltip: "Widget Market".localized)
    private let widgetTasksButton = InspectToolbarButton(symbol: "tray.full", tooltip: "Tasks".localized)
    private let pinButton = InspectToolbarButton(symbol: "pin", tooltip: "Pin on Top".localized)
    private var isPinned = false
    /// Themed action menu panel (frosted dark, warm-cue selection); rebuilt
    /// per presentation so enabled states and titles are always fresh.
    private var actionsPanel: ActionMenuPanel?
    private lazy var errorTooltip = ErrorTooltip()
    private lazy var toastWindow = InspectToastWindow()
    private let canvasContainer = MediaDropCanvasView()
    private let primaryViewport = InspectImageViewport()
    private let secondaryViewport = InspectImageViewport()
    private let sliderViewport = ImageRevealView()
    /// Inline file preview for mixed-content sessions: text/markdown/pdf/web
    /// render in the web view; video/unsupported/folder use the placeholder.
    private let fileWebView = InspectFileWebView()
    private let filePlaceholder = FilePlaceholderView()
    private var fileContentGeneration = UUID()
    private let filmstrip = ImageFilmstripView()
    private let infoPanel = ImageDifferencePanel()
    private let identityBar = InspectIdentityBar()
    private let identityNameLabel = NSTextField(labelWithString: "")
    private let identityMetaLabel = NSTextField(labelWithString: "")
    private let toolbarBar = InspectIdentityBar()
    private var toolbarHideWorkItem: DispatchWorkItem?
    private var isClosingProgrammatically = false
    private let toolbarHeight: CGFloat = 44
    private var imageHoverFrame = NSRect.zero
    /// Separate window hosting the info panel so the user can move it freely.
    /// It is attached as a CHILD window (not floating), so it stays above the
    /// main window but is covered together with it by other windows.
    private lazy var infoWindow = ImageInfoPanelWindow(panel: infoPanel)
    private var infoVisible = false
    /// Slide-out OCR result panel — a child window like the info panel.
    private lazy var ocrWindow = OCRResultWindow()
    private var ocrVisible = false
    private var ocrGeneration = UUID()
    private var handledWidgetTaskIDs = Set<UUID>()
    private let identityBarHeight: CGFloat = 54

    init(imageLoader: ImageLoader) {
        self.imageLoader = imageLoader
        let initialFrame = ScreenManager.shared.contentFrame(for: NSSize(width: 1040, height: 760))
        super.init(contentRect: initialFrame,
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Image Inspect".localized
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = PanelStyle.imageCanvas
        minSize = NSSize(width: 640, height: 440)
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        delegate = self
        buildUI()
        handledWidgetTaskIDs = Set(WidgetTaskManager.shared.records.filter { $0.phase == .completed }.map(\.id))
        NotificationCenter.default.addObserver(self, selector: #selector(localizationDidChange),
                                               name: .languageDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(widgetTasksDidChange),
                                               name: WidgetTaskManager.didChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show(infos: [MediaInfo], loaded: [LoadedMedia?], focusedIndex: Int,
              preferredMode: ImageInspectSession.Mode? = nil) {
        guard !infos.isEmpty else { return }
        let images = loaded.map { media -> NSImage? in
            guard case .image(let image, _) = media else { return nil }
            return image
        }
        session = ImageInspectSession(infos: infos, images: images, focusedIndex: focusedIndex,
                                      mode: preferredMode)
        Logger.info("ImageInspectWindow: opened \(infos.count) item(s) in \(session?.mode == .compare ? "compare" : "focus") mode")
        toolbarHideWorkItem?.cancel()
        toolbarHideWorkItem = nil
        toolbarBar.alphaValue = 0
        toolbarBar.isHidden = true
        identityBar.alphaValue = 0
        identityBar.isHidden = true
        filmstrip.alphaValue = 0
        filmstrip.isHidden = true
        loadGeneration = UUID()
        renderSession()
        loadSessionImages(generation: loadGeneration)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        toolbarHideWorkItem?.cancel()
        actionsPanel?.dismissChain()
        actionsPanel = nil
        removeChildWindow(toastWindow)
        toastWindow.orderOut(nil)
        removeChildWindow(infoWindow)
        infoWindow.orderOut(nil)
        infoVisible = false
        removeChildWindow(ocrWindow)
        ocrWindow.orderOut(nil)
        ocrVisible = false
        ocrGeneration = UUID()
        session = nil
        loadGeneration = UUID()
        guard !isClosingProgrammatically else { return }
        onClose?()
    }

    /// Close without restoring the app that was active before Image Inspect.
    /// Used when a drop hands the user directly to another Glance viewer.
    func closeForViewerHandoff() {
        isClosingProgrammatically = true
        close()
        isClosingProgrammatically = false
    }

    override func cancelOperation(_ sender: Any?) {
        guard let session else { return }
        if session.mode == .compare {
            session.mode = session.infos.count > 1 ? .browse : .focus
            session.compareIndices = nil
            renderSession()
        } else {
            closeAndRestore()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // A presented sheet owns its keyboard input. In particular, do not
        // let the image window's global ⌘V shortcut consume paste intended
        // for the URL field in the Open sheet.
        guard attachedSheet == nil else { return super.performKeyEquivalent(with: event) }
        guard session != nil else { return super.performKeyEquivalent(with: event) }
        let key = event.charactersIgnoringModifiers ?? ""
        if event.modifierFlags.contains(.command) {
            if key == "0" { activeViewports.forEach { $0.fitToView() }; return true }
            if key == "1" { activeViewports.forEach { $0.setActualSize() }; return true }
            if key.lowercased() == "i" { toggleInfo(); return true }
            // Image actions only intercept when the active item is an image —
            // otherwise fall through so e.g. ⌘C still copies text in the
            // inline file preview.
            if key.lowercased() == "l", activeItemIsImage { rotateActive(byQuarters: -1); return true }
            if key.lowercased() == "r", activeItemIsImage { rotateActive(byQuarters: 1); return true }
            if key.lowercased() == "c", activeItemIsImage { copyActiveImage(); return true }
            if key.lowercased() == "s", activeItemIsImage { quickSaveActiveImage(); return true }
            if key.lowercased() == "v", pasteRemoteImageFromClipboard() { return true }
        }
        switch event.keyCode {
        case 123:
            navigate(by: -1)
            return true
        case 124:
            navigate(by: 1)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        // AppKit may deliver trackpad magnify events to the window's responder
        // instead of the image view under the cursor. Route them explicitly so
        // Focus, side-by-side, and slider all use the same viewport gesture.
        if event.type == .magnify, let session {
            let point = canvasContainer.convert(event.locationInWindow, from: nil)
            var handled = true
            if session.mode == .compare, session.comparisonStyle == .sideBySide {
                if primaryViewport.frame.contains(point) {
                    primaryViewport.magnify(with: event)
                } else if secondaryViewport.frame.contains(point) {
                    secondaryViewport.magnify(with: event)
                }
            } else if session.mode == .compare, session.comparisonStyle == .slider {
                sliderViewport.magnify(with: event)
            } else if !primaryViewport.isHidden {
                primaryViewport.magnify(with: event)
            } else {
                handled = false
            }
            if handled { return }
        }
        if event.type == .scrollWheel, let session {
            let point = canvasContainer.convert(event.locationInWindow, from: nil)
            if session.mode == .compare, session.comparisonStyle == .sideBySide {
                if primaryViewport.frame.contains(point) {
                    primaryViewport.scrollWheel(with: event)
                    return
                } else if secondaryViewport.frame.contains(point) {
                    secondaryViewport.scrollWheel(with: event)
                    return
                }
            } else if session.mode == .compare, session.comparisonStyle == .slider,
                      sliderViewport.frame.contains(point) {
                sliderViewport.scrollWheel(with: event)
                return
            } else if !primaryViewport.isHidden, primaryViewport.frame.contains(point) {
                primaryViewport.scrollWheel(with: event)
                return
            }
        }
        if event.type == .leftMouseDown,
           let session,
           session.mode == .compare,
           session.comparisonStyle == .sideBySide {
            let point = canvasContainer.convert(event.locationInWindow, from: nil)
            let overlays = [toolbarBar, identityBar, filmstrip]
            let hitsVisibleOverlay = overlays.contains { view in
                !view.isHidden && view.alphaValue >= 0.05 && view.frame.contains(point)
            }
            if !hitsVisibleOverlay {
                if primaryViewport.frame.contains(point) {
                    selectCompareSlot(0)
                } else if secondaryViewport.frame.contains(point) {
                    selectCompareSlot(1)
                }
            }
        }
        if event.type == .mouseMoved {
            let point = canvasContainer.convert(event.locationInWindow, from: nil)
            if imageHoverFrame.contains(point) {
                showToolbar()
            } else {
                hideToolbar()
            }
            updateInfoHighlight(atWindowPoint: event.locationInWindow)
        }
        super.sendEvent(event)
    }

    /// Highlight the info block for whichever on-screen image the cursor is over.
    private func updateInfoHighlight(atWindowPoint windowPoint: NSPoint) {
        guard let session, infoVisible else { return }
        let p = canvasContainer.convert(windowPoint, from: nil)

        var hovered: Int?
        if session.mode == .compare, let (a, b) = session.compareIndices,
           session.comparisonStyle == .sideBySide {
            if primaryViewport.frame.contains(p) { hovered = a }
            else if secondaryViewport.frame.contains(p) { hovered = b }
        } else if session.mode == .compare, let (a, _) = session.compareIndices {
            // Slider shows A underneath B; treat the whole canvas as image A.
            if sliderViewport.frame.contains(p) { hovered = a }
        } else if primaryViewport.frame.contains(p) {
            hovered = session.focusedIndex
        }
        // No image under the cursor: fall back to the default (active compare
        // slot in compare mode), instead of clearing the glow entirely.
        if hovered == nil {
            if session.mode == .compare, let (a, b) = session.compareIndices {
                hovered = session.activeCompareSlot == 0 ? a : b
            } else {
                hovered = session.focusedIndex
            }
        }
        infoPanel.highlight(index: hovered)
    }

    private func showToolbar() {
        toolbarHideWorkItem?.cancel()
        toolbarHideWorkItem = nil
        if !toolbarBar.isHidden, toolbarBar.alphaValue > 0.99 { return }
        toolbarBar.isHidden = false
        identityBar.isHidden = false
        filmstrip.isHidden = !showsFilmstrip
        [primaryViewport, secondaryViewport].forEach {
            $0.setActiveIndicatorVisible(true, animated: true, duration: 0.22)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toolbarBar.animator().alphaValue = 1
            identityBar.animator().alphaValue = 1
            if showsFilmstrip { filmstrip.animator().alphaValue = 1 }
        }
    }

    private func hideToolbar() {
        if (toolbarBar.isHidden && toolbarHideWorkItem == nil)
            || (toolbarBar.alphaValue < 0.01 && toolbarHideWorkItem == nil) {
            return
        }
        toolbarHideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.toolbarHideWorkItem = nil
            [self.primaryViewport, self.secondaryViewport].forEach {
                $0.setActiveIndicatorVisible(false, animated: true, duration: 0.2)
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.toolbarBar.animator().alphaValue = 0
                self.identityBar.animator().alphaValue = 0
                self.filmstrip.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.toolbarBar.alphaValue < 0.05 else { return }
                self.toolbarBar.isHidden = true
                self.identityBar.isHidden = true
                self.filmstrip.isHidden = true
            })
        }
        toolbarHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private var activeViewports: [InspectImageViewport] {
        guard let session else { return [] }
        if session.mode == .compare, session.comparisonStyle == .sideBySide {
            return [primaryViewport, secondaryViewport]
        }
        if session.mode == .compare { return [sliderViewport.viewport] }
        return [primaryViewport]
    }

    private func buildUI() {
        // Make the registered drop target the window's content view itself.
        // AppKit can otherwise lose the drag destination while walking the
        // layered viewport/WebKit hierarchy above a registered child view.
        contentView = canvasContainer
        let root = canvasContainer
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.imageCanvas.cgColor

        // Image Inspect is the general mixed-content window: accept any file
        // or URL, then classify it after drop. Images stay here; videos route
        // to Video Inspect; documents replace the canvas content inline.
        canvasContainer.acceptsExtension = { _ in true }
        canvasContainer.acceptsImageData = true
        canvasContainer.onDrop = { [weak self] url, point in
            self?.handleDroppedResource(url: url, at: point)
        }
        primaryViewport.dropTarget = canvasContainer
        secondaryViewport.dropTarget = canvasContainer
        sliderViewport.dropTarget = canvasContainer
        fileWebView.dropTarget = canvasContainer
        filePlaceholder.dropTarget = canvasContainer

        for view in [primaryViewport, secondaryViewport, sliderViewport, fileWebView, filePlaceholder] {
            view.autoresizingMask = [.width, .height]
            canvasContainer.addSubview(view)
        }
        fileWebView.isHidden = true
        filePlaceholder.isHidden = true
        primaryViewport.onViewportChange = { [weak self] state in self?.syncViewport(state, source: self?.primaryViewport) }
        secondaryViewport.onViewportChange = { [weak self] state in self?.syncViewport(state, source: self?.secondaryViewport) }
        filmstrip.onSelect = { [weak self] index in self?.focus(index: index) }
        filmstrip.onCompare = { [weak self] index in self?.compare(focusedWith: index) }
        canvasContainer.addSubview(filmstrip)

        configureIdentityLabel(identityNameLabel, font: PanelStyle.headline, color: PanelStyle.textPrimary)
        configureIdentityLabel(identityMetaLabel, font: PanelStyle.caption, color: PanelStyle.textSecondary)
        for label in [identityNameLabel, identityMetaLabel] {
            identityBar.addSubview(label)
        }
        identityBar.alphaValue = 0
        identityBar.isHidden = true
        canvasContainer.addSubview(identityBar, positioned: .above, relativeTo: nil)

        focusButton.target = self
        focusButton.action = #selector(focusModeTapped)
        sideBySideButton.target = self
        sideBySideButton.action = #selector(sideBySideTapped)
        sliderButton.target = self
        sliderButton.action = #selector(sliderTapped)
        infoButton.target = self
        infoButton.action = #selector(infoTapped)
        revealButton.target = self
        revealButton.action = #selector(revealInFinderTapped)
        openURLButton.target = self
        openURLButton.action = #selector(openURLTapped)
        actionsButton.target = self
        actionsButton.action = #selector(actionsTapped)
        widgetMarketButton.target = self
        widgetMarketButton.action = #selector(widgetMarketTapped)
        widgetTasksButton.target = self
        widgetTasksButton.action = #selector(widgetTasksTapped)
        pinButton.target = self
        pinButton.action = #selector(pinTapped)
        pinButton.isActive = isPinned
        for button in [focusButton, sideBySideButton, sliderButton, infoButton,
                       revealButton, openURLButton, actionsButton, widgetMarketButton, widgetTasksButton] {
            button.autoresizingMask = [.minXMargin]
            toolbarBar.addSubview(button)
        }
        pinButton.autoresizingMask = [.minXMargin]
        toolbarBar.addSubview(pinButton)
        // The same themed action menu serves the toolbar ⋯ button and
        // right-clicks on every image surface.
        let menuHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self, let window = event.window else { return }
            let origin = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
            self.presentActionsMenu(atScreenPoint: origin)
        }
        primaryViewport.onActionMenu = menuHandler
        secondaryViewport.onActionMenu = menuHandler
        sliderViewport.onActionMenu = menuHandler
        toolbarBar.alphaValue = 0
        toolbarBar.isHidden = true
        canvasContainer.addSubview(toolbarBar, positioned: .above, relativeTo: nil)
        layoutContent()
    }

    private func configureIdentityLabel(_ label: NSTextField, font: NSFont, color: NSColor) {
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.isSelectable = true
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutContent()
    }

    private func layoutContent() {
        guard contentView === canvasContainer else { return }

        // The info panel is now a separate floating window, so the image always
        // uses the full content width.
        let contentFrame = NSRect(x: 0, y: 0, width: canvasContainer.bounds.width,
                                  height: canvasContainer.bounds.height)

        identityBar.frame = NSRect(x: 0, y: 0, width: contentFrame.width, height: identityBarHeight)
        let labelX: CGFloat = 18
        let labelWidth = max(80, identityBar.bounds.width - labelX * 2)
        identityNameLabel.frame = NSRect(x: labelX, y: 30, width: labelWidth, height: 17)
        identityMetaLabel.frame = NSRect(x: labelX, y: 10, width: labelWidth, height: 15)

        // Floating hover toolbar: restore the original vertically-centered,
        // right-aligned icon group. Pin remains the rightmost action.
        toolbarBar.frame = NSRect(x: 0, y: contentFrame.height - toolbarHeight,
                                  width: contentFrame.width, height: toolbarHeight)
        let buttonSize: CGFloat = 24
        let buttonGap: CGFloat = 8
        let buttons = [focusButton, sideBySideButton, sliderButton, infoButton,
                       revealButton, openURLButton, actionsButton, widgetMarketButton, widgetTasksButton, pinButton]
        var bx = toolbarBar.bounds.width - 12 - buttonSize
        for button in buttons.reversed() {
            button.frame = NSRect(x: bx, y: (toolbarHeight - buttonSize) / 2,
                                  width: buttonSize, height: buttonSize)
            bx -= buttonSize + buttonGap
        }
        imageHoverFrame = contentFrame

        guard let session else {
            primaryViewport.frame = contentFrame
            return
        }
        if session.mode == .compare, session.comparisonStyle == .sideBySide {
            let gap: CGFloat = 1
            let half = (contentFrame.width - gap) / 2
            primaryViewport.frame = NSRect(x: 0, y: 0, width: half, height: contentFrame.height)
            secondaryViewport.frame = NSRect(x: half + gap, y: 0, width: half, height: contentFrame.height)
        } else {
            primaryViewport.frame = contentFrame
            sliderViewport.frame = contentFrame
        }
        // File previews always fill the canvas; only visible in Focus/Browse.
        fileWebView.frame = contentFrame
        filePlaceholder.frame = contentFrame

        filmstrip.frame = NSRect(x: 0, y: identityBarHeight + 12,
                                 width: contentFrame.width, height: 86)
    }

    private func renderSession() {
        guard let session, session.infos.indices.contains(session.focusedIndex) else { return }
        let info = session.infos[session.focusedIndex]
        updateWindowTitle(for: info, index: session.focusedIndex)
        updateIdentityBar(for: info, index: session.focusedIndex)
        // Compare needs two IMAGES; focus/browse only needs multiple items.
        let imageCount = session.infos.filter { $0.kind == .image }.count
        focusButton.isEnabled = session.infos.count >= 2
        sideBySideButton.isEnabled = imageCount >= 2
        sliderButton.isEnabled = imageCount >= 2
        focusButton.isActive = session.mode != .compare
        sideBySideButton.isActive = session.mode == .compare && session.comparisonStyle == .sideBySide
        sliderButton.isActive = session.mode == .compare && session.comparisonStyle == .slider
        infoButton.isActive = infoVisible
        updateRevealButtonState()

        primaryViewport.isHidden = true
        secondaryViewport.isHidden = true
        sliderViewport.isHidden = true
        fileWebView.isHidden = true
        filePlaceholder.isHidden = true
        primaryViewport.isActiveSlot = false
        secondaryViewport.isActiveSlot = false
        primaryViewport.setCompareDimmed(false)
        secondaryViewport.setCompareDimmed(false)
        primaryViewport.setWidgetProcessing(nil)
        secondaryViewport.setWidgetProcessing(nil)
        sliderViewport.viewport.setWidgetProcessing(nil)

        if session.mode == .compare, let (a, b) = session.compareIndices,
           session.infos.indices.contains(a), session.infos.indices.contains(b),
           session.infos[a].kind == .image, session.infos[b].kind == .image {
            if session.comparisonStyle == .sideBySide {
                primaryViewport.isHidden = false
                secondaryViewport.isHidden = false
                primaryViewport.setLoadFailed(session.failedIndices.contains(a))
                secondaryViewport.setLoadFailed(session.failedIndices.contains(b))
                primaryViewport.image = session.images[safe: a] ?? nil
                secondaryViewport.image = session.images[safe: b] ?? nil
                primaryViewport.setWidgetProcessing(WidgetTaskManager.shared.activeRecords(for: session.infos[a].url).first)
                secondaryViewport.setWidgetProcessing(WidgetTaskManager.shared.activeRecords(for: session.infos[b].url).first)
                // Show which side a filmstrip tap will replace.
                primaryViewport.isActiveSlot = session.activeCompareSlot == 0
                secondaryViewport.isActiveSlot = session.activeCompareSlot == 1
                primaryViewport.setCompareDimmed(session.activeCompareSlot != 0)
                secondaryViewport.setCompareDimmed(session.activeCompareSlot != 1)
            } else {
                sliderViewport.isHidden = false
                sliderViewport.setImages(a: session.images[safe: a] ?? nil,
                                         b: session.images[safe: b] ?? nil,
                                         failed: session.failedIndices.contains(a)
                                             || session.failedIndices.contains(b))
                let activeIndex = session.activeCompareSlot == 0 ? a : b
                sliderViewport.viewport.setWidgetProcessing(WidgetTaskManager.shared.activeRecords(for: session.infos[activeIndex].url).first)
            }
            infoPanel.show(items: [
                (a, session.infos[a], session.metadata[safe: a] ?? nil),
                (b, session.infos[b], session.metadata[safe: b] ?? nil),
            ])
        } else {
            // Focus/Browse: images go to the viewport; other kinds render
            // inline (web view for text/markdown/pdf/web, placeholder icon
            // for video/unsupported/folders).
            switch info.kind {
            case .image:
                primaryViewport.isHidden = false
                primaryViewport.setLoadFailed(session.failedIndices.contains(session.focusedIndex))
                primaryViewport.image = session.images[safe: session.focusedIndex] ?? nil
                primaryViewport.setWidgetProcessing(WidgetTaskManager.shared.activeRecords(for: info.url).first)
            case .text, .markdown, .pdf, .webPage:
                fileWebView.isHidden = false
                loadFileContent(for: info)
            default:
                filePlaceholder.isHidden = false
                filePlaceholder.configure(info: info)
            }
            infoPanel.show(items: [
                (session.focusedIndex, info, session.metadata[safe: session.focusedIndex] ?? nil),
            ])
        }

        filmstrip.configure(infos: session.infos, images: session.images,
                            selectedIndex: session.focusedIndex, compareIndices: session.compareIndices)

        // Default glow marks the active compare slot so the user sees which
        // side a filmstrip tap will replace; hover overrides this.
        if session.mode == .compare, let (a, b) = session.compareIndices {
            infoPanel.highlight(index: session.activeCompareSlot == 0 ? a : b)
        } else {
            infoPanel.highlight(index: nil)
        }
        layoutContent()
    }

    private var showsFilmstrip: Bool { (session?.infos.count ?? 0) >= 2 }

    private func loadSessionImages(generation: UUID) {
        guard let session else { return }
        var fullResolutionIndices = Set([session.focusedIndex])
        if session.mode == .compare, let pair = session.compareIndices {
            fullResolutionIndices = Set([pair.0, pair.1])
        }
        for (index, info) in session.infos.enumerated() {
            if info.kind == .image, session.images[safe: index] ?? nil == nil,
               !fullResolutionIndices.contains(index) {
                imageLoader.loadImage(from: info.url) { [weak self] image in
                    guard let self, generation == self.loadGeneration,
                          let session = self.session, session.images.indices.contains(index) else { return }
                    if let image {
                        session.failedIndices.remove(index)
                        session.images[index] = image
                    } else {
                        session.failedIndices.insert(index)
                    }
                    self.renderSession()
                }
            }
            if info.isLocal {
                imageLoader.loadFileSize(from: info.url) { [weak self] bytes in
                    guard let self, generation == self.loadGeneration,
                          let session = self.session, session.infos.indices.contains(index) else { return }
                    session.infos[index].fileSize = bytes
                    self.renderSession()
                }
            }
            guard info.isLocal else { continue }
            imageLoader.loadTechnicalMetadata(from: info.url) { [weak self] metadata in
                guard let self, generation == self.loadGeneration,
                      let session = self.session, session.metadata.indices.contains(index) else { return }
                session.metadata[index] = metadata
                self.renderSession()
            }
        }
        loadFullResolutionForActiveItems(generation: generation)
    }

    private func loadFullResolutionForActiveItems(generation: UUID) {
        guard let session else { return }
        var indices = [session.focusedIndex]
        if session.mode == .compare, let pair = session.compareIndices {
            indices = [pair.0, pair.1]
        }
        for index in Set(indices) where session.infos.indices.contains(index) {
            let info = session.infos[index]
            guard info.kind == .image else { continue }
            imageLoader.loadFullResolutionImage(from: info.url) { [weak self] image in
                guard let self, generation == self.loadGeneration,
                      let session = self.session, session.images.indices.contains(index) else { return }
                if let image {
                    session.failedIndices.remove(index)
                    session.images[index] = image
                    session.infos[index].dimensions = image.size
                } else {
                    session.failedIndices.insert(index)
                }
                self.renderSession()
            }
        }
    }

    @objc private func focusModeTapped() {
        guard let session else { return }
        session.mode = session.infos.count > 1 ? .browse : .focus
        session.compareIndices = nil
        renderSession()
    }

    /// Inline file preview for the focused non-image item. Text/markdown are
    /// fetched and rendered through the shared ContentViewerWindow HTML
    /// helpers; pdf/web pages load directly.
    private func loadFileContent(for info: MediaInfo) {
        let token = UUID()
        fileContentGeneration = token
        switch info.kind {
        case .pdf:
            fileWebView.loadFileURL(info.url, allowingReadAccessTo: info.url.deletingLastPathComponent())
        case .webPage:
            fileWebView.load(URLRequest(url: info.url))
        case .text, .markdown:
            let url = info.url
            let isMarkdown = info.kind == .markdown
            Task { [weak self] in
                let content = await ContentViewerWindow.fetchTextContent(from: url)
                await MainActor.run {
                    guard let self, self.fileContentGeneration == token else { return }
                    let html = isMarkdown
                        ? ContentViewerWindow.wrapMarkdownInHTML(content)
                        : ContentViewerWindow.wrapCodeInHTML(content, language: url.pathExtension)
                    self.fileWebView.loadHTMLString(html, baseURL: nil)
                }
            }
        default:
            break
        }
    }
    @objc private func sideBySideTapped() {
        activateCompare(style: .sideBySide)
    }

    @objc private func sliderTapped() {
        activateCompare(style: .slider)
    }

    private func activateCompare(style: ImageInspectSession.ComparisonStyle) {
        guard let session else { return }
        // Compare is images-only: file items never enter a compare pair.
        let imageIndices = session.infos.indices.filter { session.infos[$0].kind == .image }
        guard imageIndices.count >= 2 else { return }
        session.comparisonStyle = style
        // A stored pair may reference non-image items after session changes —
        // validate before reusing it.
        if let pair = session.compareIndices,
           session.infos[safe: pair.0]?.kind != .image || session.infos[safe: pair.1]?.kind != .image {
            session.compareIndices = nil
        }
        if session.compareIndices == nil {
            let first = imageIndices.contains(session.focusedIndex) ? session.focusedIndex : imageIndices[0]
            let second = imageIndices.first { $0 != first } ?? imageIndices[0]
            session.compareIndices = (first, second)
            session.activeCompareSlot = 1
        }
        session.mode = .compare
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
    }

    @objc private func infoTapped() { toggleInfo() }

    @objc private func localizationDidChange() {
        title = "Image Inspect".localized
        focusButton.updateTooltip("Focus".localized)
        sideBySideButton.updateTooltip("Side by side".localized)
        sliderButton.updateTooltip("Slider".localized)
        infoButton.updateTooltip("Image information".localized)
        revealButton.updateTooltip("Reveal in Finder".localized)
        openURLButton.updateTooltip("Open image URL".localized)
        actionsButton.updateTooltip("Actions".localized)
        pinButton.updateTooltip((isPinned ? "Unpin" : "Pin on Top").localized)
        if infoVisible { infoWindow.title = "Image information".localized }
        ocrWindow.reloadLocalization()
        renderSession()
    }

    @objc private func revealInFinderTapped() {
        guard let info = currentRevealInfo, info.isLocal else { return }
        NSWorkspace.shared.activateFileViewerSelecting([info.url])
    }

    @objc private func pinTapped() {
        isPinned.toggle()
        pinButton.isActive = isPinned
        pinButton.updateTooltip((isPinned ? "Unpin" : "Pin on Top").localized)
        level = isPinned ? .floating : .normal
    }

    // MARK: - Image actions (rotate / export)

    /// Menu entries for the ⋯ button and right-click menu. Rebuilt per
    /// presentation so enablement and localized titles are always current.
    private func buildActionEntries() -> [ActionMenuEntry] {
        let hasActiveWidgetTask = currentRevealInfo.map { !WidgetTaskManager.shared.activeRecords(for: $0.url).isEmpty } ?? false
        let hasImage: Bool = {
            guard let session, let index = currentActionIndex,
                  session.infos.indices.contains(index),
                  session.infos[index].kind == .image else { return false }
            return (session.images[safe: index] ?? nil) != nil && !hasActiveWidgetTask
        }()
        var entries: [ActionMenuEntry] = [
            ActionMenuEntry(title: "Copy Image".localized, shortcut: "⌘C", enabled: hasImage,
                            action: { [weak self] in self?.copyActiveImage() }),
            .separator(),
            ActionMenuEntry(title: "Rotate Left".localized, shortcut: "⌘L", enabled: hasImage,
                            action: { [weak self] in self?.rotateActive(byQuarters: -1) }),
            ActionMenuEntry(title: "Rotate Right".localized, shortcut: "⌘R", enabled: hasImage,
                            action: { [weak self] in self?.rotateActive(byQuarters: 1) }),
            .separator(),
            ActionMenuEntry(title: "Format Conversion".localized, enabled: hasImage, submenu: [
                ActionMenuEntry(title: "To PNG".localized,
                                action: { [weak self] in self?.exportActive(as: .png) }),
                ActionMenuEntry(title: "To JPG".localized,
                                action: { [weak self] in self?.exportActive(as: .jpeg) }),
                ActionMenuEntry(title: "To WebP".localized,
                                action: { [weak self] in self?.exportActive(as: .webP) }),
                ActionMenuEntry(title: "To Icon".localized,
                                action: { [weak self] in self?.exportActive(as: .icns) }),
            ]),
            .separator(),
            ActionMenuEntry(title: "Recognize Text".localized, enabled: hasImage,
                            action: { [weak self] in self?.recognizeTextTapped() }),
        ]
        let widgets = WidgetRegistry.shared.compatible(with: "image")
        if !widgets.isEmpty {
            entries.insert(.separator(), at: 0)
            entries.insert(ActionMenuEntry(title: "Widgets".localized, submenu: widgets.map { widget in
                ActionMenuEntry(title: widget.name, submenu: widget.commands.filter { $0.inputTypes.contains("image") }.map { command in
                    let duplicate = currentRevealInfo.map { info in
                        WidgetTaskManager.shared.activeRecords(for: info.url).contains { $0.widgetID == widget.id && $0.commandID == command.id }
                    } ?? false
                    return ActionMenuEntry(title: command.name, enabled: hasImage && !duplicate, action: { [weak self] in
                        self?.runWidget(widgetID: widget.id, commandID: command.id)
                    })
                })
            }), at: 0)
        }
        return entries
    }

    private func presentActionsMenu(atScreenPoint point: NSPoint) {
        actionsPanel?.dismissChain()
        let panel = ActionMenuPanel(entries: buildActionEntries())
        actionsPanel = panel
        panel.present(at: point)
    }

    @objc private func actionsTapped() {
        let point = actionsButton.convert(NSPoint(x: 0, y: -4), to: nil)
        presentActionsMenu(atScreenPoint: convertToScreen(NSRect(origin: point, size: .zero)).origin)
    }

    @objc private func widgetMarketTapped() {
        WidgetMarketPanel.shared.toggle(from: self)
    }

    @objc private func widgetTasksTapped() {
        (NSApp.delegate as? AppDelegate)?.openTasks()
    }

    private func runWidget(widgetID: String, commandID: String) {
        guard let info = currentRevealInfo, info.kind == .image,
              let widget = WidgetRegistry.shared.installed.first(where: { $0.id == widgetID }),
              let command = widget.commands.first(where: { $0.id == commandID }) else { return }
        if WidgetTaskManager.shared.start(widget: widget, command: command, media: info) != nil {
            toastWindow.show(message: "Processing Widget…".localized, over: self)
        }
    }

    @objc private func widgetTasksDidChange() {
        let completed = WidgetTaskManager.shared.records.filter { $0.phase == .completed && !handledWidgetTaskIDs.contains($0.id) }
        completed.forEach { handledWidgetTaskIDs.insert($0.id) }
        guard let session else { return }
        renderSession()
        for task in completed {
            guard let output = task.output, let source = task.source,
                  currentRevealInfo?.url.absoluteString == source.absoluteString,
                  !session.infos.contains(where: { $0.url.standardizedFileURL == output.standardizedFileURL }) else { continue }
            appendImage(info: MediaInfo(url: output, isLocal: true, kind: .image))
        }
    }

    /// The viewport the actions menu acts on: focused image in Focus/Browse,
    /// the active slot in side-by-side, the shared pair state in slider.
    private var currentActionViewport: InspectImageViewport {
        guard let session, session.mode == .compare else { return primaryViewport }
        if session.comparisonStyle == .slider { return sliderViewport.viewport }
        return session.activeCompareSlot == 0 ? primaryViewport : secondaryViewport
    }

    private var currentActionIndex: Int? {
        guard let session else { return nil }
        if session.mode == .compare, let pair = session.compareIndices {
            return session.activeCompareSlot == 0 ? pair.0 : pair.1
        }
        return session.focusedIndex
    }

    /// True when the actions target is an image — gates the ⌘C/⌘S/⌘L/⌘R
    /// shortcuts so they don't swallow keys meant for the file preview.
    private var activeItemIsImage: Bool {
        guard let session, let index = currentActionIndex,
              session.infos.indices.contains(index) else { return false }
        return session.infos[index].kind == .image
    }

    private func rotateActive(byQuarters delta: Int) {
        guard let session else { return }
        if session.mode == .compare, session.comparisonStyle == .slider {
            sliderViewport.rotate(byQuarters: delta)
        } else {
            currentActionViewport.rotate(byQuarters: delta)
        }
    }

    /// The active image as a CGImage with the current view rotation applied
    /// (WYSIWYG), or nil when the active item is not a loaded image.
    private func currentActionCGImage() -> CGImage? {
        guard let session, let index = currentActionIndex,
              session.infos[index].kind == .image,
              let image = session.images[safe: index] ?? nil,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rotation = ((currentActionViewport.rotationQuarters % 4) + 4) % 4
        guard rotation != 0 else { return cgImage }
        return ImageExporter.rotate(cgImage, quarters: rotation) ?? cgImage
    }

    /// ⌘C — copy the active image (rotation applied) to the general
    /// pasteboard as PNG data plus an NSImage (TIFF) fallback.
    private func copyActiveImage() {
        guard let cgImage = currentActionCGImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        pasteboard.writeObjects([NSImage(cgImage: cgImage,
                                         size: NSSize(width: cgImage.width, height: cgImage.height))])
        toastWindow.show(message: "Copied ✓".localized, over: self)
    }

    /// ⌘S — silently save the current view as PNG into ~/Documents/Glance/.
    /// Focus saves one image; Compare saves both images as the visible
    /// side-by-side or slider comparison.
    private func quickSaveActiveImage() {
        guard let source = quickSaveSource() else { return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glance", isDirectory: true)
        let filename = UUID().uuidString.prefix(8).uppercased() + ".png"
        let url = directory.appendingPathComponent(filename)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ok = source.render().map {
                ImageExporter.write(cgImage: $0, to: url, format: .png)
            } ?? false
            DispatchQueue.main.async {
                if ok {
                    guard let self else { return }
                    self.toastWindow.show(message: "Saved ✓".localized + "\n" + url.path,
                                          over: self)
                } else {
                    self?.errorTooltip.show(message: "Export failed".localized,
                                            at: NSEvent.mouseLocation)
                }
            }
        }
    }

    private func quickSaveSource() -> QuickSaveSource? {
        guard let session else { return nil }
        if session.mode == .compare {
            guard let pair = session.compareIndices,
                  session.images.indices.contains(pair.0), session.images.indices.contains(pair.1),
                  let a = session.images[pair.0], let b = session.images[pair.1] else { return nil }
            switch session.comparisonStyle {
            case .sideBySide:
                return .sideBySide(a, comparisonRotation(slot: 0),
                                   b, comparisonRotation(slot: 1))
            case .slider:
                return .slider(a, comparisonRotation(slot: 0),
                               b, comparisonRotation(slot: 1),
                               sliderViewport.revealFraction)
            }
        }
        guard let index = currentActionIndex,
              let image = session.images[safe: index] ?? nil else { return nil }
        return .single(image, currentActionViewport.rotationQuarters)
    }

    private func comparisonRotation(slot: Int) -> Int {
        guard let session, session.comparisonStyle == .sideBySide else {
            return sliderViewport.viewport.rotationQuarters
        }
        return slot == 0 ? primaryViewport.rotationQuarters : secondaryViewport.rotationQuarters
    }

    private func recognizeTextTapped() {
        guard let cgImage = currentActionCGImage() else { return }
        presentOCRWindow()
        ocrWindow.showLoading()
        let token = UUID()
        ocrGeneration = token
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            var text = ""
            do {
                try handler.perform([request])
                text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
            } catch {
                Logger.error("OCR failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                guard let self, self.ocrGeneration == token else { return }
                self.ocrWindow.showResult(text)
            }
        }
    }

    /// Dock the OCR panel beside the main window (right of the info panel when
    /// that is also open), sliding in from the right on first presentation.
    private func presentOCRWindow() {
        let gap: CGFloat = 2
        let anchor = (infoVisible && infoWindow.isVisible) ? infoWindow.frame : frame
        var origin = NSPoint(x: anchor.maxX + gap, y: frame.minY)
        let size = NSSize(width: 320, height: frame.height)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            if origin.x + size.width > visible.maxX {
                origin.x = max(visible.minX, frame.minX - size.width - gap)
            }
            origin.y = min(max(visible.minY, origin.y), visible.maxY - size.height)
        }
        let target = NSRect(origin: origin, size: size)
        if ocrVisible && ocrWindow.isVisible {
            ocrWindow.setFrame(target, display: true)
            return
        }
        removeChildWindow(ocrWindow)
        ocrWindow.setFrame(target.offsetBy(dx: 48, dy: 0), display: false)
        ocrWindow.alphaValue = 0
        addChildWindow(ocrWindow, ordered: .above)
        ocrVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ocrWindow.animator().setFrame(target, display: true)
            ocrWindow.animator().alphaValue = 1
        }
    }

    /// Export the active image through a Save panel. The export is WYSIWYG:
    /// it carries the current view rotation, but never touches the source file.
    private func exportActive(as format: ImageExportFormat) {
        guard let session, let index = currentActionIndex,
              let image = session.images[safe: index] ?? nil else { return }
        let rotation = currentActionViewport.rotationQuarters
        let baseName = (session.infos[index].filename as NSString).deletingPathExtension
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.utType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = ImageExporter.write(image: image, rotatedQuarters: rotation,
                                         to: url, format: format)
            DispatchQueue.main.async {
                if ok {
                    guard let self else { return }
                    self.toastWindow.show(message: "Exported ✓".localized + "\n" + url.path,
                                          over: self)
                } else {
                    self?.errorTooltip.show(message: "Export failed".localized,
                                            at: NSEvent.mouseLocation)
                }
            }
        }
    }

    private var currentRevealInfo: MediaInfo? {
        guard let session else { return nil }
        let index: Int
        if session.mode == .compare, let pair = session.compareIndices {
            index = session.activeCompareSlot == 0 ? pair.0 : pair.1
        } else {
            index = session.focusedIndex
        }
        guard session.infos.indices.contains(index) else { return nil }
        return session.infos[index]
    }

    private func updateRevealButtonState() {
        revealButton.isEnabled = currentRevealInfo?.isLocal == true
    }

    private func toggleInfo() {
        infoVisible.toggle()
        infoButton.isActive = infoVisible
        if infoVisible {
            positionInfoWindowBesideMain()
            // Attach as a child window: ordered just above the main window, so
            // a window covering the main window also covers the info panel.
            addChildWindow(infoWindow, ordered: .above)
        } else {
            removeChildWindow(infoWindow)
            infoWindow.orderOut(nil)
        }
        renderSession()
    }

    /// Dock the floating info window just to the right of the main window,
    /// clamped on-screen. The user can then drag it anywhere.
    private func positionInfoWindowBesideMain() {
        let width: CGFloat = 320
        let gap: CGFloat = 2
        let mainFrame = frame
        var origin = NSPoint(x: mainFrame.maxX + gap, y: mainFrame.minY)
        let size = NSSize(width: width, height: mainFrame.height)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            if origin.x + width > visible.maxX {
                origin.x = max(visible.minX, mainFrame.minX - width - gap)
            }
            origin.y = min(max(visible.minY, origin.y), visible.maxY - size.height)
        }
        infoWindow.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func updateIdentityBar(for info: MediaInfo, index: Int) {
        identityNameLabel.stringValue = info.filename
        var parts: [String] = []
        if let session, session.infos.count > 1 { parts.append("\(index + 1) / \(session.infos.count)") }
        if let size = info.dimensions { parts.append("\(Int(size.width)) × \(Int(size.height))") }
        if info.formatName.isDisplayableValue { parts.append(info.formatName) }
        if let bytes = info.fileSize { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
        identityMetaLabel.stringValue = parts.joined(separator: "  ·  ")
    }

    private func focus(index: Int) {
        guard let session, session.infos.indices.contains(index) else { return }
        if session.mode == .compare {
            // Tapping a non-image thumbnail in compare mode exits compare and
            // focuses the file — files never join a compare pair.
            guard session.infos[index].kind == .image else {
                session.mode = session.infos.count > 1 ? .browse : .focus
                session.compareIndices = nil
                session.focusedIndex = index
                renderSession()
                return
            }
            if let pair = session.compareIndices {
                // Replace whichever slot is active (left or right), so both sides
                // can be changed. Avoid pointing both slots at the same image.
                if session.activeCompareSlot == 0 {
                    guard index != pair.1 else { return }
                    session.compareIndices = (index, pair.1)
                } else {
                    guard index != pair.0 else { return }
                    session.compareIndices = (pair.0, index)
                }
            }
        } else {
            session.focusedIndex = index
        }
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
    }

    /// Choose which compare slot subsequent filmstrip taps replace, by clicking
    /// the left or right image in side-by-side mode.
    private func selectCompareSlot(_ slot: Int) {
        guard let session,
              session.mode == .compare,
              session.comparisonStyle == .sideBySide,
              session.activeCompareSlot != slot else { return }
        session.activeCompareSlot = slot
        Logger.debug("ImageInspectWindow: active compare slot = \(slot == 0 ? "left" : "right")")
        primaryViewport.isActiveSlot = slot == 0
        secondaryViewport.isActiveSlot = slot == 1
        primaryViewport.setCompareDimmed(slot != 0)
        secondaryViewport.setCompareDimmed(slot != 1)
        updateRevealButtonState()
        if let pair = session.compareIndices {
            infoPanel.highlight(index: slot == 0 ? pair.0 : pair.1)
        }
    }

    private func navigate(by delta: Int) {
        guard let session, !session.infos.isEmpty else { return }
        if session.mode == .compare, let pair = session.compareIndices {
            // Cycle only among images (excluding the pinned left slot).
            let pool = session.infos.indices.filter {
                session.infos[$0].kind == .image && $0 != pair.0
            }
            guard let position = pool.firstIndex(of: pair.1), pool.count > 1 else { return }
            let candidate = pool[(position + delta + pool.count) % pool.count]
            session.compareIndices = (pair.0, candidate)
        } else {
            session.focusedIndex = (session.focusedIndex + delta + session.infos.count) % session.infos.count
        }
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
    }

    private func compare(focusedWith index: Int) {
        guard let session, session.infos.indices.contains(index), index != session.focusedIndex,
              session.infos[index].kind == .image,
              session.infos[session.focusedIndex].kind == .image else { return }
        session.mode = .compare
        session.compareIndices = (session.focusedIndex, index)
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
    }

    /// Append a freshly captured frame (from video capture handoff) to the
    /// current session and focus it; leaves compare mode so the capture shows.
    func appendImage(info: MediaInfo) {
        guard let session, isVisible else {
            show(infos: [info], loaded: [nil], focusedIndex: 0)
            return
        }
        session.infos.append(info)
        session.images.append(nil)
        session.metadata.append(nil)
        let newIndex = session.infos.count - 1
        session.mode = session.infos.count > 1 ? .browse : .focus
        session.compareIndices = nil
        session.focusedIndex = newIndex
        renderSession()
        loadDroppedItem(at: newIndex, generation: loadGeneration)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// Accept an image file dragged onto the window. The file is appended to
    /// the end of the filmstrip; which on-screen slot shows it depends on the
    /// current mode:
    ///   - Focus/Browse: display the dropped image directly.
    ///   - Side by side: replace the side the drop landed on.
    ///   - Slider: replace the base (A) image.
    private func handleDroppedImage(url: URL, at point: NSPoint) {
        guard let session else { return }
        // A repeated resource selects the existing item instead of creating a
        // duplicate thumbnail. Exit Compare so the selected image is shown as
        // the single focused image immediately.
        let identity = mediaIdentity(for: url)
        if let existingIndex = session.infos.firstIndex(where: {
            mediaIdentity(for: $0.url) == identity
        }) {
            session.mode = .focus
            session.compareIndices = nil
            session.focusedIndex = existingIndex
            renderSession()
            loadFullResolutionForActiveItems(generation: loadGeneration)
            return
        }
        session.infos.append(MediaInfo(url: url, isLocal: url.isFileURL, kind: .image))
        session.images.append(nil)
        session.metadata.append(nil)
        let newIndex = session.infos.count - 1
        if session.mode == .compare, let pair = session.compareIndices {
            if session.comparisonStyle == .sideBySide {
                let slot = primaryViewport.frame.contains(point) ? 0 : 1
                session.activeCompareSlot = slot
                session.compareIndices = slot == 0 ? (newIndex, pair.1) : (pair.0, newIndex)
            } else {
                session.compareIndices = (newIndex, pair.1)
            }
        } else {
            // A single-image Focus session becomes Browse after the append:
            // the dropped image is the main image and both items remain in
            // the filmstrip.
            session.mode = session.infos.count > 1 ? .browse : .focus
            session.focusedIndex = newIndex
        }
        Logger.debug("ImageInspectWindow: dropped image \(url.lastPathComponent) at index \(newIndex)")
        renderSession()
        loadDroppedItem(at: newIndex, generation: loadGeneration)
    }

    private func mediaIdentity(for url: URL) -> String {
        url.isFileURL ? url.standardizedFileURL.path : url.absoluteURL.absoluteString
    }

    /// Clipboard text for URL pasting. Browser address-bar copies and some
    /// apps only provide an NSURL object (public.url) without a plain-string
    /// type, so readObjects is required as a fallback.
    static func clipboardText() -> String? {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), !text.isEmpty { return text }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first {
            return url.absoluteString
        }
        return nil
    }

    /// ⌘V: classify clipboard text through the same PathDetector used by the
    /// selection-hotkey pipeline, then display a remote image URL directly.
    private func pasteRemoteImageFromClipboard() -> Bool {
        guard let text = Self.clipboardText() else { return false }
        guard let info = imageInfo(from: text, allowExtensionlessRemoteURL: true),
              !info.isLocal else { return false }
        appendOrFocusImage(info: info)
        return true
    }

    /// Toolbar "globe" button: a sheet accepting an image URL OR a local
    /// path. Local files display immediately; remote URLs show the loading
    /// animation while downloading into the persistent cache.
    @objc private func openURLTapped() {
        let alert = NSAlert()
        alert.messageText = "Open image URL".localized
        alert.informativeText = "Paste an image URL or local path".localized
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Open".localized)
        alert.addButton(withTitle: "Cancel".localized)
        alert.window.initialFirstResponder = field
        var pasteMonitor: Any?
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.window === alert.window,
               event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v" {
                if let editor = field.currentEditor() as? NSTextView {
                    editor.paste(nil)
                } else if let text = Self.clipboardText() {
                    field.stringValue = text
                }
                return nil
            }
            return event
        }
        alert.beginSheetModal(for: self) { [weak self, weak field] response in
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
            guard response == .alertFirstButtonReturn,
                  let text = field?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            self?.openImageFromInput(text)
        }
        // NSAlert creates its field editor only after the sheet is attached.
        // Make the accessory field first responder on the next run-loop turn
        // so native typing and ⌘V both target it reliably.
        DispatchQueue.main.async { [weak self, weak alert, weak field] in
            guard let self, let alert, let field,
                  self.attachedSheet === alert.window else { return }
            alert.window.makeFirstResponder(field)
        }
    }

    private func openImageFromInput(_ text: String) {
        guard let info = imageInfo(from: text, allowExtensionlessRemoteURL: true) else {
            errorTooltip.show(message: "No image URL found".localized, at: NSEvent.mouseLocation)
            return
        }
        appendOrFocusImage(info: info)
    }

    /// Return a normal detected image, or let the image-specific URL entry
    /// point probe an extensionless HTTP URL by sending it to the decoder.
    /// Generic selection detection still treats unknown URLs as webpages.
    private func imageInfo(from text: String, allowExtensionlessRemoteURL: Bool) -> MediaInfo? {
        for path in pathDetector.detectAll(text) {
            guard let info = MediaInfo.from(path) else { continue }
            if info.kind == .image { return info }
            if allowExtensionlessRemoteURL, info.kind == .webPage, !info.isLocal {
                return MediaInfo(url: info.url, isLocal: false, kind: .image)
            }
        }
        return nil
    }

    /// Shared append-or-focus path for URL input, ⌘V, and remote drops:
    /// duplicates focus the existing item; new items append to the filmstrip
    /// end and take focus.
    private func appendOrFocusImage(info: MediaInfo) {
        guard let session else {
            show(infos: [info], loaded: [nil], focusedIndex: 0, preferredMode: .focus)
            return
        }
        let identity = mediaIdentity(for: info.url)
        if let index = session.infos.firstIndex(where: { mediaIdentity(for: $0.url) == identity }) {
            session.mode = .focus
            session.compareIndices = nil
            session.focusedIndex = index
            renderSession()
            loadFullResolutionForActiveItems(generation: loadGeneration)
            return
        }
        session.infos.append(info)
        session.images.append(nil)
        session.metadata.append(nil)
        let index = session.infos.count - 1
        session.mode = session.infos.count > 1 ? .browse : .focus
        session.compareIndices = nil
        session.focusedIndex = index
        renderSession()
        loadDroppedItem(at: index, generation: loadGeneration)
        if !info.isLocal { Logger.info("ImageInspectWindow: pasted remote image") }
    }

    private func handleDroppedResource(url: URL, at point: NSPoint) {
        let info: MediaInfo?
        if url.isFileURL {
            info = MediaInfo.from(pathDetector.localKind(for: url.path))
        } else {
            info = pathDetector.detectAll(url.absoluteString)
                .compactMap(MediaInfo.from).first
        }
        guard let info else { return }
        switch info.kind {
        case .image:
            handleDroppedImage(url: info.url, at: point)
        case .video:
            onOpenVideo?(info)
        case .markdown, .text, .pdf, .webPage:
            onOpenContent?(info)
        case .other, .folder:
            closeForViewerHandoff()
            if info.isLocal {
                NSWorkspace.shared.activateFileViewerSelecting([info.url])
            } else {
                NSWorkspace.shared.open(info.url)
            }
        }
    }

    /// Load only the newly appended item — the rest of the session is already
    /// loaded, so a full loadSessionImages pass would redo work.
    private func loadDroppedItem(at index: Int, generation: UUID) {
        guard let session, session.infos.indices.contains(index) else { return }
        let info = session.infos[index]
        imageLoader.loadFullResolutionImage(from: info.url) { [weak self] image in
            guard let self, generation == self.loadGeneration,
                  let session = self.session, session.images.indices.contains(index) else { return }
            if let image {
                session.failedIndices.remove(index)
                session.images[index] = image
                session.infos[index].dimensions = image.size
            } else {
                session.failedIndices.insert(index)
            }
            self.renderSession()
        }
        imageLoader.loadFileSize(from: info.url) { [weak self] bytes in
            guard let self, generation == self.loadGeneration,
                  let session = self.session, session.infos.indices.contains(index) else { return }
            session.infos[index].fileSize = bytes
            self.renderSession()
        }
        imageLoader.loadTechnicalMetadata(from: info.url) { [weak self] metadata in
            guard let self, generation == self.loadGeneration,
                  let session = self.session, session.metadata.indices.contains(index) else { return }
            session.metadata[index] = metadata
            self.renderSession()
        }
    }

    private func syncViewport(_ state: InspectViewportState, source: InspectImageViewport?) {
        guard session?.mode == .compare, session?.comparisonStyle == .sideBySide else { return }
        for viewport in [primaryViewport, secondaryViewport] where viewport !== source {
            viewport.apply(state: state, notify: false)
        }
    }

    private func closeAndRestore() {
        isClosingProgrammatically = true
        orderOut(nil)
        isClosingProgrammatically = false
        onClose?()
    }

    private func updateWindowTitle(for info: MediaInfo, index: Int) {
        // The window title stays generic; the filename shows in the bottom bar.
        title = "Image Inspect".localized
        representedURL = nil
    }
}

/// Slide-out panel showing OCR results, docked beside the main window.
/// Attached as a child window (same occlusion behavior as the info panel)
/// with frosted translucent chrome.
private final class OCRResultWindow: NSPanel {
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

/// Short centered acknowledgement for successful save/export operations.
/// A child panel is used instead of a canvas subview so layer-backed image,
/// WebKit, and AV surfaces can never render above it.
private final class InspectToastWindow: NSPanel {
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hideWorkItem: DispatchWorkItem?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 156, height: 42),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let frost = PanelStyle.makeFrostedBase(cornerRadius: 10)
        contentView = frost
        label.font = PanelStyle.label
        label.textColor = PanelStyle.textPrimary
        label.alignment = .center
        label.lineBreakMode = .byCharWrapping
        label.maximumNumberOfLines = 0
        frost.addSubview(label)
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(message: String, over parentWindow: NSWindow) {
        hideWorkItem?.cancel()
        let parts = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3
        let styled = NSMutableAttributedString(
            string: String(parts.first ?? ""),
            attributes: [.font: PanelStyle.label,
                         .foregroundColor: PanelStyle.textPrimary,
                         .paragraphStyle: paragraph])
        if parts.count > 1 {
            styled.append(NSAttributedString(
                string: "\n" + String(parts[1]),
                attributes: [.font: PanelStyle.caption,
                             .foregroundColor: PanelStyle.textSecondary,
                             .paragraphStyle: paragraph]))
        }
        label.attributedStringValue = styled
        let maxWidth = min(620, max(240, parentWindow.frame.width - 80))
        let textBounds = styled.boundingRect(
            with: NSSize(width: maxWidth - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = NSSize(width: min(maxWidth, max(156, ceil(textBounds.width) + 32)),
                          height: max(42, ceil(textBounds.height) + 20))
        label.frame = NSRect(origin: .zero, size: size).insetBy(dx: 12, dy: 10)
        let target = NSRect(x: parentWindow.frame.midX - size.width / 2,
                            y: parentWindow.frame.midY - size.height / 2,
                            width: size.width, height: size.height)
        if parent !== parentWindow {
            if let parent { parent.removeChildWindow(self) }
            parentWindow.addChildWindow(self, ordered: .above)
        }
        setFrame(target, display: true)
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 1
        }
        let item = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self?.animator().alphaValue = 0
            }, completionHandler: {
                guard let self else { return }
                self.parent?.removeChildWindow(self)
                self.orderOut(nil)
            })
        }
        hideWorkItem = item
        let delay: TimeInterval = parts.count > 1 ? 2.5 : 1.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

// MARK: - Themed action menu

/// One row in an ActionMenuPanel. `submenu` rows cascade to a child panel.
struct ActionMenuEntry {
    var title = ""
    var shortcut: String? = nil
    var isSeparator = false
    var enabled = true
    var submenu: [ActionMenuEntry]? = nil
    var action: (() -> Void)? = nil

    static func separator() -> ActionMenuEntry { ActionMenuEntry(isSeparator: true) }
}

/// Themed replacement for the system NSMenu behind the ⋯ button and image
/// right-clicks: frosted dark translucent chrome with warm-cue row
/// highlights (the system menu's blue selection and light-mode material
/// clash with the darkroom theme). Supports one cascading submenu level.
final class ActionMenuPanel: NSPanel {
    private static let menuWidth: CGFloat = 216
    private static let rowHeight: CGFloat = 26
    private static let separatorHeight: CGFloat = 9
    private static let padding: CGFloat = 6

    private let entries: [ActionMenuEntry]
    private var rowViews: [ActionMenuRow] = []
    private var childPanel: ActionMenuPanel?
    private weak var parentPanel: ActionMenuPanel?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var submenuWorkItem: DispatchWorkItem?

    init(entries: [ActionMenuEntry]) {
        self.entries = entries
        var height = Self.padding * 2
        for entry in entries {
            height += entry.isSeparator ? Self.separatorHeight : Self.rowHeight
        }
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.menuWidth, height: height),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces]
        guard let content = contentView else { return }
        let frost = PanelStyle.makeFrostedBase(cornerRadius: 10)
        frost.frame = content.bounds
        frost.autoresizingMask = [.width, .height]
        content.addSubview(frost)

        var y = height - Self.padding
        for entry in entries {
            if entry.isSeparator {
                let sep = NSView(frame: NSRect(x: Self.padding + 6, y: y - Self.separatorHeight + 4,
                                               width: Self.menuWidth - (Self.padding + 6) * 2, height: 1))
                sep.wantsLayer = true
                sep.layer?.backgroundColor = PanelStyle.hairline.cgColor
                content.addSubview(sep)
                y -= Self.separatorHeight
                continue
            }
            let row = ActionMenuRow(entry: entry,
                                    frame: NSRect(x: Self.padding, y: y - Self.rowHeight,
                                                  width: Self.menuWidth - Self.padding * 2,
                                                  height: Self.rowHeight))
            row.onHover = { [weak self] hovered in self?.rowHovered(hovered) }
            row.onActivate = { [weak self] activated in self?.rowActivated(activated) }
            content.addSubview(row)
            rowViews.append(row)
            y -= Self.rowHeight
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Present top-left-anchored at a screen point, clamped on screen.
    func present(at screenPoint: NSPoint, parent: ActionMenuPanel? = nil) {
        parentPanel = parent
        let size = frame.size
        var origin = NSPoint(x: screenPoint.x, y: screenPoint.y - size.height)
        let screen = NSScreen.screens.first { $0.frame.contains(screenPoint) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if origin.x + size.width > visible.maxX { origin.x = visible.maxX - size.width - 4 }
            origin.x = max(visible.minX + 4, origin.x)
            origin.y = min(max(visible.minY + 4, origin.y), visible.maxY - size.height - 4)
        }
        setFrameOrigin(origin)
        if parent == nil { installMonitors() }
        orderFront(nil)
    }

    func dismissChain() {
        submenuWorkItem?.cancel()
        submenuWorkItem = nil
        childPanel?.dismissChain()
        childPanel = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        mouseMonitor = nil
        keyMonitor = nil
        resignObserver = nil
        orderOut(nil)
    }

    private func dismissFromRoot() {
        var root = self
        while let parent = root.parentPanel { root = parent }
        root.dismissChain()
    }

    private func chainContains(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        var current: ActionMenuPanel? = self
        while let panel = current {
            if panel == window { return true }
            current = panel.childPanel
        }
        return false
    }

    /// Resolve the visible parent/child menu panel under a screen point.
    private func panel(atScreenPoint point: NSPoint) -> ActionMenuPanel? {
        if let child = childPanel, let hit = child.panel(atScreenPoint: point) { return hit }
        return frame.contains(point) ? self : nil
    }

    /// Dispatch a click directly from the root event monitor. Nonactivating
    /// panels do not reliably route the first click through the responder
    /// chain, so waiting for row mouseDown/mouseUp loses the action.
    private func activateRow(atScreenPoint point: NSPoint) {
        let windowPoint = convertFromScreen(NSRect(origin: point, size: .zero)).origin
        let contentPoint = contentView?.convert(windowPoint, from: nil) ?? windowPoint
        guard let row = rowViews.first(where: { $0.frame.contains(contentPoint) }) else { return }
        rowActivated(row)
    }

    private func installMonitors() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let point = NSEvent.mouseLocation
            if let panel = self.panel(atScreenPoint: point) {
                if event.type == .leftMouseDown { panel.activateRow(atScreenPoint: point) }
                return nil
            }
            self.dismissChain()
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc closes the menu before the window sees it
                self?.dismissChain()
                return nil
            }
            return event
        }
        // hidesOnDeactivate hides the panel visually; tear the chain down so
        // no hidden menu keeps swallowing clicks/Esc.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismissChain()
        }
    }

    private func rowHovered(_ row: ActionMenuRow) {
        for other in rowViews where other !== row { other.setHighlighted(false) }
        row.setHighlighted(row.entry.enabled)
        submenuWorkItem?.cancel()
        if let submenu = row.entry.submenu, row.entry.enabled {
            // Slight delay matches system submenu hover behavior.
            let item = DispatchWorkItem { [weak self, weak row] in
                guard let self, let row, row.isHighlightedState else { return }
                self.openSubmenu(submenu, from: row)
            }
            submenuWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        } else {
            childPanel?.dismissChain()
            childPanel = nil
        }
    }

    private func rowActivated(_ row: ActionMenuRow) {
        guard row.entry.enabled else { return }
        if let submenu = row.entry.submenu {
            openSubmenu(submenu, from: row)
            return
        }
        guard let action = row.entry.action else { return }
        dismissFromRoot()
        action()
    }

    private func openSubmenu(_ entries: [ActionMenuEntry], from row: ActionMenuRow) {
        childPanel?.dismissChain()
        let child = ActionMenuPanel(entries: entries)
        childPanel = child
        let rowTopRight = row.convert(NSPoint(x: row.bounds.width, y: row.bounds.height), to: nil)
        let screenPoint = convertToScreen(NSRect(origin: rowTopRight, size: .zero)).origin
        // rowTopRight stops at the content padding (6pt before the panel
        // edge), so add padding + gap to guarantee no panel overlap.
        var point = NSPoint(x: screenPoint.x + Self.padding + 2,
                            y: screenPoint.y + Self.padding)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame,
           point.x + child.frame.width > visible.maxX {
            // No room on the right — cascade to the left of the parent.
            point.x = frame.minX - child.frame.width - 2
        }
        child.present(at: point, parent: self)
    }
}

/// One menu row: title (+ optional shortcut hint or submenu chevron),
/// warm-cue highlight with dark text for contrast.
final class ActionMenuRow: NSView {
    let entry: ActionMenuEntry
    var onHover: ((ActionMenuRow) -> Void)?
    var onActivate: ((ActionMenuRow) -> Void)?
    private(set) var isHighlightedState = false
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let chevronLabel = NSTextField(labelWithString: "›")

    init(entry: ActionMenuEntry, frame: NSRect) {
        self.entry = entry
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        titleLabel.stringValue = entry.title
        titleLabel.font = PanelStyle.label
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        if let shortcut = entry.shortcut {
            shortcutLabel.stringValue = shortcut
            shortcutLabel.font = PanelStyle.label
            shortcutLabel.alignment = .right
            addSubview(shortcutLabel)
        }
        if entry.submenu != nil {
            chevronLabel.font = PanelStyle.label
            addSubview(chevronLabel)
        }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Swallow all hits at the row level so the labels never consume events.
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func layout() {
        super.layout()
        // Center the labels vertically by their real line height — a
        // full-height text field draws its text on the baseline, not centered.
        let titleHeight = ceil(titleLabel.cell?.cellSize.height ?? bounds.height)
        let centeredY = (bounds.height - titleHeight) / 2
        titleLabel.frame = NSRect(x: 10, y: centeredY, width: bounds.width - 62, height: titleHeight)
        shortcutLabel.frame = NSRect(x: bounds.width - 52, y: centeredY, width: 40, height: titleHeight)
        chevronLabel.frame = NSRect(x: bounds.width - 20, y: centeredY, width: 12, height: titleHeight)
    }

    func setHighlighted(_ highlighted: Bool) {
        isHighlightedState = highlighted
        layer?.backgroundColor = highlighted ? PanelStyle.warmCue.cgColor : NSColor.clear.cgColor
        updateColors()
    }

    private func updateColors() {
        let color: NSColor
        if !entry.enabled { color = PanelStyle.textTertiary }
        else if isHighlightedState { color = PanelStyle.canvas }
        else { color = PanelStyle.textPrimary }
        titleLabel.textColor = color
        shortcutLabel.textColor = isHighlightedState && entry.enabled
            ? PanelStyle.canvas.withAlphaComponent(0.72)
            : PanelStyle.textTertiary
        chevronLabel.textColor = color
        alphaValue = entry.enabled ? 1 : 0.55
    }

    override func mouseEntered(with event: NSEvent) { onHover?(self) }

    override func mouseDown(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?(self)
    }
}

/// Shown when the focused item in a mixed session has no inline preview
/// (video, unsupported file, folder): a large type icon over the filename.
private final class FilePlaceholderView: NSView {
    weak var dropTarget: MediaDropCanvasView?
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        nameLabel.font = PanelStyle.headline
        nameLabel.textColor = PanelStyle.textSecondary
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender) == true
    }

    func configure(info: MediaInfo) {
        iconView.image = FileTypeIcon.makeImage(for: info, size: CGSize(width: 128, height: 128))
        nameLabel.stringValue = info.filename
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 128
        iconView.frame = NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2 + 12,
                                width: size, height: size)
        nameLabel.frame = NSRect(x: 20, y: bounds.midY - size / 2 - 28,
                                 width: bounds.width - 40, height: 20)
    }
}

/// WKWebView is itself a drag destination, so mixed-file sessions must
/// explicitly forward media drops instead of relying on superview bubbling.
private final class InspectFileWebView: WKWebView {
    weak var dropTarget: MediaDropCanvasView?

    convenience init() {
        self.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender) == true
    }
}

/// Canvas view that accepts dragged media from anywhere — Finder file URLs,
/// browser/web URLs, file promises (WeChat, Photos, screenshot tools), and
/// raw image data. The owning window decides which extensions are droppable
/// (via `acceptsExtension`) and what to do with the result (via `onDrop`).
/// Shared by the image and video inspect windows.
final class MediaDropCanvasView: NSView {
    /// Kept in sync with PathDetector's media extension lists.
    static let imageExtensions = ImageFormatSupport.extensions
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mpg", "mpeg", "mpe", "m2v",
        "ts", "m2ts", "mts", "3gp", "3gpp", "3g2",
        "webm", "mkv", "avi"
    ]

    /// Return true when the dragged file extension is a kind this canvas accepts.
    var acceptsExtension: ((String) -> Bool)?
    /// Whether raw dragged image data (no URL at all) may be accepted.
    /// Image window only — the video canvas never wants a raw bitmap drop.
    var acceptsImageData = false
    /// Called with the resolved URL (local file, remote, or a temp file
    /// materialized from a promise/bitmap) and the drop location in this
    /// view's coordinate space.
    var onDrop: ((URL, NSPoint) -> Void)?

    private static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes
        .map { NSPasteboard.PasteboardType(rawValue: $0) }
    private static let imageDataTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType(rawValue: UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(rawValue: "public.heic"),
        NSPasteboard.PasteboardType(rawValue: "org.webmproject.webp"),
    ]
    static var imageDraggedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL] + imageDataTypes + promiseTypes
    }
    static var videoDraggedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL] + promiseTypes
    }
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.imageDraggedTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func accepts(_ url: URL) -> Bool {
        acceptsExtension?(url.pathExtension.lowercased()) == true
    }

    /// Local file URLs (Finder, other apps dragging real files).
    private func acceptedFileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return nil
        }
        return urls.first { accepts($0) }
    }

    /// Remote URLs (browser image/video drags carry public.url).
    private func acceptedRemoteURL(from pasteboard: NSPasteboard) -> URL? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return nil
        }
        return urls.first { !$0.isFileURL && accepts($0) }
    }

    /// File promises advertise only the promised content's UTIs — match by
    /// preferred filename extension.
    private func hasAcceptablePromise(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: Self.promiseTypes) != nil
    }

    private func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        if acceptedFileURL(from: pasteboard) != nil { return true }
        if acceptedRemoteURL(from: pasteboard) != nil { return true }
        if hasAcceptablePromise(pasteboard) { return true }
        if acceptsImageData,
           pasteboard.availableType(from: Self.imageDataTypes) != nil { return true }
        return false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptsDragging(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptsDragging(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        performDrop(sender)
    }

    func acceptsDragging(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender.draggingPasteboard)
    }

    func performDrop(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let point = convert(sender.draggingLocation, from: nil)
        if let url = acceptedFileURL(from: pasteboard) ?? acceptedRemoteURL(from: pasteboard) {
            onDrop?(url, point)
            return true
        }
        if handlePromises(from: pasteboard, at: point) { return true }
        if acceptsImageData, handleImageData(from: pasteboard, at: point) { return true }
        return false
    }

    /// Receive promised files into a temp directory, then drop each one.
    private func handlePromises(from pasteboard: NSPasteboard, at point: NSPoint) -> Bool {
        guard let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
              !receivers.isEmpty else { return false }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var handled = false
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:],
                                          operationQueue: promiseQueue) { [weak self] fileURL, error in
                guard error == nil, let self, self.accepts(fileURL) else { return }
                DispatchQueue.main.async { self.onDrop?(fileURL, point) }
            }
            handled = true
        }
        return handled
    }

    /// Materialize raw dragged image data into a temp PNG, then drop it.
    private func handleImageData(from pasteboard: NSPasteboard, at point: NSPoint) -> Bool {
        guard let type = pasteboard.availableType(from: Self.imageDataTypes),
              let data = pasteboard.data(forType: type),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return false }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let url = destination.appendingPathComponent("dropped-\(UUID().uuidString.prefix(8)).png")
        guard (try? pngData.write(to: url)) != nil else { return false }
        onDrop?(url, point)
        return true
    }
}

/// Standalone panel that hosts the image info panel. Attached to the main
/// window as a child while visible; not floating, so it shares the main
/// window's occlusion behavior.
final class ImageInfoPanelWindow: NSPanel {
    init(panel: ImageDifferencePanel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 320, height: 240)
        contentMaxSize = NSSize(width: 320, height: 10000)
        title = "Image information".localized
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Frosted, translucent black chrome instead of a solid surface color.
        isOpaque = false
        backgroundColor = .clear
        if let content = contentView {
            let frost = PanelStyle.makeFrostedBase(cornerRadius: 0)
            frost.frame = content.bounds
            frost.autoresizingMask = [.width, .height]
            content.addSubview(frost)
        }
        panel.frame = contentView?.bounds ?? .zero
        panel.autoresizingMask = [.width, .height]
        contentView?.addSubview(panel)
    }
}

final class InspectIdentityBar: NSVisualEffectView {
    private let tintLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.masksToBounds = true
        // Frosted translucency comes from the effect view; the sublayer only
        // biases it darker. Square corners.
        tintLayer.backgroundColor = PanelStyle.canvas.withAlphaComponent(0.62).cgColor
        layer?.addSublayer(tintLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        CATransaction.commit()
    }

    /// Double-click on the toolbar/identity bar zooms the window in and out,
    /// matching the standard macOS title-bar double-click behavior that the
    /// hidden title bar cannot provide.
    override func mouseDown(with event: NSEvent) {
        let now = event.timestamp
        let isDoubleClick = event.clickCount == 2
            || (now - lastMouseDownTimestamp) < NSEvent.doubleClickInterval
        lastMouseDownTimestamp = isDoubleClick ? -.infinity : now
        if isDoubleClick {
            window?.zoom(nil)
            return
        }
        super.mouseDown(with: event)
    }

    private var lastMouseDownTimestamp: TimeInterval = -.infinity
}

final class InspectToolbarButton: NSButton {
    var isActive = false { didSet { updateAppearance() } }

    /// Symbols render at their native 16pt size, centered in the 24pt button.
    /// (Previously a 9pt symbol was upscaled ~2.5× via scaleProportionally
    /// UpOrDown, which made tall symbols like arrow.counterclockwise clip at
    /// the button's bottom edge.)
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .light)

    init(symbol: String, tooltip: String) {
        super.init(frame: .zero)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        toolTip = tooltip
        isBordered = false
        bezelStyle = .recessed
        contentTintColor = PanelStyle.textPrimary
        wantsLayer = true
        layer?.cornerRadius = 5
        setSymbol(symbol)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Swap the icon while keeping the shared symbol configuration. Use this
    /// instead of assigning `image` directly so dynamically swapped icons
    /// (play/pause, mute) match the rest of the toolbar.
    func setSymbol(_ name: String) {
        let raw = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)
        image = raw?.withSymbolConfiguration(Self.symbolConfiguration)
    }

    func updateTooltip(_ tooltip: String) {
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    private func updateAppearance() {
        // Native-style selected tile: a filled rounded square, using Glance's
        // warm theme accent instead of the system blue selection color.
        layer?.backgroundColor = isActive
            ? PanelStyle.warmCue.withAlphaComponent(0.90).cgColor
            : NSColor.clear.cgColor
        // Dim disabled compare buttons so the user can see they are inactive
        // for a single image, instead of looking tappable but doing nothing.
        let activeTint = isActive ? PanelStyle.canvas : PanelStyle.textPrimary
        contentTintColor = isEnabled ? activeTint : PanelStyle.textTertiary
        alphaValue = isEnabled ? 1 : 0.5
    }
}

struct InspectViewportState {
    var zoomRelativeToFit: CGFloat
    var normalizedCenter: CGPoint
}

final class InspectImageViewport: NSView {
    var image: NSImage? {
        didSet {
            // Only reset rotation when a DIFFERENT image is assigned — session
            // re-renders re-assign the same instance after async metadata loads.
            if image !== oldValue { rotationQuarters = 0 }
            imageLayer.contents = image
            updateLoadStatus()
            fitToView()
        }
    }
    var onViewportChange: ((InspectViewportState) -> Void)?
    var isInteractionEnabled = true
    /// Right-click action-menu callback (rotate, export, OCR…). Wired by the
    /// window to present the themed ActionMenuPanel.
    var onActionMenu: ((NSEvent) -> Void)?
    weak var dropTarget: MediaDropCanvasView?
    /// Quarter-turns clockwise applied to the VIEW only (0–3). The file on
    /// disk is never modified; resets when a different image is assigned.
    private(set) var rotationQuarters = 0
    var loadingIndicatorEnabled = true {
        didSet { updateLoadStatus() }
    }
    /// Marks which compare slot is active — the side a filmstrip tap replaces.
    var isActiveSlot = false {
        didSet {
            updateActiveIndicator()
        }
    }
    var viewportState: InspectViewportState {
        InspectViewportState(zoomRelativeToFit: zoom, normalizedCenter: normalizedCenter)
    }

    private let imageLayer = CALayer()
    private let activeIndicator = CALayer()
    private let loadingView = ModularImageLoadingView(frame: .zero)
    private let failureView = LoadFailedAnimationView(frame: .zero)
    private let widgetOverlay = NSVisualEffectView()
    private let widgetLoadingView = ModularImageLoadingView(frame: .zero)
    private let widgetStatusLabel = NSTextField(labelWithString: "")
    private var loadFailed = false
    private var zoom: CGFloat = 1
    private var normalizedCenter = CGPoint(x: 0.5, y: 0.5)
    private var panOffset = CGPoint.zero
    private var lastMouseLocation = CGPoint.zero
    private var dragging = false
    private var compareDimmed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.imageCanvas.cgColor
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
        // Compare selection is communicated by gently dimming the inactive
        // side. Keep the selected side completely free of a border/glow.
        activeIndicator.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
        activeIndicator.borderWidth = 0
        activeIndicator.cornerRadius = 0
        activeIndicator.shadowOpacity = 0
        activeIndicator.opacity = 0
        layer?.addSublayer(activeIndicator)
        addSubview(loadingView)
        addSubview(failureView)
        failureView.isHidden = true
        widgetOverlay.material = .underWindowBackground
        widgetOverlay.blendingMode = .withinWindow
        widgetOverlay.state = .active
        widgetOverlay.wantsLayer = true
        widgetOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        widgetOverlay.isHidden = true
        widgetStatusLabel.textColor = PanelStyle.textPrimary
        widgetStatusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        widgetStatusLabel.alignment = .center
        widgetOverlay.addSubview(widgetLoadingView)
        widgetOverlay.addSubview(widgetStatusLabel)
        addSubview(widgetOverlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender) == true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !widgetOverlay.isHidden { return widgetOverlay.hitTest(point) ?? widgetOverlay }
        return isInteractionEnabled ? super.hitTest(point) : nil
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
        let indicatorRect = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activeIndicator.frame = indicatorRect
        CATransaction.commit()
        let loaderSize = ModularImageLoadingView.preferredSize
        loadingView.frame = NSRect(x: bounds.midX - loaderSize.width / 2,
                                   y: bounds.midY - loaderSize.height / 2,
                                   width: loaderSize.width,
                                   height: loaderSize.height)
        let failureSize = LoadFailedAnimationView.preferredSize
        failureView.frame = NSRect(x: bounds.midX - failureSize.width / 2,
                                   y: bounds.midY - failureSize.height / 2,
                                   width: failureSize.width,
                                   height: failureSize.height)
        widgetOverlay.frame = bounds
        let widgetLoaderSize = ModularImageLoadingView.preferredSize
        widgetLoadingView.frame = NSRect(x: bounds.midX - widgetLoaderSize.width / 2,
                                         y: bounds.midY - widgetLoaderSize.height / 2 + 14,
                                         width: widgetLoaderSize.width, height: widgetLoaderSize.height)
        widgetStatusLabel.frame = NSRect(x: 20, y: bounds.midY - 42, width: bounds.width - 40, height: 22)
    }

    func setLoadFailed(_ failed: Bool) {
        loadFailed = failed
        updateLoadStatus()
    }

    private func updateLoadStatus() {
        let failed = image == nil && loadFailed
        failureView.isHidden = !failed
        loadingView.setLoading(image == nil && loadingIndicatorEnabled && !failed)
    }

    func setActiveIndicatorVisible(_ visible: Bool, animated _: Bool, duration _: CFTimeInterval) {
        // Kept for callers that control toolbar visibility. Compare dimming
        // itself is persistent and is managed by setCompareDimmed(_:).
    }

    func setCompareDimmed(_ dimmed: Bool) {
        compareDimmed = dimmed
        updateActiveIndicator()
    }

    func setWidgetProcessing(_ task: WidgetTaskRecord?) {
        widgetOverlay.isHidden = task == nil
        widgetLoadingView.setLoading(task != nil)
        isInteractionEnabled = task == nil
        guard let task else { widgetStatusLabel.stringValue = ""; return }
        switch task.phase {
        case .uploading: widgetStatusLabel.stringValue = "Uploading…".localized
        case .submitting: widgetStatusLabel.stringValue = "Submitting…".localized
        case .processing: widgetStatusLabel.stringValue = task.progress > 0 ? "Processing \(task.progress)%" : "Processing…".localized
        case .downloading: widgetStatusLabel.stringValue = "Downloading result…".localized
        default: widgetStatusLabel.stringValue = "Processing…".localized
        }
        setAccessibilityElement(true)
        setAccessibilityLabel(widgetStatusLabel.stringValue)
    }

    private func updateActiveIndicator() {
        let isVisible = compareDimmed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activeIndicator.opacity = isVisible ? 1 : 0
        CATransaction.commit()
    }

    func fitToView() {
        zoom = 1
        panOffset = .zero
        normalizedCenter = CGPoint(x: 0.5, y: 0.5)
        updateLayerGeometry()
        notify()
    }

    func setActualSize() {
        guard let image, bounds.width > 0, bounds.height > 0 else { return }
        let fit = fitScale(for: image)
        zoom = max(1, min(20, 1 / max(fit, 0.0001)))
        panOffset = .zero
        normalizedCenter = CGPoint(x: 0.5, y: 0.5)
        updateLayerGeometry()
        notify()
    }

    func apply(state: InspectViewportState, notify shouldNotify: Bool) {
        guard let image else { return }
        zoom = max(1, min(20, state.zoomRelativeToFit))
        normalizedCenter = state.normalizedCenter
        let rendered = renderedSize(for: image)
        panOffset = CGPoint(x: (0.5 - normalizedCenter.x) * rendered.width,
                            y: (0.5 - normalizedCenter.y) * rendered.height)
        constrainPan(rendered: rendered)
        updateLayerGeometry()
        if shouldNotify { notify() }
    }

    /// Rotate the view layer by 90° steps (view-only; the file is untouched).
    func rotate(byQuarters delta: Int) {
        guard image != nil else { return }
        rotationQuarters = ((rotationQuarters + delta) % 4 + 4) % 4
        updateLayerGeometry()
        notify()
    }

    override func rightMouseDown(with event: NSEvent) {
        if let onActionMenu {
            onActionMenu(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let image else { return }
        // Once zoomed, trackpad two-finger scrolling is panning (matching the
        // Preview image viewer), not another zoom gesture.
        if zoom > 1.0 {
            panOffset.x -= event.scrollingDeltaX
            panOffset.y -= event.scrollingDeltaY
            constrainPan(rendered: renderedSize(for: image))
        } else if event.modifierFlags.contains(.command) || abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            let point = convert(event.locationInWindow, from: nil)
            let before = imagePoint(at: point, image: image)
            let factor = pow(1.08, event.scrollingDeltaY)
            zoom = max(1, min(20, zoom * factor))
            setCenter(so: before, remainsAt: point, image: image)
        }
        updateLayerGeometry()
        notify()
    }

    override func magnify(with event: NSEvent) {
        window?.makeFirstResponder(self)
        zoom = max(1, min(20, zoom * (1 + event.magnification)))
        updateLayerGeometry()
        notify()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            zoom > 1.01 ? fitToView() : setActualSize()
            return
        }
        guard zoom > 1 else { return }
        dragging = true
        lastMouseLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let location = event.locationInWindow
        let delta = CGPoint(x: location.x - lastMouseLocation.x,
                            y: location.y - lastMouseLocation.y)
        panOffset.x += delta.x
        panOffset.y += delta.y
        lastMouseLocation = location
        let rendered = renderedSize(for: image!)
        constrainPan(rendered: rendered)
        normalizedCenter = CGPoint(x: 0.5 - panOffset.x / max(rendered.width, 1),
                                   y: 0.5 - panOffset.y / max(rendered.height, 1))
        updateLayerGeometry()
        notify()
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    private func updateLayerGeometry() {
        guard let image, bounds.width > 0, bounds.height > 0 else {
            imageLayer.frame = bounds
            return
        }
        let rendered = renderedSize(for: image)
        constrainPan(rendered: rendered)
        let centerX = bounds.midX + panOffset.x
        let centerY = bounds.midY + panOffset.y
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The layer keeps the UNROTATED rendered size so resizeAspect fills it
        // exactly; quarter-turns are applied via the layer transform, and the
        // view-space width/height swap happens in renderedSize(for:).
        imageLayer.bounds = NSRect(origin: .zero, size: contentSize(for: image))
        imageLayer.position = CGPoint(x: centerX, y: centerY)
        imageLayer.transform = CATransform3DMakeRotation(-CGFloat(rotationQuarters) * .pi / 2, 0, 0, 1)
        CATransaction.commit()
    }

    /// Fit scale against the (possibly width/height-swapped) rotated size.
    private func fitScale(for image: NSImage) -> CGFloat {
        let size = rotationQuarters % 2 == 1
            ? CGSize(width: image.size.height, height: image.size.width)
            : image.size
        return min(bounds.width / size.width, bounds.height / size.height)
    }

    /// Layer bounds — the rendered size BEFORE rotation.
    private func contentSize(for image: NSImage) -> CGSize {
        let scale = fitScale(for: image) * zoom
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    /// View-space size — what the rotated image occupies on screen.
    private func renderedSize(for image: NSImage) -> CGSize {
        let content = contentSize(for: image)
        return rotationQuarters % 2 == 1
            ? CGSize(width: content.height, height: content.width)
            : content
    }

    private func imagePoint(at viewPoint: CGPoint, image: NSImage) -> CGPoint {
        let rendered = renderedSize(for: image)
        let centerX = bounds.midX + (0.5 - normalizedCenter.x) * rendered.width
        let centerY = bounds.midY + (0.5 - normalizedCenter.y) * rendered.height
        return CGPoint(x: (viewPoint.x - centerX) / rendered.width + 0.5,
                       y: (viewPoint.y - centerY) / rendered.height + 0.5)
    }

    private func setCenter(so imagePoint: CGPoint, remainsAt viewPoint: CGPoint, image: NSImage) {
        let rendered = renderedSize(for: image)
        normalizedCenter.x = 0.5 - (viewPoint.x - bounds.midX - (imagePoint.x - 0.5) * rendered.width) / rendered.width
        normalizedCenter.y = 0.5 - (viewPoint.y - bounds.midY - (imagePoint.y - 0.5) * rendered.height) / rendered.height
        panOffset = CGPoint(x: (0.5 - normalizedCenter.x) * rendered.width,
                            y: (0.5 - normalizedCenter.y) * rendered.height)
        constrainPan(rendered: rendered)
    }

    private func constrainPan(rendered: CGSize) {
        let maxPanX = max(0, (rendered.width - bounds.width) / 2)
        let maxPanY = max(0, (rendered.height - bounds.height) / 2)
        panOffset.x = max(-maxPanX, min(maxPanX, panOffset.x))
        panOffset.y = max(-maxPanY, min(maxPanY, panOffset.y))
        normalizedCenter = CGPoint(x: 0.5 - panOffset.x / max(rendered.width, 1),
                                   y: 0.5 - panOffset.y / max(rendered.height, 1))
    }

    private func notify() {
        onViewportChange?(InspectViewportState(zoomRelativeToFit: zoom, normalizedCenter: normalizedCenter))
    }
}

final class ImageRevealView: NSView {
    let viewport = InspectImageViewport()
    private let overlayViewport = InspectImageViewport()
    private let loadingView = ModularImageLoadingView(frame: .zero)
    private let failureView = LoadFailedAnimationView(frame: .zero)
    private let maskLayer = CALayer()
    private let divider = NSView()
    private var fraction: CGFloat = 0.5
    var revealFraction: CGFloat { fraction }
    /// Right-click action-menu callback, shared with the plain viewports.
    var onActionMenu: ((NSEvent) -> Void)?
    weak var dropTarget: MediaDropCanvasView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(MediaDropCanvasView.imageDraggedTypes)
        wantsLayer = true
        viewport.loadingIndicatorEnabled = false
        overlayViewport.loadingIndicatorEnabled = false
        addSubview(viewport)
        addSubview(overlayViewport)
        addSubview(loadingView)
        addSubview(failureView)
        failureView.isHidden = true
        overlayViewport.isInteractionEnabled = false
        viewport.onViewportChange = { [weak overlayViewport] state in
            overlayViewport?.apply(state: state, notify: false)
        }
        overlayViewport.wantsLayer = true
        overlayViewport.layer?.mask = maskLayer
        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.textPrimary.withAlphaComponent(0.82).cgColor
        addSubview(divider)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.acceptsDragging(sender) == true ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDrop(sender) == true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    /// Slider rotates both layers together (the pair shares one viewport state).
    func rotate(byQuarters delta: Int) {
        viewport.rotate(byQuarters: delta)
        overlayViewport.rotate(byQuarters: delta)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let onActionMenu {
            onActionMenu(event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    func setImages(a: NSImage?, b: NSImage?, failed: Bool = false) {
        viewport.image = a
        overlayViewport.image = b
        let isWaitingForPair = a == nil || b == nil
        viewport.isHidden = isWaitingForPair
        overlayViewport.isHidden = isWaitingForPair
        divider.isHidden = isWaitingForPair
        failureView.isHidden = !failed
        loadingView.setLoading(isWaitingForPair && !failed)
    }

    override func layout() {
        super.layout()
        viewport.frame = bounds
        overlayViewport.frame = bounds
        let loaderSize = ModularImageLoadingView.preferredSize
        loadingView.frame = NSRect(x: bounds.midX - loaderSize.width / 2,
                                   y: bounds.midY - loaderSize.height / 2,
                                   width: loaderSize.width,
                                   height: loaderSize.height)
        let failureSize = LoadFailedAnimationView.preferredSize
        failureView.frame = NSRect(x: bounds.midX - failureSize.width / 2,
                                   y: bounds.midY - failureSize.height / 2,
                                   width: failureSize.width,
                                   height: failureSize.height)
        updateMask()
    }

    override func mouseDragged(with event: NSEvent) {
        fraction = max(0, min(1, convert(event.locationInWindow, from: nil).x / max(bounds.width, 1)))
        updateMask()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            viewport.mouseDown(with: event)
            overlayViewport.apply(state: viewport.viewportState, notify: false)
            return
        }
        fraction = max(0, min(1, convert(event.locationInWindow, from: nil).x / max(bounds.width, 1)))
        updateMask()
    }

    override func scrollWheel(with event: NSEvent) {
        viewport.scrollWheel(with: event)
        overlayViewport.apply(state: viewport.viewportState, notify: false)
    }

    override func magnify(with event: NSEvent) {
        viewport.magnify(with: event)
        overlayViewport.apply(state: viewport.viewportState, notify: false)
    }

    private func updateMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.backgroundColor = NSColor.black.cgColor
        maskLayer.frame = NSRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        divider.frame = NSRect(x: bounds.width * fraction - 1, y: 0, width: 2, height: bounds.height)
        CATransaction.commit()
    }
}

final class ImageFilmstripView: NSView {
    private static let itemWidth: CGFloat = 48
    private static let itemHeight: CGFloat = 50
    private static let itemGap: CGFloat = 8
    private static let horizontalPadding: CGFloat = 16

    var onSelect: ((Int) -> Void)?
    var onCompare: ((Int) -> Void)?
    private var itemViews: [ImageFilmstripItem] = []
    private var infos: [MediaInfo] = []
    private var images: [NSImage?] = []
    private var selectedIndex = 0
    private var compareIndices: (Int, Int)?
    /// Generated type icons for non-image items (mixed sessions), by index.
    private var iconCache: [Int: NSImage] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue < 0.05 ? nil : super.hitTest(point)
    }

    func configure(infos: [MediaInfo], images: [NSImage?], selectedIndex: Int,
                   compareIndices: (Int, Int)?) {
        self.infos = infos
        self.images = images
        self.selectedIndex = selectedIndex
        self.compareIndices = compareIndices
        iconCache.removeAll()
        rebuild()
    }

    private func thumbnail(for index: Int) -> NSImage? {
        if let image = images[safe: index] ?? nil { return image }
        guard infos.indices.contains(index), infos[index].kind != .image else { return nil }
        if let cached = iconCache[index] { return cached }
        let icon = FileTypeIcon.makeImage(for: infos[index], size: CGSize(width: 96, height: 96))
        iconCache[index] = icon
        return icon
    }

    private func rebuild() {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        let count = infos.count
        guard count > 0 else { return }
        let gap = Self.itemGap
        let itemWidth = Self.itemWidth
        let itemHeight = Self.itemHeight
        // Fit the row within the available width so no scroll bar is needed.
        let maxRowWidth = bounds.width - Self.horizontalPadding * 2
        let naturalWidth = CGFloat(count) * itemWidth + CGFloat(count - 1) * gap
        let rowWidth = min(naturalWidth, maxRowWidth)
        let cellWidth = count > 1
            ? (rowWidth - CGFloat(count - 1) * gap) / CGFloat(count)
            : itemWidth
        var x = (bounds.width - rowWidth) / 2
        let cellHeight = itemHeight * min(1, cellWidth / itemWidth)
        let itemY = (bounds.height - cellHeight) / 2
        for index in 0..<count {
            let item = ImageFilmstripItem(frame: NSRect(x: x, y: itemY, width: cellWidth, height: cellHeight))
            let isCompared = compareIndices.map { $0.0 == index || $0.1 == index } ?? false
            // In compare mode the border means pair membership only. The
            // browse/focus selection is intentionally ignored so a stale
            // focusedIndex can never create a third highlighted thumbnail.
            let isSelected = compareIndices == nil && index == selectedIndex
            let task = WidgetTaskManager.shared.latestRecord(for: infos[index].url)
            item.configure(image: thumbnail(for: index), title: infos[index].filename,
                           selected: isSelected,
                           compared: isCompared,
                           taskPhase: task?.phase,
                           activeTaskCount: WidgetTaskManager.shared.activeRecords(for: infos[index].url).count)
            item.onClick = { [weak self] modifiers in
                if modifiers.contains(.option) { self?.onCompare?(index) }
                else { self?.onSelect?(index) }
            }
            addSubview(item)
            itemViews.append(item)
            x += cellWidth + gap
        }
    }

    override func layout() {
        super.layout()
        rebuild()
    }
}

private final class NonHitTestingImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class ImageFilmstripItem: NSView {
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    private let imageView = NonHitTestingImageView()
    private let taskBadge = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        taskBadge.cornerRadius = 3.5
        taskBadge.isHidden = true
        layer?.addSublayer(taskBadge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(event.modifierFlags) }
    override func accessibilityPerformPress() -> Bool {
        onClick?([])
        return true
    }
    func configure(image: NSImage?, title: String, selected: Bool, compared: Bool,
                   taskPhase: WidgetTaskPhase?, activeTaskCount: Int) {
        imageView.image = image
        toolTip = title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        let processing = taskPhase?.isActive == true
        let failed = taskPhase == .failed || taskPhase == .interrupted
        layer?.borderWidth = selected || compared || processing ? 2 : 0
        layer?.borderColor = PanelStyle.warmCue.cgColor
        taskBadge.isHidden = !processing && !failed
        taskBadge.backgroundColor = (failed ? NSColor.systemRed : PanelStyle.warmCue).cgColor
        layer?.removeAnimation(forKey: "widgetBreathing")
        if processing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = CABasicAnimation(keyPath: "borderColor")
            animation.fromValue = PanelStyle.warmCue.withAlphaComponent(0.30).cgColor
            animation.toValue = PanelStyle.warmCue.cgColor
            animation.duration = 0.75
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(animation, forKey: "widgetBreathing")
        }
        if processing { setAccessibilityLabel("\(title), \(activeTaskCount) Widget task running") }
        else if failed { setAccessibilityLabel("\(title), Widget task failed") }
    }

    override func layout() {
        super.layout()
        imageView.frame = NSRect(x: 3, y: 3, width: bounds.width - 6, height: bounds.height - 6)
        taskBadge.frame = NSRect(x: bounds.maxX - 9, y: bounds.maxY - 9, width: 7, height: 7)
    }
}

/// One image's full metadata as a self-contained block. A soft glowing border
/// can be toggled so the user sees which on-screen image this block describes.
final class ImageInfoBlock: NSView {
    /// Fixed card width, also used by ImageDifferencePanel for the width
    /// constraint, so column math here always matches the rendered width.
    static let cardWidth: CGFloat = 300

    let index: Int
    private let container = NSView()

    init(index: Int, info: MediaInfo, metadata: ImageTechnicalMetadata?,
         rowOverrides: [(String, String)]? = nil) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = PanelStyle.overlay.withAlphaComponent(0.62).cgColor
        container.layer?.borderWidth = 1.5
        container.layer?.borderColor = NSColor.clear.cgColor
        addSubview(container)

        let inset: CGFloat = 12
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        container.addSubview(stack)

        // Filename: wraps to as many lines as needed instead of truncating.
        let name = NSTextField(wrappingLabelWithString: info.filename)
        name.font = PanelStyle.headline
        name.textColor = PanelStyle.textPrimary
        name.maximumNumberOfLines = 0
        name.lineBreakMode = .byCharWrapping
        name.isSelectable = true
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(name)
        name.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -inset * 2).isActive = true

        // Thin divider between the name and the metadata grid.
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = PanelStyle.hairline.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(divider)
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        divider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -inset * 2).isActive = true

        // Metadata laid out in a TWO-COLUMN grid so the card grows wide and
        // short (landscape) rather than tall and narrow.
        let rows = rowOverrides ?? Self.metadataRows(info, metadata: metadata)
        // Fixed column widths derived from the card width, so value labels get
        // a definite width to wrap against instead of truncating with "…".
        let columnWidth = (Self.cardWidth - inset * 2 - 14) / 2
        let mid = Int(ceil(Double(rows.count) / 2.0))
        let leftRows = Array(rows[0..<mid])
        let rightRows = Array(rows[mid...])
        var gridRows: [[NSView]] = []
        for i in 0..<max(leftRows.count, rightRows.count) {
            let left = leftRows[safe: i].map { Self.makePair(key: $0.0, value: $0.1, width: columnWidth) } ?? NSView()
            let right = rightRows[safe: i].map { Self.makePair(key: $0.0, value: $0.1, width: columnWidth) } ?? NSView()
            gridRows.append([left, right])
        }
        let grid = NSGridView(views: gridRows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 8
        grid.columnSpacing = 14
        if grid.numberOfColumns >= 2 {
            grid.column(at: 0).width = columnWidth
            grid.column(at: 1).width = columnWidth
        }
        stack.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -inset * 2).isActive = true

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Landscape by default: at least 16:9 wide, but allowed to grow taller
        // so all metadata is shown in full when two columns aren't enough.
        let minRatio = container.heightAnchor.constraint(
            greaterThanOrEqualTo: container.widthAnchor, multiplier: 9.0 / 16.0)
        minRatio.priority = .defaultHigh
        minRatio.isActive = true
    }

    /// A muted uppercase key over a bright value, used as one grid cell.
    /// The value wraps to as many lines as needed instead of truncating.
    private static func makePair(key: String, value: String, width: CGFloat) -> NSView {
        let pair = NSStackView()
        pair.orientation = .vertical
        pair.alignment = .leading
        pair.spacing = 1
        pair.translatesAutoresizingMaskIntoConstraints = false

        let keyLabel = NSTextField(labelWithString: key.uppercased())
        keyLabel.font = .systemFont(ofSize: 10, weight: .medium)
        keyLabel.textColor = PanelStyle.textTertiary
        pair.addArrangedSubview(keyLabel)

        let valueLabel = NSTextField(wrappingLabelWithString: value)
        valueLabel.font = PanelStyle.body
        valueLabel.textColor = PanelStyle.textPrimary
        valueLabel.lineBreakMode = .byWordWrapping
        valueLabel.maximumNumberOfLines = 0
        valueLabel.isSelectable = true
        valueLabel.preferredMaxLayoutWidth = width
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.widthAnchor.constraint(equalToConstant: width).isActive = true
        pair.addArrangedSubview(valueLabel)
        return pair
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setHighlighted(_ highlighted: Bool) {
        // Soft, neutral highlight — a subtly brighter fill and faint white
        // hairline border, no blue accent, no glow.
        let layer = container.layer
        layer?.backgroundColor = (highlighted ? PanelStyle.overlay
                                              : PanelStyle.overlay.withAlphaComponent(0.62)).cgColor
        layer?.borderColor = (highlighted ? PanelStyle.warmCue.withAlphaComponent(0.34)
                                          : NSColor.clear).cgColor
        layer?.removeAnimation(forKey: "glow")
        layer?.shadowOpacity = 0
    }

    static func metadataRows(_ info: MediaInfo, metadata: ImageTechnicalMetadata?) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let size = info.dimensions, size.height > 0 {
            rows.append(("Dimensions".localized, "\(Int(size.width)) × \(Int(size.height)) px"))
            rows.append(("Aspect ratio".localized, String(format: "%.3f", size.width / size.height)))
        }
        if let bytes = info.fileSize {
            rows.append(("File size".localized, ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
        }
        if info.formatName.isDisplayableValue { rows.append(("Format".localized, info.formatName)) }
        if let color = metadata?.colorSpace, color.isDisplayableValue {
            rows.append(("Color space".localized, color))
        }
        if let depth = metadata?.bitDepth { rows.append(("Bit depth".localized, "\(depth)-bit")) }
        if let alpha = metadata?.hasAlpha {
            rows.append(("Alpha".localized, alpha ? "Yes".localized : "No".localized))
        }
        return rows
    }
}

/// Scrolling column of per-image info blocks (one block per on-screen image).
final class ImageDifferencePanel: NSView {
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private(set) var blocks: [ImageInfoBlock] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Transparent so the window's frosted base shows through.
        layer?.backgroundColor = NSColor.clear.cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        // Only show the scroller when content overflows, and overlay it so it
        // never steals width from the info blocks.
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        // Flipped document view so its origin is at the TOP-LEFT — content
        // stacks downward from the top instead of sitting at the bottom.
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        // 10pt padding on all sides; blocks then fill the remaining width.
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        doc.addSubview(stack)
        scroll.documentView = doc
        addSubview(scroll)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        if let doc = scroll.documentView {
            doc.frame.size.width = bounds.width
        }
    }

    /// `items` is the ordered list of (image index, info, metadata) currently on
    /// screen. Rebuilds one block per image.
    func show(items: [(index: Int, info: MediaInfo, metadata: ImageTechnicalMetadata?)]) {
        rebuild(items.map { ImageInfoBlock(index: $0.index, info: $0.info, metadata: $0.metadata) })
    }

    /// Video inspect supplies its own metadata rows (codec, frame rate, …) but
    /// renders through the same card layout.
    func show(items: [(index: Int, info: MediaInfo, rows: [(String, String)])]) {
        rebuild(items.map { ImageInfoBlock(index: $0.index, info: $0.info, metadata: nil, rowOverrides: $0.rows) })
    }

    private func rebuild(_ newBlocks: [ImageInfoBlock]) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        blocks.removeAll()

        for block in newBlocks {
            stack.addArrangedSubview(block)
            block.widthAnchor.constraint(equalToConstant: ImageInfoBlock.cardWidth).isActive = true
            blocks.append(block)
        }
        needsLayout = true
    }

    func highlight(index: Int?) {
        for block in blocks {
            block.setHighlighted(block.index == index)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Immutable snapshot of what ⌘S should render. Rendering happens on the
/// background queue so large compare images never block the main thread.
private enum QuickSaveSource {
    case single(NSImage, Int)
    case sideBySide(NSImage, Int, NSImage, Int)
    case slider(NSImage, Int, NSImage, Int, CGFloat)

    func render() -> CGImage? {
        switch self {
        case .single(let image, let rotation):
            return ImageExporter.cgImage(from: image, rotatedQuarters: rotation)
        case .sideBySide(let a, let aRotation, let b, let bRotation):
            guard let aCG = ImageExporter.cgImage(from: a, rotatedQuarters: aRotation),
                  let bCG = ImageExporter.cgImage(from: b, rotatedQuarters: bRotation) else { return nil }
            return ImageExporter.sideBySide(a: aCG, b: bCG)
        case .slider(let a, let aRotation, let b, let bRotation, let fraction):
            guard let aCG = ImageExporter.cgImage(from: a, rotatedQuarters: aRotation),
                  let bCG = ImageExporter.cgImage(from: b, rotatedQuarters: bRotation) else { return nil }
            return ImageExporter.slider(a: aCG, b: bCG, fraction: fraction)
        }
    }
}

private enum ImageExportFormat {
    case png, jpeg, webP, icns

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .webP: return UTType("org.webmproject.webp") ?? .png
        case .icns: return UTType("com.apple.icns")!
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .webP: return "webp"
        case .icns: return "icns"
        }
    }
}

/// Encodes an NSImage to disk via ImageIO — NSBitmapImageRep has no WebP
/// support, while CGImageDestination covers PNG/JPEG/WebP uniformly.
/// Never mutates the source file; always writes a new one chosen in a
/// Save panel.
private enum ImageExporter {
    static func write(image: NSImage, rotatedQuarters: Int, to url: URL,
                      format: ImageExportFormat) -> Bool {
        guard let output = cgImage(from: image, rotatedQuarters: rotatedQuarters) else { return false }
        return write(cgImage: output, to: url, format: format)
    }

    static func cgImage(from image: NSImage, rotatedQuarters: Int) -> CGImage? {
        guard let image = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let quarters = ((rotatedQuarters % 4) + 4) % 4
        guard quarters != 0 else { return image }
        return rotate(image, quarters: quarters)
    }

    static func write(cgImage: CGImage, to url: URL, format: ImageExportFormat) -> Bool {
        if format == .icns {
            return writeIcon(cgImage: cgImage, to: url)
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else { return false }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// Build a multi-resolution macOS icon. Every representation is square;
    /// non-square sources are aspect-fitted on a transparent canvas so the
    /// artwork is never stretched or cropped.
    private static func writeIcon(cgImage: CGImage, to url: URL) -> Bool {
        // The duplicate pixel sizes are distinct 1x/2x icon representations.
        // ImageIO uses 144 DPI to identify Retina entries; without it, the
        // 64px and 1024px representations are silently omitted from the ICNS.
        let representations = [
            (side: 16, dpi: 72),
            (side: 32, dpi: 144), (side: 32, dpi: 72),
            (side: 64, dpi: 144),
            (side: 128, dpi: 72),
            (side: 256, dpi: 144), (side: 256, dpi: 72),
            (side: 512, dpi: 144), (side: 512, dpi: 72),
            (side: 1024, dpi: 144),
        ]
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            ImageExportFormat.icns.utType.identifier as CFString,
            representations.count,
            nil
        ) else { return false }

        for representation in representations {
            let side = representation.side
            guard let context = makeContext(width: side, height: side) else { return false }
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .high
            drawAspectFit(cgImage,
                          in: CGRect(x: 0, y: 0, width: side, height: side),
                          context: context)
            guard let outputImage = context.makeImage() else { return false }
            let properties: [CFString: Any] = [
                kCGImagePropertyDPIWidth: representation.dpi,
                kCGImagePropertyDPIHeight: representation.dpi,
            ]
            CGImageDestinationAddImage(destination, outputImage, properties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }

    static func sideBySide(a: CGImage, b: CGImage) -> CGImage? {
        var height = min(4096, CGFloat(max(a.height, b.height)))
        var aWidth = CGFloat(a.width) * height / CGFloat(a.height)
        var bWidth = CGFloat(b.width) * height / CGFloat(b.height)
        let gap: CGFloat = 2
        if aWidth + bWidth + gap > 8192 {
            let scale = (8192 - gap) / (aWidth + bWidth)
            height *= scale
            aWidth *= scale
            bWidth *= scale
        }
        let width = aWidth + gap + bWidth
        guard let context = makeContext(width: Int(ceil(width)), height: Int(ceil(height))) else { return nil }
        fillCanvas(context, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(a, in: CGRect(x: 0, y: 0, width: aWidth, height: height))
        context.draw(b, in: CGRect(x: aWidth + gap, y: 0, width: bWidth, height: height))
        return context.makeImage()
    }

    static func slider(a: CGImage, b: CGImage, fraction: CGFloat) -> CGImage? {
        let rawWidth = CGFloat(max(a.width, b.width))
        let rawHeight = CGFloat(max(a.height, b.height))
        let scale = min(1, 4096 / max(rawWidth, rawHeight))
        let width = max(1, ceil(rawWidth * scale))
        let height = max(1, ceil(rawHeight * scale))
        guard let context = makeContext(width: Int(width), height: Int(height)) else { return nil }
        fillCanvas(context, width: width, height: height)
        context.interpolationQuality = .high
        drawAspectFit(a, in: CGRect(x: 0, y: 0, width: width, height: height), context: context)
        let split = max(0, min(1, fraction)) * width
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: split, height: height))
        drawAspectFit(b, in: CGRect(x: 0, y: 0, width: width, height: height), context: context)
        context.restoreGState()
        context.setFillColor(PanelStyle.textPrimary.withAlphaComponent(0.82).cgColor)
        context.fill(CGRect(x: max(0, split - 1), y: 0, width: 2, height: height))
        return context.makeImage()
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func fillCanvas(_ context: CGContext, width: CGFloat, height: CGFloat) {
        context.setFillColor(PanelStyle.imageCanvas.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func drawAspectFit(_ image: CGImage, in bounds: CGRect, context: CGContext) {
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
        context.draw(image, in: rect)
    }

    /// Quarter-turn rotation into a fresh bitmap. quarters = 1 means 90°
    /// clockwise, matching the viewport's layer transform.
    static func rotate(_ image: CGImage, quarters: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        let swapped = quarters % 2 == 1
        let outWidth = swapped ? height : width
        let outHeight = swapped ? width : height
        guard let context = CGContext(data: nil, width: outWidth, height: outHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        switch quarters {
        case 1: // 90° clockwise
            context.translateBy(x: 0, y: CGFloat(width))
            context.rotate(by: -.pi / 2)
        case 2: // 180°
            context.translateBy(x: CGFloat(width), y: CGFloat(height))
            context.rotate(by: .pi)
        case 3: // 90° counterclockwise
            context.translateBy(x: CGFloat(height), y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
