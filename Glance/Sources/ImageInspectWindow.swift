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

    private let toolbarBar = PanelStyle.makeBarBlur()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(labels: ["Focus".localized, "Side by side".localized, "Slider".localized], trackingMode: .selectOne,
                                                  target: nil, action: nil)
    private let infoButton = NSButton()
    private let canvasContainer = NSView()
    private let primaryViewport = InspectImageViewport()
    private let secondaryViewport = InspectImageViewport()
    private let sliderViewport = ImageRevealView()
    private let filmstrip = ImageFilmstripView()
    private let infoPanel = ImageDifferencePanel()
    private var filmstripHideWorkItem: DispatchWorkItem?
    private var isClosingProgrammatically = false

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
        loadGeneration = UUID()
        renderSession()
        loadSessionImages(generation: loadGeneration)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        filmstripHideWorkItem?.cancel()
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
        if event.type == .mouseMoved,
           session?.infos.count ?? 0 > 1,
           event.locationInWindow.y < 120 {
            scheduleFilmstripHide()
        }
        super.sendEvent(event)
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

        toolbarBar.frame = NSRect(x: 0, y: root.bounds.height - 58, width: root.bounds.width, height: 58)
        toolbarBar.autoresizingMask = [.width, .minYMargin]
        PanelStyle.addHairline(to: toolbarBar, edge: .minY)
        root.addSubview(toolbarBar)

        titleLabel.font = PanelStyle.title
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.lineBreakMode = .byTruncatingMiddle
        toolbarBar.addSubview(titleLabel)

        subtitleLabel.font = PanelStyle.caption
        subtitleLabel.textColor = PanelStyle.textSecondary
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        toolbarBar.addSubview(subtitleLabel)

        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.selectedSegment = 0
        toolbarBar.addSubview(modeControl)

        infoButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Image information".localized)
        infoButton.isBordered = false
        infoButton.contentTintColor = PanelStyle.textPrimary
        infoButton.target = self
        infoButton.action = #selector(infoTapped)
        toolbarBar.addSubview(infoButton)

        canvasContainer.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: root.bounds.height - 58)
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

        infoPanel.isHidden = true
        canvasContainer.addSubview(infoPanel)
        layoutContent()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        layoutContent()
    }

    private func layoutContent() {
        guard let root = contentView else { return }
        let toolbarH: CGFloat = 58
        toolbarBar.frame = NSRect(x: 0, y: root.bounds.height - toolbarH, width: root.bounds.width, height: toolbarH)
        titleLabel.frame = NSRect(x: 20, y: 30, width: max(120, root.bounds.width - 440), height: 20)
        subtitleLabel.frame = NSRect(x: 20, y: 10, width: max(120, root.bounds.width - 440), height: 16)
        modeControl.frame = NSRect(x: root.bounds.width - 390, y: 15, width: 270, height: 28)
        infoButton.frame = NSRect(x: root.bounds.width - 92, y: 15, width: 30, height: 28)
        canvasContainer.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: root.bounds.height - toolbarH)

        let infoW: CGFloat = infoPanel.isHidden ? 0 : min(340, canvasContainer.bounds.width * 0.34)
        let contentFrame = NSRect(x: 0, y: 0, width: canvasContainer.bounds.width - infoW,
                                  height: canvasContainer.bounds.height)
        infoPanel.frame = NSRect(x: contentFrame.maxX, y: 0, width: infoW, height: contentFrame.height)

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

        filmstrip.frame = NSRect(x: max(16, (contentFrame.width - min(600, contentFrame.width - 32)) / 2),
                                 y: 16, width: min(600, contentFrame.width - 32), height: 86)
    }

    private func renderSession() {
        guard let session, session.infos.indices.contains(session.focusedIndex) else { return }
        let info = session.infos[session.focusedIndex]
        titleLabel.stringValue = info.filename
        subtitleLabel.stringValue = identityLine(for: info, index: session.focusedIndex)
        modeControl.isEnabled = session.infos.count >= 2
        modeControl.selectedSegment = session.mode == .compare
            ? (session.comparisonStyle == .sideBySide ? 1 : 2)
            : 0

        primaryViewport.isHidden = false
        secondaryViewport.isHidden = true
        sliderViewport.isHidden = true
        primaryViewport.image = session.images[safe: session.focusedIndex] ?? nil

        if session.mode == .compare, let (a, b) = session.compareIndices,
           session.infos.indices.contains(a), session.infos.indices.contains(b) {
            if session.comparisonStyle == .sideBySide {
                secondaryViewport.isHidden = false
                primaryViewport.image = session.images[safe: a] ?? nil
                secondaryViewport.image = session.images[safe: b] ?? nil
            } else {
                primaryViewport.isHidden = true
                sliderViewport.isHidden = false
                sliderViewport.setImages(a: session.images[safe: a] ?? nil,
                                         b: session.images[safe: b] ?? nil)
            }
            titleLabel.stringValue = "\(session.infos[a].filename)  ↔  \(session.infos[b].filename)"
            subtitleLabel.stringValue = comparisonSubtitle(a: session.infos[a], b: session.infos[b])
            infoPanel.showComparison(a: session.infos[a], metadataA: session.metadata[safe: a] ?? nil,
                                     b: session.infos[b], metadataB: session.metadata[safe: b] ?? nil)
        } else {
            infoPanel.showSingle(info: info,
                                 metadata: session.metadata[safe: session.focusedIndex] ?? nil)
        }

        filmstrip.configure(infos: session.infos, images: session.images,
                            selectedIndex: session.focusedIndex, compareIndices: session.compareIndices)
        filmstrip.isHidden = session.infos.count < 2
        if !filmstrip.isHidden { scheduleFilmstripHide() }
        layoutContent()
    }

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

    @objc private func modeChanged() {
        guard let session else { return }
        if modeControl.selectedSegment > 0 {
            session.comparisonStyle = modeControl.selectedSegment == 2 ? .slider : .sideBySide
            if session.mode != .compare || session.compareIndices == nil {
                let other = session.focusedIndex == 0 ? 1 : 0
                compare(focusedWith: other)
            } else {
                renderSession()
            }
            loadFullResolutionForActiveItems(generation: loadGeneration)
        } else {
            session.mode = session.infos.count > 1 ? .browse : .focus
            session.compareIndices = nil
            renderSession()
        }
    }

    @objc private func infoTapped() { toggleInfo() }

    private func toggleInfo() {
        infoPanel.isHidden.toggle()
        renderSession()
    }

    private func focus(index: Int) {
        guard let session, session.infos.indices.contains(index) else { return }
        if session.mode == .compare {
            let a = session.compareIndices?.0 ?? session.focusedIndex
            guard index != a else { return }
            session.compareIndices = (a, index)
        } else {
            session.focusedIndex = index
        }
        filmstrip.isHidden = false
        renderSession()
        loadFullResolutionForActiveItems(generation: loadGeneration)
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
        filmstrip.isHidden = false
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

    private func scheduleFilmstripHide() {
        filmstripHideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.filmstrip.animator().alphaValue = 0 }
        filmstripHideWorkItem = item
        filmstrip.alphaValue = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    private func closeAndRestore() {
        isClosingProgrammatically = true
        orderOut(nil)
        isClosingProgrammatically = false
        onClose?()
    }

    private func identityLine(for info: MediaInfo, index: Int) -> String {
        var parts: [String] = []
        if let session, session.infos.count > 1 { parts.append("\(index + 1) / \(session.infos.count)") }
        if let size = info.dimensions { parts.append("\(Int(size.width)) × \(Int(size.height))") }
        if !info.formatName.isEmpty { parts.append(info.formatName) }
        if let bytes = info.fileSize { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
        let location = info.isLocal ? info.url.deletingLastPathComponent().path : (info.url.host ?? info.url.absoluteString)
        if let source = info.sourceAppName { parts.append(source + " · " + location) }
        else { parts.append(location) }
        return parts.joined(separator: "  ·  ")
    }

    private func comparisonSubtitle(a: MediaInfo, b: MediaInfo) -> String {
        guard let sa = a.dimensions, let sb = b.dimensions else { return "Relative alignment".localized }
        return sa == sb ? "Pixel alignment".localized : "Relative alignment".localized
    }
}

struct InspectViewportState {
    var zoomRelativeToFit: CGFloat
    var normalizedCenter: CGPoint
}

final class InspectImageViewport: NSView {
    var image: NSImage? { didSet { imageLayer.contents = image; fitToView() } }
    var onViewportChange: ((InspectViewportState) -> Void)?
    var isInteractionEnabled = true
    var viewportState: InspectViewportState {
        InspectViewportState(zoomRelativeToFit: zoom, normalizedCenter: normalizedCenter)
    }

    private let imageLayer = CALayer()
    private var zoom: CGFloat = 1
    private var normalizedCenter = CGPoint(x: 0.5, y: 0.5)
    private var lastDragPoint = CGPoint.zero
    private var dragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.imageCanvas.cgColor
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractionEnabled ? super.hitTest(point) : nil
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
    }

    func fitToView() {
        zoom = 1
        normalizedCenter = CGPoint(x: 0.5, y: 0.5)
        updateLayerGeometry()
        notify()
    }

    func setActualSize() {
        guard let image, bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        zoom = max(1, min(20, 1 / max(fit, 0.0001)))
        updateLayerGeometry()
        notify()
    }

    func apply(state: InspectViewportState, notify shouldNotify: Bool) {
        zoom = max(1, min(20, state.zoomRelativeToFit))
        normalizedCenter = state.normalizedCenter
        updateLayerGeometry()
        if shouldNotify { notify() }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let image else { return }
        if event.modifierFlags.contains(.command) || abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            let point = convert(event.locationInWindow, from: nil)
            let before = imagePoint(at: point, image: image)
            let factor = pow(1.08, event.scrollingDeltaY)
            zoom = max(1, min(20, zoom * factor))
            setCenter(so: before, remainsAt: point, image: image)
        } else {
            pan(dx: -event.scrollingDeltaX, dy: event.scrollingDeltaY)
        }
        updateLayerGeometry()
        notify()
    }

    override func magnify(with event: NSEvent) {
        zoom = max(1, min(20, zoom * (1 + event.magnification)))
        updateLayerGeometry()
        notify()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            zoom > 1.01 ? fitToView() : setActualSize()
            return
        }
        dragging = true
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        pan(dx: point.x - lastDragPoint.x, dy: point.y - lastDragPoint.y)
        lastDragPoint = point
        updateLayerGeometry()
        notify()
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    private func pan(dx: CGFloat, dy: CGFloat) {
        guard let image else { return }
        let rendered = renderedSize(for: image)
        guard rendered.width > 0, rendered.height > 0 else { return }
        normalizedCenter.x -= dx / rendered.width
        normalizedCenter.y -= dy / rendered.height
        clampCenter(rendered: rendered)
    }

    private func updateLayerGeometry() {
        guard let image, bounds.width > 0, bounds.height > 0 else {
            imageLayer.frame = bounds
            return
        }
        let rendered = renderedSize(for: image)
        clampCenter(rendered: rendered)
        let centerX = bounds.midX + (0.5 - normalizedCenter.x) * rendered.width
        let centerY = bounds.midY + (0.5 - normalizedCenter.y) * rendered.height
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
        clampCenter(rendered: rendered)
    }

    private func clampCenter(rendered: CGSize) {
        let xMargin = min(0.5, bounds.width / max(rendered.width, 1) / 2)
        let yMargin = min(0.5, bounds.height / max(rendered.height, 1) / 2)
        normalizedCenter.x = max(xMargin, min(1 - xMargin, normalizedCenter.x))
        normalizedCenter.y = max(yMargin, min(1 - yMargin, normalizedCenter.y))
    }

    private func notify() {
        onViewportChange?(InspectViewportState(zoomRelativeToFit: zoom, normalizedCenter: normalizedCenter))
    }
}

final class ImageRevealView: NSView {
    let viewport = InspectImageViewport()
    private let overlayViewport = InspectImageViewport()
    private let maskLayer = CALayer()
    private let divider = NSView()
    private var fraction: CGFloat = 0.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(viewport)
        addSubview(overlayViewport)
        overlayViewport.isInteractionEnabled = false
        viewport.onViewportChange = { [weak overlayViewport] state in
            overlayViewport?.apply(state: state, notify: false)
        }
        overlayViewport.wantsLayer = true
        overlayViewport.layer?.mask = maskLayer
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.cgColor
        addSubview(divider)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    func setImages(a: NSImage?, b: NSImage?) {
        viewport.image = a
        overlayViewport.image = b
    }

    override func layout() {
        super.layout()
        viewport.frame = bounds
        overlayViewport.frame = bounds
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
    var onSelect: ((Int) -> Void)?
    var onCompare: ((Int) -> Void)?
    private var itemViews: [ImageFilmstripItem] = []
    private let scrollView = NSScrollView()
    private let documentView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor(white: 0.05, alpha: 0.88).cgColor
        layer?.borderColor = PanelStyle.hairline.cgColor
        layer?.borderWidth = 1
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue < 0.05 ? nil : super.hitTest(point)
    }

    func configure(infos: [MediaInfo], images: [NSImage?], selectedIndex: Int,
                   compareIndices: (Int, Int)?) {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        let count = infos.count
        let gap: CGFloat = 8
        let width: CGFloat = 76
        let documentWidth = max(bounds.width, 24 + CGFloat(count) * width + CGFloat(max(0, count - 1)) * gap)
        documentView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: 78)
        var x: CGFloat = 12
        for index in 0..<count {
            let item = ImageFilmstripItem(frame: NSRect(x: x, y: 9, width: width, height: 68))
            item.configure(image: images[safe: index] ?? nil, title: infos[index].filename,
                           selected: index == selectedIndex,
                           compared: compareIndices.map { $0.0 == index || $0.1 == index } ?? false)
            item.onClick = { [weak self] modifiers in
                if modifiers.contains(.option) { self?.onCompare?(index) }
                else { self?.onSelect?(index) }
            }
            documentView.addSubview(item)
            itemViews.append(item)
            x += width + gap
        }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds.insetBy(dx: 2, dy: 2)
        documentView.frame.size.height = max(1, scrollView.contentSize.height)
    }
}

private final class ImageFilmstripItem: NSView {
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        label.font = PanelStyle.caption
        label.textColor = PanelStyle.textSecondary
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(event.modifierFlags) }

    func configure(image: NSImage?, title: String, selected: Bool, compared: Bool) {
        imageView.image = image
        label.stringValue = title
        layer?.borderWidth = selected || compared ? 2 : 0
        layer?.borderColor = (compared ? NSColor.systemOrange : PanelStyle.accent).cgColor
    }

    override func layout() {
        super.layout()
        imageView.frame = NSRect(x: 4, y: 18, width: bounds.width - 8, height: bounds.height - 22)
        label.frame = NSRect(x: 2, y: 2, width: bounds.width - 4, height: 14)
    }
}

final class ImageDifferencePanel: NSView {
    private let scroll = NSScrollView()
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 18, bottom: 20, right: 18)
        scroll.documentView = stack
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        stack.frame = NSRect(x: 0, y: 0, width: max(1, bounds.width), height: max(bounds.height, stack.fittingSize.height))
    }

    func showSingle(info: MediaInfo, metadata: ImageTechnicalMetadata?) {
        setRows(title: "Image information".localized, rows: metadataRows(info, metadata: metadata))
    }

    func showComparison(a: MediaInfo, metadataA: ImageTechnicalMetadata?,
                        b: MediaInfo, metadataB: ImageTechnicalMetadata?) {
        let aRows = Dictionary(uniqueKeysWithValues: metadataRows(a, metadata: metadataA))
        let bRows = Dictionary(uniqueKeysWithValues: metadataRows(b, metadata: metadataB))
        let keys = ["Dimensions", "Aspect ratio", "File size", "Format", "Color space", "Bit depth", "Alpha"]
        let differences = keys.compactMap { key -> (String, String)? in
            let av = aRows[key] ?? "—"
            let bv = bRows[key] ?? "—"
            return av == bv ? nil : (key, "A  \(av)\nB  \(bv)")
        }
        setRows(title: String(format: "%d differences".localized, differences.count), rows: differences)
    }

    private func setRows(title: String, rows: [(String, String)]) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let heading = NSTextField(labelWithString: title)
        heading.font = PanelStyle.title
        heading.textColor = PanelStyle.textPrimary
        stack.addArrangedSubview(heading)
        for (key, value) in rows {
            let label = NSTextField(wrappingLabelWithString: "\(key)\n\(value)")
            label.font = PanelStyle.body
            label.textColor = PanelStyle.textSecondary
            label.maximumNumberOfLines = 3
            label.preferredMaxLayoutWidth = max(100, bounds.width - 36)
            stack.addArrangedSubview(label)
        }
        needsLayout = true
    }

    private func metadataRows(_ info: MediaInfo, metadata: ImageTechnicalMetadata?) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let size = info.dimensions, size.height > 0 {
            rows.append(("Dimensions", "\(Int(size.width)) × \(Int(size.height))"))
            rows.append(("Aspect ratio", String(format: "%.3f", size.width / size.height)))
        }
        if let bytes = info.fileSize {
            rows.append(("File size", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
        }
        rows.append(("Format", info.formatName.isEmpty ? "—" : info.formatName))
        if let color = metadata?.colorSpace { rows.append(("Color space", color)) }
        if let depth = metadata?.bitDepth { rows.append(("Bit depth", "\(depth)-bit")) }
        if let alpha = metadata?.hasAlpha { rows.append(("Alpha", alpha ? "Yes" : "No")) }
        return rows
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
