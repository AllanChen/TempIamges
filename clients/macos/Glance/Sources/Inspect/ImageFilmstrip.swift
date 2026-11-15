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
    private var tileSize: CGFloat = InspectLayout.thumbSize
    private var itemGap: CGFloat = InspectLayout.thumbGap
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
            // Tiles sit on the bottom edge; the headroom above them carries
            // the compare captions and the corner marks.
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
            var compareSlot: String?
            if let pair = compareIndices {
                if pair.0 == index { compareSlot = "A" } else if pair.1 == index { compareSlot = "B" }
            }
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
                           compareSlot: compareSlot,
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
        let radius = min(bounds.width, bounds.height) * PanelStyle.Radius.thumb / 40
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: bounds, from: source, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// One Figma `thumb`: a 48 pt tile with a 40 pt image inset 4 pt. Every
/// state keeps that geometry; selection is a 1 pt rule and task, result and
/// compare states are overlays in the corner or the headroom above the tile.
final class ImageFilmstripItem: NSView {
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    private let imageView = NonHitTestingImageView()
    private let ring = InspectRunningRing()
    private let newMark = InspectNonHitTestingView()
    private let failureMark = InspectNonHitTestingView()
    private let failureGlyph = PanelCenteredTextView()
    private let slotCaption = PanelCenteredTextView()
    private let ossCaptionBackground = InspectNonHitTestingView()
    private let ossCaptionLabel = PanelCenteredTextView()
    private let plusLabel = PanelCenteredTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Marks extend into the strip's headroom; the image clips itself.
        layer?.masksToBounds = false
        layer?.cornerRadius = PanelStyle.Radius.control
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(imageView)
        ossCaptionBackground.wantsLayer = true
        ossCaptionBackground.layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.ink0.withAlphaComponent(0.85))
        ossCaptionBackground.layer?.cornerRadius = 2
        ossCaptionBackground.isHidden = true
        ossCaptionLabel.font = PanelStyle.monoFont(ofSize: 8)
        ossCaptionLabel.textColor = InspectInk.text1
        ossCaptionBackground.addSubview(ossCaptionLabel)
        addSubview(ossCaptionBackground)
        ring.isHidden = true
        addSubview(ring)
        newMark.wantsLayer = true
        newMark.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.failure)
        newMark.isHidden = true
        addSubview(newMark)
        failureMark.wantsLayer = true
        failureMark.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.failure)
        failureMark.isHidden = true
        failureGlyph.string = "!"
        failureGlyph.font = PanelStyle.inspectFont(ofSize: 9, weight: .semibold)
        failureGlyph.textColor = PanelStyle.accentInk
        failureMark.addSubview(failureGlyph)
        addSubview(failureMark)
        slotCaption.font = PanelStyle.monoFont(ofSize: 10)
        slotCaption.textColor = InspectInk.text2
        slotCaption.isHidden = true
        addSubview(slotCaption)
        plusLabel.string = "+"
        plusLabel.font = PanelStyle.inspectFont(ofSize: 17)
        plusLabel.textColor = InspectInk.text3
        plusLabel.isHidden = true
        addSubview(plusLabel)
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
        ring.isHidden = true
        newMark.isHidden = true
        failureMark.isHidden = true
        slotCaption.isHidden = true
        ossCaptionBackground.isHidden = true
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
        plusLabel.isHidden = false
        toolTip = "Add".localized
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Add".localized)
    }

    func configure(image: NSImage?, title: String, selected: Bool, compared: Bool,
                   compareSlot: String? = nil,
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
        // Figma: unselected thumbnails rest at 55 %; selected and paired
        // thumbnails are full strength with a 1 pt rule (B in text/2).
        let emphasized = selected || compared
        imageView.alphaValue = emphasized ? 1 : 0.55
        let rule: NSColor? = failed ? PanelStyle.failure
            : compareSlot == "B" ? InspectInk.text2
            : emphasized ? InspectInk.text1 : nil
        layer?.borderWidth = rule == nil ? 0 : 1
        layer?.borderColor = rule.map { PanelStyle.resolvedCG($0) }
        ring.isHidden = !processing
        ring.progress = processing && taskProgress > 0 ? taskProgress : nil
        failureMark.isHidden = !failed || processing
        newMark.isHidden = !isResult || processing || failed
        slotCaption.string = compareSlot ?? ""
        slotCaption.isHidden = compareSlot == nil
        ossCaptionBackground.isHidden = ossCaption == nil
        if let ossCaption {
            // The tile is too small for the full caption; it stays the
            // accessibility description.
            ossCaptionLabel.string = "OSS"
            ossCaptionBackground.setAccessibilityLabel(ossCaption)
        }
        if processing {
            let progress = taskProgress > 0 ? ", \(min(99, taskProgress))%" : ""
            setAccessibilityLabel("\(title), \(activeTaskCount) Widget task running\(progress)")
        }
        else if failed { setAccessibilityLabel("\(title), Widget task failed") }
        else if isResult { setAccessibilityLabel("\(title), Widget result just completed") }
        needsLayout = true
    }

    /// Figma thumb (top-origin): image 4/4/40/40, running ring 20 pt centred on
    /// the image, failure mark 14 pt at (34, −2), NEW mark 5 pt at (40, −1),
    /// compare caption at (20, −17).
    override func layout() {
        super.layout()
        let s = min(bounds.width, bounds.height) / InspectLayout.thumbSize
        let h = bounds.height
        func top(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hh: CGFloat) -> NSRect {
            NSRect(x: x * s, y: h - (y + hh) * s, width: w * s, height: hh * s)
        }
        layer?.cornerRadius = PanelStyle.Radius.control * s
        imageView.frame = top(4, 4, 40, 40)
        ring.frame = top(14, 14, 20, 20)
        failureMark.frame = top(34, -2, 14, 14)
        failureMark.layer?.cornerRadius = 7 * s
        failureGlyph.frame = failureMark.bounds
        newMark.frame = top(40, -1, 5, 5)
        newMark.layer?.cornerRadius = 2.5 * s
        slotCaption.frame = top(0, -17, 48, 12)
        ossCaptionBackground.frame = top(6, 32, 20, 10)
        ossCaptionLabel.frame = ossCaptionBackground.bounds
        plusLabel.frame = bounds
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
