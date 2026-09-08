import AppKit

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

    init(infos: [MediaInfo], images: [NSImage?], focusedIndex: Int, mode: Mode? = nil) {
        self.infos = infos
        self.images = images
        self.focusedIndex = min(max(0, focusedIndex), max(0, infos.count - 1))
        self.mode = mode ?? (infos.count > 1 ? .browse : .focus)
        self.metadata = Array(repeating: nil, count: infos.count)
        if self.mode == .compare, infos.count >= 2 {
            compareIndices = (0, 1)
        }
    }
}

final class ImageInspectWindow: NSWindow, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let imageLoader: ImageLoader
    private var session: ImageInspectSession?
    private var loadGeneration = UUID()

    private let focusButton = InspectToolbarButton(symbol: "photo", tooltip: "Focus".localized)
    private let sideBySideButton = InspectToolbarButton(symbol: "rectangle.split.2x1", tooltip: "Side by side".localized)
    private let sliderButton = InspectToolbarButton(symbol: "slider.horizontal.3", tooltip: "Slider".localized)
    private let infoButton = InspectToolbarButton(symbol: "info.circle", tooltip: "Image information".localized)
    private let revealButton = InspectToolbarButton(symbol: "folder", tooltip: "Reveal in Finder".localized)
    private let canvasContainer = NSView()
    private let primaryViewport = InspectImageViewport()
    private let secondaryViewport = InspectImageViewport()
    private let sliderViewport = ImageRevealView()
    private let filmstrip = ImageFilmstripView()
    private let infoPanel = ImageDifferencePanel()
    private let identityBar = InspectIdentityBar()
    private let identityNameLabel = NSTextField(labelWithString: "")
    private let identityMetaLabel = NSTextField(labelWithString: "")
    private let toolbarBar = InspectIdentityBar()
    private var toolbarHideWorkItem: DispatchWorkItem?
    private var isClosingProgrammatically = false
    private let toolbarHeight: CGFloat = 34
    private var imageHoverFrame = NSRect.zero
    /// Independent floating window that hosts the info panel, separate from the
    /// main image window so it can be moved freely.
    private lazy var infoWindow = ImageInfoPanelWindow(panel: infoPanel)
    private var infoVisible = false
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
        NotificationCenter.default.addObserver(self, selector: #selector(localizationDidChange),
                                               name: .languageDidChange, object: nil)
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
        infoWindow.orderOut(nil)
        infoVisible = false
        session = nil
        loadGeneration = UUID()
        guard !isClosingProgrammatically else { return }
        onClose?()
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
        guard session != nil else { return super.performKeyEquivalent(with: event) }
        let key = event.charactersIgnoringModifiers ?? ""
        if event.modifierFlags.contains(.command) {
            if key == "0" { activeViewports.forEach { $0.fitToView() }; return true }
            if key == "1" { activeViewports.forEach { $0.setActualSize() }; return true }
            if key.lowercased() == "i" { toggleInfo(); return true }
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
            if session.mode == .compare, session.comparisonStyle == .sideBySide {
                if primaryViewport.frame.contains(point) {
                    primaryViewport.magnify(with: event)
                } else if secondaryViewport.frame.contains(point) {
                    secondaryViewport.magnify(with: event)
                }
            } else if session.mode == .compare, session.comparisonStyle == .slider {
                sliderViewport.magnify(with: event)
            } else {
                primaryViewport.magnify(with: event)
            }
            return
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
            } else if primaryViewport.frame.contains(point) {
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
        guard let root = contentView else { return }
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.imageCanvas.cgColor

        canvasContainer.frame = root.bounds
        canvasContainer.autoresizingMask = [.width, .height]
        canvasContainer.wantsLayer = true
        canvasContainer.layer?.backgroundColor = PanelStyle.imageCanvas.cgColor
        root.addSubview(canvasContainer)

        for view in [primaryViewport, secondaryViewport, sliderViewport] {
            view.autoresizingMask = [.width, .height]
            canvasContainer.addSubview(view)
        }
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
        for button in [focusButton, sideBySideButton, sliderButton, infoButton, revealButton] {
            button.autoresizingMask = [.minXMargin]
            toolbarBar.addSubview(button)
        }
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
        guard let root = contentView else { return }
        canvasContainer.frame = root.bounds

        // The info panel is now a separate floating window, so the image always
        // uses the full content width.
        let contentFrame = NSRect(x: 0, y: 0, width: canvasContainer.bounds.width,
                                  height: canvasContainer.bounds.height)

        identityBar.frame = NSRect(x: 0, y: 0, width: contentFrame.width, height: identityBarHeight)
        let labelX: CGFloat = 18
        let labelWidth = max(80, identityBar.bounds.width - labelX * 2)
        identityNameLabel.frame = NSRect(x: labelX, y: 30, width: labelWidth, height: 17)
        identityMetaLabel.frame = NSRect(x: labelX, y: 10, width: labelWidth, height: 15)

        // Floating hover toolbar: a full-width bar across the top of the image,
        // with the icons right-aligned.
        toolbarBar.frame = NSRect(x: 0, y: contentFrame.height - toolbarHeight,
                                  width: contentFrame.width, height: toolbarHeight)
        let buttonSize: CGFloat = 26
        let buttonGap: CGFloat = 4
        let buttons = [focusButton, sideBySideButton, sliderButton, infoButton, revealButton]
        let rightMargin: CGFloat = 12
        var bx = toolbarBar.bounds.width - rightMargin - buttonSize
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

        filmstrip.frame = NSRect(x: 0, y: identityBarHeight + 12,
                                 width: contentFrame.width, height: 86)
    }

    private func renderSession() {
        guard let session, session.infos.indices.contains(session.focusedIndex) else { return }
        let info = session.infos[session.focusedIndex]
        updateWindowTitle(for: info, index: session.focusedIndex)
        updateIdentityBar(for: info, index: session.focusedIndex)
        let hasMultipleImages = session.infos.count >= 2
        // Keep the compare buttons visible but disabled for a single image, so
        // the titlebar icon row never collapses to just one button.
        focusButton.isEnabled = hasMultipleImages
        sideBySideButton.isEnabled = hasMultipleImages
        sliderButton.isEnabled = hasMultipleImages
        focusButton.isActive = session.mode != .compare
        sideBySideButton.isActive = session.mode == .compare && session.comparisonStyle == .sideBySide
        sliderButton.isActive = session.mode == .compare && session.comparisonStyle == .slider
        infoButton.isActive = infoVisible
        updateRevealButtonState()

        primaryViewport.isHidden = false
        secondaryViewport.isHidden = true
        sliderViewport.isHidden = true
        primaryViewport.isActiveSlot = false
        secondaryViewport.isActiveSlot = false
        primaryViewport.image = session.images[safe: session.focusedIndex] ?? nil

        if session.mode == .compare, let (a, b) = session.compareIndices,
           session.infos.indices.contains(a), session.infos.indices.contains(b) {
            if session.comparisonStyle == .sideBySide {
                secondaryViewport.isHidden = false
                primaryViewport.image = session.images[safe: a] ?? nil
                secondaryViewport.image = session.images[safe: b] ?? nil
                // Show which side a filmstrip tap will replace.
                primaryViewport.isActiveSlot = session.activeCompareSlot == 0
                secondaryViewport.isActiveSlot = session.activeCompareSlot == 1
            } else {
                primaryViewport.isHidden = true
                sliderViewport.isHidden = false
                sliderViewport.setImages(a: session.images[safe: a] ?? nil,
                                         b: session.images[safe: b] ?? nil)
            }
            infoPanel.show(items: [
                (a, session.infos[a], session.metadata[safe: a] ?? nil),
                (b, session.infos[b], session.metadata[safe: b] ?? nil),
            ])
        } else {
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
            if session.images[safe: index] ?? nil == nil,
               !fullResolutionIndices.contains(index) {
                imageLoader.loadImage(from: info.url) { [weak self] image in
                    guard let self, generation == self.loadGeneration,
                          let session = self.session, session.images.indices.contains(index), let image else { return }
                    session.images[index] = image
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
            imageLoader.loadFullResolutionImage(from: info.url) { [weak self] image in
                guard let self, generation == self.loadGeneration,
                      let session = self.session, session.images.indices.contains(index), let image else { return }
                session.images[index] = image
                session.infos[index].dimensions = image.size
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

    @objc private func sideBySideTapped() {
        activateCompare(style: .sideBySide)
    }

    @objc private func sliderTapped() {
        activateCompare(style: .slider)
    }

    private func activateCompare(style: ImageInspectSession.ComparisonStyle) {
        guard let session, session.infos.count > 1 else { return }
        session.comparisonStyle = style
        if session.compareIndices == nil {
            let other = session.focusedIndex == 0 ? 1 : 0
            session.compareIndices = (session.focusedIndex, other)
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
        if infoVisible { infoWindow.title = "Image information".localized }
        renderSession()
    }

    @objc private func revealInFinderTapped() {
        guard let info = currentRevealInfo, info.isLocal else { return }
        NSWorkspace.shared.activateFileViewerSelecting([info.url])
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
            infoWindow.orderFront(nil)
        } else {
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
        if session.mode == .compare, let pair = session.compareIndices {
            // Replace whichever slot is active (left or right), so both sides
            // can be changed. Avoid pointing both slots at the same image.
            if session.activeCompareSlot == 0 {
                guard index != pair.1 else { return }
                session.compareIndices = (index, pair.1)
            } else {
                guard index != pair.0 else { return }
                session.compareIndices = (pair.0, index)
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
        updateRevealButtonState()
        if let pair = session.compareIndices {
            infoPanel.highlight(index: slot == 0 ? pair.0 : pair.1)
        }
    }

    private func navigate(by delta: Int) {
        guard let session, !session.infos.isEmpty else { return }
        if session.mode == .compare, let pair = session.compareIndices {
            var candidate = (pair.1 + delta + session.infos.count) % session.infos.count
            if candidate == pair.0 {
                candidate = (candidate + delta + session.infos.count) % session.infos.count
            }
            guard candidate != pair.0 else { return }
            session.compareIndices = (pair.0, candidate)
        } else {
            session.focusedIndex = (session.focusedIndex + delta + session.infos.count) % session.infos.count
        }
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
    }

    private func compare(focusedWith index: Int) {
        guard let session, session.infos.indices.contains(index), index != session.focusedIndex else { return }
        session.mode = .compare
        session.compareIndices = (session.focusedIndex, index)
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
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

/// Standalone floating window that hosts the image info panel, independent of
/// the main image window so the user can move it around freely.
final class ImageInfoPanelWindow: NSPanel {
    init(panel: ImageDifferencePanel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 320, height: 240)
        contentMaxSize = NSSize(width: 320, height: 10000)
        title = "Image information".localized
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.frame = contentView?.bounds ?? .zero
        panel.autoresizingMask = [.width, .height]
        contentView?.addSubview(panel)
    }
}

private final class InspectIdentityBar: NSVisualEffectView {
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
}

private final class InspectToolbarButton: NSButton {
    var isActive = false { didSet { updateAppearance() } }

    init(symbol: String, tooltip: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        imagePosition = .imageOnly
        toolTip = tooltip
        isBordered = false
        bezelStyle = .recessed
        contentTintColor = PanelStyle.textPrimary
        wantsLayer = true
        layer?.cornerRadius = 7
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func updateTooltip(_ tooltip: String) {
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    private func updateAppearance() {
        layer?.backgroundColor = isActive
            ? PanelStyle.controlFillHi.cgColor
            : NSColor.clear.cgColor
        // Dim disabled compare buttons so the user can see they are inactive
        // for a single image, instead of looking tappable but doing nothing.
        contentTintColor = isEnabled ? PanelStyle.textPrimary : PanelStyle.textTertiary
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
            imageLayer.contents = image
            loadingView.setLoading(image == nil && loadingIndicatorEnabled)
            fitToView()
        }
    }
    var onViewportChange: ((InspectViewportState) -> Void)?
    var isInteractionEnabled = true
    var loadingIndicatorEnabled = true {
        didSet { loadingView.setLoading(image == nil && loadingIndicatorEnabled) }
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
    private var zoom: CGFloat = 1
    private var normalizedCenter = CGPoint(x: 0.5, y: 0.5)
    private var panOffset = CGPoint.zero
    private var lastMouseLocation = CGPoint.zero
    private var dragging = false
    private var activeIndicatorVisible = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.imageCanvas.cgColor
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
        activeIndicator.backgroundColor = NSColor.clear.cgColor
        activeIndicator.borderColor = PanelStyle.warmCue.withAlphaComponent(0.62).cgColor
        activeIndicator.borderWidth = 2
        activeIndicator.cornerRadius = 1.5
        activeIndicator.shadowColor = PanelStyle.warmCue.cgColor
        activeIndicator.shadowOpacity = 0.22
        activeIndicator.shadowRadius = 4
        activeIndicator.shadowOffset = .zero
        activeIndicator.opacity = 0
        layer?.addSublayer(activeIndicator)
        addSubview(loadingView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractionEnabled ? super.hitTest(point) : nil
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
        let indicatorRect = bounds.insetBy(dx: 3, dy: 3)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activeIndicator.frame = indicatorRect
        CATransaction.commit()
        let loaderSize = ModularImageLoadingView.preferredSize
        loadingView.frame = NSRect(x: bounds.midX - loaderSize.width / 2,
                                   y: bounds.midY - loaderSize.height / 2,
                                   width: loaderSize.width,
                                   height: loaderSize.height)
    }

    func setActiveIndicatorVisible(_ visible: Bool, animated _: Bool, duration _: CFTimeInterval) {
        activeIndicatorVisible = visible
        updateActiveIndicator()
    }

    private func updateActiveIndicator() {
        let isVisible = activeIndicatorVisible && isActiveSlot
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
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
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
        imageLayer.bounds = NSRect(origin: .zero, size: rendered)
        imageLayer.position = CGPoint(x: centerX, y: centerY)
        CATransaction.commit()
    }

    private func renderedSize(for image: NSImage) -> CGSize {
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        return CGSize(width: image.size.width * fit * zoom, height: image.size.height * fit * zoom)
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
    private let maskLayer = CALayer()
    private let divider = NSView()
    private var fraction: CGFloat = 0.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        viewport.loadingIndicatorEnabled = false
        overlayViewport.loadingIndicatorEnabled = false
        addSubview(viewport)
        addSubview(overlayViewport)
        addSubview(loadingView)
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    func setImages(a: NSImage?, b: NSImage?) {
        viewport.image = a
        overlayViewport.image = b
        let isWaitingForPair = a == nil || b == nil
        viewport.isHidden = isWaitingForPair
        overlayViewport.isHidden = isWaitingForPair
        divider.isHidden = isWaitingForPair
        loadingView.setLoading(isWaitingForPair)
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
        rebuild()
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
            item.configure(image: images[safe: index] ?? nil, title: infos[index].filename,
                           selected: isSelected,
                           compared: isCompared)
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(event.modifierFlags) }
    override func accessibilityPerformPress() -> Bool {
        onClick?([])
        return true
    }
    func configure(image: NSImage?, title: String, selected: Bool, compared: Bool) {
        imageView.image = image
        toolTip = title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        layer?.borderWidth = selected || compared ? 2 : 0
        layer?.borderColor = PanelStyle.warmCue.cgColor
    }

    override func layout() {
        super.layout()
        imageView.frame = NSRect(x: 3, y: 3, width: bounds.width - 6, height: bounds.height - 6)
    }
}

/// One image's full metadata as a self-contained block. A soft glowing border
/// can be toggled so the user sees which on-screen image this block describes.
final class ImageInfoBlock: NSView {
    let index: Int
    private let container = NSView()

    init(index: Int, info: MediaInfo, metadata: ImageTechnicalMetadata?) {
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
        let rows = Self.metadataRows(info, metadata: metadata)
        let mid = Int(ceil(Double(rows.count) / 2.0))
        let leftRows = Array(rows[0..<mid])
        let rightRows = Array(rows[mid...])
        var gridRows: [[NSView]] = []
        for i in 0..<max(leftRows.count, rightRows.count) {
            let left = leftRows[safe: i].map { Self.makePair(key: $0.0, value: $0.1) } ?? NSView()
            let right = rightRows[safe: i].map { Self.makePair(key: $0.0, value: $0.1) } ?? NSView()
            gridRows.append([left, right])
        }
        let grid = NSGridView(views: gridRows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 8
        grid.columnSpacing = 14
        if grid.numberOfColumns >= 2 {
            grid.column(at: 0).xPlacement = .fill
            grid.column(at: 1).xPlacement = .fill
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
    private static func makePair(key: String, value: String) -> NSView {
        let pair = NSStackView()
        pair.orientation = .vertical
        pair.alignment = .leading
        pair.spacing = 1
        pair.translatesAutoresizingMaskIntoConstraints = false

        let keyLabel = NSTextField(labelWithString: key.uppercased())
        keyLabel.font = .systemFont(ofSize: 10, weight: .medium)
        keyLabel.textColor = PanelStyle.textTertiary
        pair.addArrangedSubview(keyLabel)

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = PanelStyle.body
        valueLabel.textColor = PanelStyle.textPrimary
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.isSelectable = true
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
        layer?.backgroundColor = PanelStyle.surface.cgColor
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
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        blocks.removeAll()

        for item in items {
            let block = ImageInfoBlock(index: item.index, info: item.info, metadata: item.metadata)
            stack.addArrangedSubview(block)
            block.widthAnchor.constraint(equalToConstant: 300).isActive = true
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
