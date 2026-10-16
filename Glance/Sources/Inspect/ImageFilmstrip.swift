import AppKit

final class ImageFilmstripView: NSView {
    var onSelect: ((Int) -> Void)?
    var onCompare: ((Int) -> Void)?
    var onVisibleIndicesChanged: (([Int]) -> Void)?
    /// The trailing "+" tile — an explicit alternative to drag-and-drop.
    var onAdd: (() -> Void)?
    private var itemViews: [Int: ImageFilmstripItem] = [:]
    private var visibleIndices: [Int] = []
    private var infos: [MediaInfo] = []
    private var images: [NSImage?] = []
    private var generatedResultPaths = Set<String>()
    private var selectedIndex = 0
    private var compareIndices: (Int, Int)?
    /// Generated type icons for non-image items (mixed sessions), by index.
    private var iconCache: [Int: NSImage] = [:]
    private var tileSize: CGFloat = 96
    private var itemGap: CGFloat = 10
    private var scrollOffset: CGFloat = 0
    private var pendingRevealIndex: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        layoutItems()
        if visibleRange != visibleIndices {
            // Never mutate the view hierarchy during AppKit's layout pass.
            DispatchQueue.main.async { [weak self] in self?.refreshVisibleItems() }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue < 0.05 ? nil : super.hitTest(point)
    }

    func setGeometry(tileSize: CGFloat, gap: CGFloat) {
        guard self.tileSize != tileSize || itemGap != gap else { return }
        self.tileSize = tileSize
        itemGap = gap
        refreshVisibleItems()
    }

    override func scrollWheel(with event: NSEvent) {
        guard maxScrollOffset > 0 else { return }
        let delta = abs(event.scrollingDeltaX) > 0.01 ? event.scrollingDeltaX : event.scrollingDeltaY
        let step = event.hasPreciseScrollingDeltas ? delta : delta * 20
        scrollOffset = min(max(0, scrollOffset - step), maxScrollOffset)
        refreshVisibleItems()
    }

    func configure(infos: [MediaInfo], images: [NSImage?], selectedIndex: Int,
                   compareIndices: (Int, Int)?, generatedResultPaths: Set<String>) {
        let structureChanged = self.infos.count != infos.count
            || self.infos.first?.url != infos.first?.url
            || self.infos.last?.url != infos.last?.url
        let previousURLs: Set<URL> = structureChanged
            ? Set(self.infos.map { $0.url.standardizedFileURL }) : []
        let previousSelection = self.selectedIndex
        let firstLoad = self.infos.isEmpty
        let sessionChanged = self.infos.first?.url != infos.first?.url
        if sessionChanged {
            scrollOffset = 0
            itemViews.values.forEach { $0.removeFromSuperview() }
            itemViews.removeAll()
            visibleIndices.removeAll()
        }
        self.infos = infos
        self.images = images
        self.generatedResultPaths = generatedResultPaths
        self.selectedIndex = selectedIndex
        self.compareIndices = compareIndices
        if structureChanged { iconCache.removeAll() }
        refreshVisibleItems()
        if structureChanged, !sessionChanged, let resultIndex = infos.indices.first(where: {
            !previousURLs.contains(infos[$0].url.standardizedFileURL) &&
            (isGeneratedResult(infos[$0].url) ||
             WidgetTaskManager.shared.completedRecord(for: infos[$0].url) != nil)
        }) {
            revealItem(at: resultIndex)
        } else if firstLoad || sessionChanged || previousSelection != selectedIndex {
            revealItem(at: selectedIndex)
        }
    }

    private func revealItem(at index: Int) {
        guard infos.indices.contains(index) else { return }
        guard bounds.width > 0 else {
            pendingRevealIndex = index
            return
        }
        adjustOffsetToReveal(index)
        refreshVisibleItems()
    }

    /// Screen-space frame of a tile, for anchoring popovers to it.
    func screenFrame(ofItemAt index: Int) -> NSRect? {
        guard let item = itemViews[index], let window else { return nil }
        return window.convertToScreen(item.convert(item.bounds, to: nil))
    }

    private func isGeneratedResult(_ url: URL) -> Bool {
        url.isFileURL && generatedResultPaths.contains(url.standardizedFileURL.path)
    }

    private func adjustOffsetToReveal(_ index: Int) {
        let itemStart = CGFloat(index) * (tileSize + itemGap)
        let itemEnd = itemStart + tileSize
        if itemStart < scrollOffset { scrollOffset = itemStart }
        else if itemEnd > scrollOffset + bounds.width { scrollOffset = itemEnd - bounds.width }
    }

    private func thumbnail(for index: Int) -> NSImage? {
        if let image = images[safe: index] ?? nil { return image }
        guard infos.indices.contains(index), infos[index].kind != .image else { return nil }
        if let cached = iconCache[index] { return cached }
        let icon = FileTypeIcon.makeImage(for: infos[index], size: CGSize(width: 96, height: 96))
        iconCache[index] = icon
        return icon
    }

    private var contentWidth: CGFloat {
        CGFloat(infos.count) * tileSize + CGFloat(max(0, infos.count - 1)) * itemGap
    }

    private var maxScrollOffset: CGFloat { max(0, contentWidth - bounds.width) }
    var visibleItemIndices: [Int] { visibleRange }

    private var visibleRange: [Int] {
        guard !infos.isEmpty, bounds.width > 0 else { return [] }
        let pitch = max(1, tileSize + itemGap)
        let offset = min(max(0, scrollOffset), maxScrollOffset)
        let first = max(0, Int(offset / pitch) - 1)
        let last = min(infos.count - 1, Int((offset + bounds.width) / pitch) + 1)
        return Array(first...last)
    }

    /// Position the existing tiles without touching the view hierarchy.
    private func layoutItems() {
        if let index = pendingRevealIndex, bounds.width > 0 {
            pendingRevealIndex = nil
            adjustOffsetToReveal(index)
        }
        scrollOffset = min(scrollOffset, maxScrollOffset)
        for (index, item) in itemViews {
            item.frame = NSRect(x: CGFloat(index) * (tileSize + itemGap) - scrollOffset,
                                y: 0, width: tileSize, height: tileSize)
        }
    }

    private func refreshVisibleItems() {
        scrollOffset = min(max(0, scrollOffset), maxScrollOffset)
        let indices = visibleRange
        let wanted = Set(indices)
        for index in itemViews.keys.filter({ !wanted.contains($0) }) {
            itemViews.removeValue(forKey: index)?.removeFromSuperview()
        }
        let selectedResultTask: WidgetTaskRecord? = infos.indices.contains(selectedIndex)
            ? WidgetTaskManager.shared.completedRecord(for: infos[selectedIndex].url)
            : nil
        let ossResultTask = selectedResultTask?.widgetID == ossImageHostingWidgetID
            ? selectedResultTask : nil
        for index in indices {
            let item: ImageFilmstripItem
            if let existing = itemViews[index] { item = existing }
            else {
                item = ImageFilmstripItem(frame: .zero)
                addSubview(item)
                itemViews[index] = item
            }
            let isCompared = compareIndices.map { $0.0 == index || $0.1 == index } ?? false
            // In compare mode the border means pair membership only. The
            // browse/focus selection is intentionally ignored so a stale
            // focusedIndex can never create a third highlighted thumbnail.
            let isSelected = compareIndices == nil && index == selectedIndex
            let activeTask = WidgetTaskManager.shared.activeRecords(for: infos[index].url).first
            let task = activeTask ?? WidgetTaskManager.shared.latestRecord(for: infos[index].url)
            let resultTask = WidgetTaskManager.shared.completedRecord(for: infos[index].url)
            let caption: String?
            if ossResultTask?.outputURLString != nil && index == selectedIndex {
                caption = "RESULT · OSS"
            } else {
                caption = nil
            }
            item.configure(image: thumbnail(for: index), title: infos[index].filename,
                           selected: isSelected,
                           compared: isCompared,
                           taskPhase: (task ?? resultTask)?.phase,
                           taskProgress: task?.progress ?? 0,
                           isResult: resultTask != nil || isGeneratedResult(infos[index].url),
                           ossCaption: caption,
                           activeTaskCount: WidgetTaskManager.shared.activeRecords(for: infos[index].url).count)
            item.onClick = { [weak self] modifiers in
                if modifiers.contains(.option) { self?.onCompare?(index) }
                else { self?.onSelect?(index) }
            }
        }
        layoutItems()
        if visibleIndices != indices {
            visibleIndices = indices
            onVisibleIndicesChanged?(indices)
        }
    }
}

final class NonHitTestingImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        let sourceAspect = image.size.width / image.size.height
        let targetAspect = bounds.width / bounds.height
        var source = CGRect(origin: .zero, size: image.size)
        if sourceAspect > targetAspect {
            source.size.width = image.size.height * targetAspect
            source.origin.x = (image.size.width - source.width) / 2
        } else {
            source.size.height = image.size.width / targetAspect
            source.origin.y = (image.size.height - source.height) / 2
        }
        NSGraphicsContext.saveGraphicsState()
        let radius = min(bounds.width, bounds.height) * 6 / 96
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: bounds, from: source, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class ImageFilmstripItem: NSView {
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    private let imageView = NonHitTestingImageView()
    private let taskBadge = CALayer()
    private let tagBackground = InspectNonHitTestingView()
    private let tagLabel = PanelCenteredTextView()
    private let ossCaptionBackground = InspectNonHitTestingView()
    private let ossCaptionLabel = PanelCenteredTextView()
    private let plusLabel = CATextLayer()
    private var previewInset: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        layer?.backgroundColor = PanelStyle.inspectChrome.cgColor
        addSubview(imageView)
        taskBadge.cornerRadius = 3.5
        taskBadge.isHidden = true
        layer?.addSublayer(taskBadge)
        // Keep the corner badge in the view hierarchy above the thumbnail
        // image. Parent CALayer overlays can be occluded by AppKit subviews.
        tagBackground.wantsLayer = true
        tagBackground.layer?.backgroundColor = PanelStyle.success.cgColor
        tagBackground.layer?.cornerRadius = 4
        tagBackground.layer?.masksToBounds = true
        tagBackground.isHidden = true
        addSubview(tagBackground, positioned: .above, relativeTo: imageView)
        tagLabel.string = "NEW"
        tagLabel.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        tagLabel.textColor = PanelStyle.accentInk
        tagBackground.addSubview(tagLabel)
        ossCaptionBackground.wantsLayer = true
        ossCaptionBackground.layer?.cornerRadius = 5
        ossCaptionBackground.layer?.masksToBounds = true
        ossCaptionBackground.isHidden = true
        addSubview(ossCaptionBackground, positioned: .above, relativeTo: imageView)
        ossCaptionLabel.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        ossCaptionBackground.addSubview(ossCaptionLabel)
        // "+" glyph for the add tile.
        plusLabel.font = NSFont.systemFont(ofSize: 19, weight: .regular)
        plusLabel.fontSize = 19
        plusLabel.foregroundColor = PanelStyle.textTertiary.cgColor
        plusLabel.alignmentMode = .center
        plusLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        plusLabel.isHidden = true
        layer?.addSublayer(plusLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(event.modifierFlags) }
    override func accessibilityPerformPress() -> Bool {
        onClick?([])
        return true
    }

    /// The trailing "+" tile (spec `.thumb.add`).
    func configureAddTile() {
        imageView.image = nil
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.hairline.cgColor
        taskBadge.isHidden = true
        tagBackground.isHidden = true
        ossCaptionBackground.isHidden = true
        plusLabel.isHidden = false
        plusLabel.string = "+"
        toolTip = "Add".localized
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Add".localized)
    }

    func configure(image: NSImage?, title: String, selected: Bool, compared: Bool,
                   taskPhase: WidgetTaskPhase?, taskProgress: Int = 0, isResult: Bool = false,
                   ossCaption: String? = nil,
                   activeTaskCount: Int) {
        imageView.image = image
        toolTip = title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        plusLabel.isHidden = true
        let processing = taskPhase?.isActive == true
        let failed = taskPhase?.isFailure == true
        let completedResult = isResult
        let emphasized = selected || compared || processing
        layer?.borderWidth = emphasized ? 2 : 1
        previewInset = emphasized ? 2 : 3
        layer?.borderColor = (failed ? PanelStyle.failure : (emphasized ? PanelStyle.warmCue : PanelStyle.inspectLine)).cgColor
        taskBadge.isHidden = !failed
        taskBadge.backgroundColor = PanelStyle.failure.cgColor
        // The same corner badge shows progress while a task runs on this image
        // and NEW once a result arrived — one overlay, no extra geometry.
        let showsProgress = processing && taskProgress > 0 && !completedResult
        tagBackground.isHidden = !(completedResult || showsProgress)
        if showsProgress { tagLabel.string = "\(min(99, taskProgress))%" }
        else if completedResult { tagLabel.string = "NEW" }
        ossCaptionBackground.isHidden = ossCaption == nil
        if let ossCaption {
            let isOSSResult = ossCaption == "RESULT · OSS"
            ossCaptionBackground.layer?.backgroundColor = NSColor(
                srgbRed: isOSSResult ? 48 / 255 : 16 / 255,
                green: isOSSResult ? 35 / 255 : 17 / 255,
                blue: isOSSResult ? 31 / 255 : 21 / 255,
                alpha: 1
            ).cgColor
            ossCaptionLabel.textColor = isOSSResult ? PanelStyle.accent : PanelStyle.textPrimary
            ossCaptionLabel.string = ossCaption
        }
        if processing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if layer?.animation(forKey: "widgetBreathing") == nil {
                let animation = CABasicAnimation(keyPath: "borderColor")
                animation.fromValue = PanelStyle.warmCue.withAlphaComponent(0.30).cgColor
                animation.toValue = PanelStyle.warmCue.cgColor
                animation.duration = 0.75
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer?.add(animation, forKey: "widgetBreathing")
            }
        } else {
            layer?.removeAnimation(forKey: "widgetBreathing")
        }
        if processing { setAccessibilityLabel("\(title), \(activeTaskCount) Widget task running") }
        else if failed { setAccessibilityLabel("\(title), Widget task failed") }
        else if completedResult { setAccessibilityLabel("\(title), Widget result just completed") }
    }

    override func layout() {
        super.layout()
        let scale = min(bounds.width, bounds.height) / 96
        layer?.cornerRadius = 9 * scale
        tagBackground.layer?.cornerRadius = 4 * scale
        // Figma 176:90 / 176:92: 48×22 at the top-right of a 96×96 tile,
        // with a centered 48×12 Inter Semibold text frame. At small window
        // sizes the font stops shrinking at 9pt, so keep its badge and text
        // frame large enough to show all of NEW without resizing the tile.
        tagLabel.font = PanelStyle.inspectFont(ofSize: max(9, 10 * scale), weight: .semibold)
        taskBadge.cornerRadius = 3.5 * scale
        imageView.frame = bounds.insetBy(dx: previewInset * scale, dy: previewInset * scale)
        taskBadge.frame = NSRect(x: bounds.maxX - 9 * scale, y: bounds.maxY - 9 * scale,
                                 width: 7 * scale, height: 7 * scale)
        let tagSize = CGSize(width: max(28, 48 * scale), height: max(14, 22 * scale))
        tagBackground.frame = CGRect(x: bounds.maxX - tagSize.width,
                                     y: bounds.maxY - tagSize.height,
                                     width: tagSize.width, height: tagSize.height)
        let tagTextHeight = max(8, 12 * scale)
        tagLabel.frame = NSRect(x: 0, y: (tagSize.height - tagTextHeight) / 2,
                                width: tagSize.width, height: tagTextHeight)
        ossCaptionBackground.layer?.cornerRadius = 5 * scale
        ossCaptionBackground.frame = NSRect(x: 4 * scale, y: 4 * scale,
                                             width: bounds.width - 8 * scale, height: 23 * scale)
        ossCaptionLabel.font = PanelStyle.inspectFont(ofSize: max(8, 10 * scale), weight: .semibold)
        ossCaptionLabel.frame = NSRect(x: 0, y: 5 * scale,
                                       width: ossCaptionBackground.bounds.width,
                                       height: 12 * scale)
        plusLabel.frame = CGRect(x: 0, y: bounds.height / 2 - 14, width: bounds.width, height: 28)
    }
}

final class FigmaAddButton: NSControl {
    private let plusLabel = NSTextField(labelWithString: "+")
    private let addLabel = NSTextField(labelWithString: "Add")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectToolbar)
        layer?.borderColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
        layer?.borderWidth = 1
        layer?.cornerRadius = 9

        plusLabel.font = PanelStyle.inspectFont(ofSize: 34)
        plusLabel.textColor = PanelStyle.textPrimary
        plusLabel.alignment = .center
        addLabel.font = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
        addLabel.textColor = PanelStyle.textSecondary
        addLabel.alignment = .center
        addSubview(plusLabel)
        addSubview(addLabel)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Add".localized)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let scale = min(bounds.width, bounds.height) / 112
        layer?.cornerRadius = 9 * scale
        layer?.borderWidth = max(1, scale)
        plusLabel.font = PanelStyle.inspectFont(ofSize: 34 * scale)
        addLabel.font = PanelStyle.inspectFont(ofSize: 12 * scale, weight: .medium)
        plusLabel.frame = NSRect(x: 0, y: bounds.height - 61 * scale,
                                 width: bounds.width, height: 41 * scale)
        addLabel.frame = NSRect(x: 0, y: bounds.height - 85 * scale,
                                width: bounds.width, height: 15 * scale)
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        sendAction(action, to: target)
    }
}
