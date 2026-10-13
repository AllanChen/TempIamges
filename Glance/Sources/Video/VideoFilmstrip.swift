import AppKit
import AVFoundation
import AVKit
import Network
import WebKit

final class VideoFilmstripView: NSView {
    var onSelect: ((Int) -> Void)?
    private let scrollView = VideoFilmstripScrollView()
    private let document = NSView()
    private var items: [VideoFilmstripItem] = []
    private var itemURLs: [URL] = []
    private var selectedIndex = 0
    private var revealSelection = false
    private var previousSize = NSSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = document
        addSubview(scrollView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func scrollWheel(with event: NSEvent) { scrollView.scrollWheel(with: event) }

    func configure(infos: [MediaInfo], selectedIndex: Int, compareIndices: (Int, Int)?,
                   generatedResultPaths: Set<String>) {
        let previousSelection = self.selectedIndex
        let previousURLs = itemURLs
        self.selectedIndex = selectedIndex
        var reusableItems = Array(zip(itemURLs, items))
        items.forEach { $0.removeFromSuperview() }
        items = infos.indices.map { index in
            let previousIndex = reusableItems.firstIndex { $0.0 == infos[index].url }
            let item = previousIndex.map { reusableItems.remove(at: $0).1 } ?? VideoFilmstripItem(frame: .zero)
            item.configure(selected: compareIndices == nil && index == selectedIndex,
                           compared: compareIndices.map { $0.0 == index || $0.1 == index } ?? false)
            item.toolTip = infos[index].filename
            item.setAccessibilityLabel(infos[index].filename)
            // Retain decoded thumbnails (including WebM player captures) when
            // switching the focused video or appending another video.
            if previousIndex == nil { item.loadThumbnail(from: infos[index].url) }
            item.onClick = { [weak self] in self?.onSelect?(index) }
            document.addSubview(item)
            return item
        }
        itemURLs = infos.map(\.url)
        updateTaskStates(infos: infos, generatedResultPaths: generatedResultPaths)
        revealSelection = previousSelection != selectedIndex || previousURLs != itemURLs
        needsLayout = true
    }

    func updateTaskStates(infos: [MediaInfo], generatedResultPaths: Set<String>) {
        for (index, item) in items.enumerated() {
            guard let info = infos[safe: index] else { continue }
            let active = WidgetTaskManager.shared.activeRecords(for: info.url)
            let task = active.first ?? WidgetTaskManager.shared.latestRecord(for: info.url)
            let result = WidgetTaskManager.shared.completedRecord(for: info.url) != nil ||
                generatedResultPaths.contains(info.url.standardizedFileURL.path)
            item.setWidgetTaskState(phase: task?.phase, progress: active.first?.progress ?? 0,
                                    isResult: result, activeTaskCount: active.count, title: info.filename)
        }
    }

    func setThumbnail(_ image: NSImage, at index: Int) {
        items[safe: index]?.setThumbnail(image)
    }

    /// Screen-space frame of a tile, for anchoring popovers to it.
    func screenFrame(ofItemAt index: Int) -> NSRect? {
        guard let item = items[safe: index], let window else { return nil }
        return window.convertToScreen(item.convert(item.bounds, to: nil))
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let tile = bounds.height
        let gap = VideoInspectChromeLayout.filmstripBaseGap * tile / VideoInspectChromeLayout.filmstripBaseSize
        let contentWidth = CGFloat(items.count) * tile + CGFloat(max(0, items.count - 1)) * gap
        document.frame = NSRect(x: 0, y: 0, width: max(bounds.width, contentWidth), height: tile)
        let left = max(0, (bounds.width - contentWidth) / 2)
        for (index, item) in items.enumerated() {
            item.frame = NSRect(x: left + CGFloat(index) * (tile + gap), y: 0, width: tile, height: tile)
        }
        if revealSelection || previousSize != bounds.size {
            if let selected = items[safe: selectedIndex] { document.scrollToVisible(selected.frame) }
            revealSelection = false
            previousSize = bounds.size
        }
    }
}

/// Both a trackpad's horizontal gesture and an ordinary mouse wheel can reach
/// every video without squeezing thumbnails as more videos are added.
final class VideoFilmstripScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard let documentView else { return }
        let delta = abs(event.scrollingDeltaX) > 0.01 ? event.scrollingDeltaX : event.scrollingDeltaY
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 20
        let maxX = max(0, documentView.bounds.width - contentView.bounds.width)
        let x = min(maxX, max(0, contentView.bounds.minX - delta * multiplier))
        contentView.scroll(to: NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
}

final class VideoFilmstripItem: NSView {
    var onClick: (() -> Void)?
    private let imageView = VideoThumbnailImageView()
    private let newBadge = VideoNonHitTestingView()
    private let newLabel = PanelCenteredTextView()
    private var previewInset: CGFloat = 3
    private var emphasized = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        layer?.backgroundColor = PanelStyle.inspectToolbar.cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        imageView.contentTintColor = PanelStyle.textTertiary
        addSubview(imageView)
        newBadge.wantsLayer = true
        newBadge.layer?.backgroundColor = PanelStyle.success.cgColor
        newBadge.layer?.cornerRadius = 4
        newBadge.layer?.masksToBounds = true
        newBadge.isHidden = true
        newLabel.string = "NEW"
        newLabel.font = PanelStyle.inspectFont(ofSize: 10, weight: .semibold)
        newLabel.textColor = PanelStyle.accentInk
        newBadge.addSubview(newLabel)
        addSubview(newBadge, positioned: .above, relativeTo: imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    // Selection is communicated by the warm-cue border only (mirrors the image
    // filmstrip); the frosted background stays the same either way.
    func configure(selected: Bool, compared: Bool) {
        emphasized = selected || compared
        layer?.borderWidth = emphasized ? 2 : 1
        layer?.borderColor = (emphasized ? PanelStyle.warmCue : PanelStyle.inspectLine).cgColor
        previewInset = emphasized ? 2 : 3
        needsLayout = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityValue(selected || compared ? 1 : 0)
    }
    func setWidgetTaskState(phase: WidgetTaskPhase?, progress: Int = 0, isResult: Bool,
                            activeTaskCount: Int, title: String) {
        let processing = phase?.isActive == true
        let failed = phase?.isFailure == true
        let showsProgress = processing && progress > 0 && !isResult
        layer?.borderWidth = emphasized || processing ? 2 : 1
        previewInset = emphasized || processing ? 2 : 3
        layer?.borderColor = (failed ? PanelStyle.failure :
            (emphasized || processing ? PanelStyle.warmCue : PanelStyle.inspectLine)).cgColor
        newBadge.isHidden = !(isResult || showsProgress)
        newLabel.string = showsProgress ? "\(min(99, progress))%" : "NEW"
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
        else if isResult { setAccessibilityLabel("\(title), Widget result just completed") }
        else { setAccessibilityLabel(title) }
        needsLayout = true
    }
    func setThumbnail(_ image: NSImage) { imageView.image = image }
    func loadThumbnail(from url: URL) { DispatchQueue.global(qos: .userInitiated).async { [weak self] in let generator = AVAssetImageGenerator(asset: AVAsset(url: url)); generator.appliesPreferredTrackTransform = true; guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return }; DispatchQueue.main.async { self?.imageView.image = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height))) } } }
    override func layout() {
        super.layout()
        let scale = bounds.height / 96
        layer?.cornerRadius = 9 * scale
        imageView.frame = bounds.insetBy(dx: previewInset * scale, dy: previewInset * scale)
        newBadge.layer?.cornerRadius = 4 * scale
        newLabel.font = PanelStyle.inspectFont(ofSize: max(9, 10 * scale), weight: .semibold)
        let badgeSize = CGSize(width: max(28, 48 * scale), height: max(14, 22 * scale))
        newBadge.frame = NSRect(x: bounds.maxX - badgeSize.width, y: bounds.maxY - badgeSize.height,
                                width: badgeSize.width, height: badgeSize.height)
        let textHeight = max(8, 12 * scale)
        newLabel.frame = NSRect(x: 0, y: (badgeSize.height - textHeight) / 2,
                                width: badgeSize.width, height: textHeight)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

final class VideoNonHitTestingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class VideoThumbnailImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        if image.isTemplate { super.draw(dirtyRect); return }
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
