import AppKit

/// Image Inspect's information panel (Figma `20 · Image Inspect / Info`):
/// the file name in Mincho, its folder in mono, then Image / Color / File
/// sections of key (12 pt text/3) and value (mono 11 pt text/1) rows.
final class FigmaImageInspectorView: NSView {
    /// The panel is a borderless child window, so it carries its own close control.
    var onClose: (() -> Void)?
    private lazy var closeButton: InspectToolbarButton = {
        let button = InspectToolbarButton(symbol: "xmark", tooltip: "Close".localized)
        button.usesShizukaStyle = true
        button.target = self
        button.action = #selector(closeTapped)
        return button
    }()
    private var items: [(index: Int, info: MediaInfo, metadata: ImageTechnicalMetadata?)] = []
    private var title = ""
    private var folder = ""
    private var sections: [(String, [(String, String)])] = []

    private static let padX: CGFloat = 24
    private static let keyFont = PanelStyle.inspectFont(ofSize: 12)
    private static let valueFont = PanelStyle.monoFont(ofSize: 11)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(closeButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Image information".localized)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: bounds.width - 16 - InspectLayout.controlSize, y: 26,
                                   width: InspectLayout.controlSize, height: InspectLayout.controlSize)
    }

    func show(items: [(index: Int, info: MediaInfo, metadata: ImageTechnicalMetadata?)]) {
        self.items = items
        if let first = items.first { display(first) }
    }

    func highlight(index: Int?) {
        guard let index, let item = items.first(where: { $0.index == index }) else { return }
        display(item)
    }

    @objc private func closeTapped() { onClose?() }

    private func display(_ item: (index: Int, info: MediaInfo, metadata: ImageTechnicalMetadata?)) {
        let info = item.info
        let metadata = item.metadata
        let dash = "—"
        let dimensions = info.dimensions.map { "\(Int($0.width)) × \(Int($0.height))" } ?? dash
        let size = info.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? dash
        let created: String = {
            guard info.isLocal,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: info.url.path),
                  let date = attributes[.creationDate] as? Date else { return dash }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }()
        let location = info.isLocal
            ? (info.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            : (info.url.host ?? info.url.absoluteString)
        title = info.filename
        folder = location
        sections = [
            ("Image".localized, [
                ("Dimensions".localized, dimensions),
                ("Aspect ratio".localized, Self.aspectRatio(info.dimensions) ?? dash),
                ("Format".localized, info.formatName.isDisplayableValue ? info.formatName : dash),
                ("File size".localized, size)
            ]),
            ("Color".localized, [
                ("Color space".localized, metadata?.colorSpace?.isDisplayableValue == true ? metadata!.colorSpace! : dash),
                ("Bit depth".localized, metadata?.bitDepth.map { "\($0)-bit" } ?? dash),
                ("Alpha".localized, metadata?.hasAlpha.map { ($0 ? "Yes" : "No").localized } ?? dash)
            ]),
            ("File".localized, [
                ("Created".localized, created),
                ("Path".localized, location)
            ])
        ]
        needsDisplay = true
    }

    /// "4 : 3" for common ratios, otherwise the decimal ratio.
    private static func aspectRatio(_ size: CGSize?) -> String? {
        guard let size, size.width > 0, size.height > 0 else { return nil }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        let divisor = max(1, gcd(w, h))
        let (rw, rh) = (w / divisor, h / divisor)
        if rw <= 32, rh <= 32 { return "\(rw) : \(rh)" }
        return String(format: "%.3f", size.width / size.height)
    }

    /// Figma (top-origin): padding 28 / 24, title 20 pt on a 28 pt line, 4,
    /// folder 14, 24, then per section: caption 15, 4, rows of 32 (8 + 15 + 8 + 1 rule), 24.
    override func draw(_ dirtyRect: NSRect) {
        let x = Self.padX
        let width = bounds.width - x * 2
        InspectText.draw(title, in: NSRect(x: x, y: 28, width: width - InspectLayout.controlSize - 8, height: 28),
                         font: PanelStyle.titleFont(ofSize: 20), color: InspectInk.text1, truncation: .byTruncatingMiddle)
        InspectText.draw(folder, in: NSRect(x: x, y: 60, width: width, height: 14),
                         font: Self.valueFont, color: InspectInk.text3, truncation: .byTruncatingMiddle)
        var y: CGFloat = 60 + 14 + 24
        for (caption, rows) in sections {
            InspectText.draw(caption, in: NSRect(x: x, y: y, width: width, height: 15),
                             font: Self.keyFont, color: InspectInk.text3)
            y += 15 + 4
            for (key, value) in rows {
                let keyWidth = min(width * 0.45, InspectText.width(key, font: Self.keyFont))
                InspectText.draw(key, in: NSRect(x: x, y: y + 8, width: keyWidth, height: 15),
                                 font: Self.keyFont, color: InspectInk.text3)
                let valueX = x + keyWidth + 8
                InspectText.draw(value, in: NSRect(x: valueX, y: y + 8.5, width: max(0, x + width - valueX), height: 14),
                                 font: Self.valueFont, color: InspectInk.text1, align: .right,
                                 truncation: .byTruncatingMiddle)
                InspectInk.line.setFill()
                NSRect(x: x, y: y + 31, width: width, height: 1).fill()
                y += 32
            }
            y += 24
        }
    }

    /// Height the content needs (used to size the panel).
    static var contentHeight: CGFloat { 60 + 14 + 24 + 3 * (15 + 4 + 24) + 9 * 32 }
}

/// Image Information as its own child window attached to the right edge of
/// the Image Inspect window: the Figma 320 pt ink/1 panel, top-aligned.
final class ImageInfoPanel: NSPanel {
    private static let panelWidth: CGFloat = 320
    private static let panelHeight: CGFloat = FigmaImageInspectorView.contentHeight
    private weak var attachedParent: NSWindow?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
                   styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        appearance = PanelStyle.windowAppearance
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = NSView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight))
        root.wantsLayer = true
        root.layer?.backgroundColor = PanelStyle.resolvedCG(InspectInk.ink1)
        root.layer?.cornerRadius = PanelStyle.Radius.window
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
        root.autoresizingMask = [.width, .height]
        contentView = root
    }

    func setContent(_ view: NSView) {
        guard let root = contentView else { return }
        if view.superview !== root {
            view.removeFromSuperview()
            view.frame = root.bounds
            view.autoresizingMask = [.width, .height]
            root.addSubview(view)
        }
    }

    func present(alongside parent: NSWindow) {
        if let old = attachedParent, old !== parent { old.removeChildWindow(self) }
        attachedParent = parent
        position(alongside: parent)
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        if let parent = attachedParent { parent.removeChildWindow(self) }
        orderOut(nil)
    }

    private func position(alongside parent: NSWindow) {
        let gap: CGFloat = 2
        let width = Self.panelWidth
        let height = Self.panelHeight
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        var x = parent.frame.maxX + gap
        if x + width > visible.maxX { x = max(visible.minX, parent.frame.minX - width - gap) }
        x = max(visible.minX, min(x, visible.maxX - width))
        // Align the panel to the parent's top edge, as the Figma side panel.
        let y = max(visible.minY, min(parent.frame.maxY - height, visible.maxY - height))
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        contentView?.layoutSubtreeIfNeeded()
        invalidateShadow()
    }
}

/// One image's full metadata as a self-contained block. A soft glowing border
/// can be toggled so the user sees which on-screen image this block describes.
final class ImageInfoBlock: NSView {
    /// Fixed card width, also used by ImageDifferencePanel for the width
    /// constraint, so column math here always matches the rendered width.
    /// 260 = 280pt inspector minus the panel's 10pt horizontal padding.
    static let cardWidth: CGFloat = 260

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
        PanelStyle.styleScrollers(in: scroll)
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
