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

/// Figma Shizuka `thumb`, as in Image Inspect: the image inset 4/48 of the
/// tile at 55 % until selected, a 1 pt text/1 rule when selected, and task /
/// result states as small marks inside the top-right corner.
final class VideoFilmstripItem: NSView {
    var onClick: (() -> Void)?
    private let imageView = VideoThumbnailImageView()
    private let ring = InspectRunningRing()
    private let newMark = VideoNonHitTestingView()
    private let failureMark = VideoNonHitTestingView()
    private var emphasized = false
    private var failed = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PanelStyle.Radius.control
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        imageView.contentTintColor = PanelStyle.textTertiary
        addSubview(imageView)
        ring.isHidden = true
        addSubview(ring)
        for (mark, hidden) in [(newMark, true), (failureMark, true)] {
            mark.wantsLayer = true
            mark.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.failure)
            mark.isHidden = hidden
            addSubview(mark)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(selected: Bool, compared: Bool) {
        emphasized = selected || compared
        updateRule()
        imageView.alphaValue = emphasized ? 1 : 0.55
        needsLayout = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityValue(selected || compared ? 1 : 0)
    }
    private func updateRule() {
        let rule: NSColor? = failed ? PanelStyle.failure : emphasized ? InspectInk.text1 : nil
        layer?.borderWidth = rule == nil ? 0 : 1
        layer?.borderColor = rule.map { PanelStyle.resolvedCG($0) }
    }
    func setWidgetTaskState(phase: WidgetTaskPhase?, progress: Int = 0, isResult: Bool,
                            activeTaskCount: Int, title: String) {
        let processing = phase?.isActive == true
        failed = phase?.isFailure == true
        updateRule()
        ring.isHidden = !processing
        ring.progress = processing && progress > 0 ? progress : nil
        newMark.isHidden = !isResult || processing || failed
        failureMark.isHidden = !failed || processing
        if processing {
            let percent = progress > 0 ? ", \(min(99, progress))%" : ""
            setAccessibilityLabel("\(title), \(activeTaskCount) Widget task running\(percent)")
        }
        else if failed { setAccessibilityLabel("\(title), Widget task failed") }
        else if isResult { setAccessibilityLabel("\(title), Widget result just completed") }
        else { setAccessibilityLabel(title) }
        needsLayout = true
    }
    func setThumbnail(_ image: NSImage) { imageView.image = image }
    func loadThumbnail(from url: URL) { DispatchQueue.global(qos: .userInitiated).async { [weak self] in let generator = AVAssetImageGenerator(asset: AVAsset(url: url)); generator.appliesPreferredTrackTransform = true; guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return }; DispatchQueue.main.async { self?.imageView.image = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height))) } } }
    /// Thumb geometry in 48 pt units; the marks stay inside the tile because
    /// the video strip clips to its row.
    override func layout() {
        super.layout()
        let s = min(bounds.width, bounds.height) / InspectLayout.thumbSize
        func top(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x * s, y: bounds.height - (y + h) * s, width: w * s, height: h * s)
        }
        layer?.cornerRadius = PanelStyle.Radius.control * s
        imageView.frame = top(4, 4, 40, 40)
        ring.frame = top(14, 14, 20, 20)
        failureMark.frame = top(35, 5, 8, 8)
        failureMark.layer?.cornerRadius = 4 * s
        newMark.frame = top(38, 5, 5, 5)
        newMark.layer?.cornerRadius = 2.5 * s
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
        let radius = min(bounds.width, bounds.height) * PanelStyle.Radius.thumb / 40
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: bounds, from: source, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}
