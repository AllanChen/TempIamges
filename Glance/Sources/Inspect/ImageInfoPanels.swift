import AppKit

/// Image Inspect's Figma-defined right inspector. Matches the
/// "Dark Refresh v3 / Image Inspect / Clean Editable" image information panel:
/// frosted dark card, title + filename hint, and two-column metadata rows.
final class FigmaImageInspectorView: NSView {
    /// The panel is a borderless child window, so it carries its own close control.
    var onClose: (() -> Void)?
    private lazy var closeButton = PanelStyle.makeIconButton(symbol: "xmark", tooltip: "Close".localized,
                                                             target: self, action: #selector(closeTapped))
    private let titleLabel = NSTextField(labelWithString: "Image information".localized)
    private let subtitleLabel = NSTextField(labelWithString: "")
    // Figma panel shows six metadata rows; Alpha is omitted to match the design.
    private let keys = ["Name", "Dimensions", "Format", "File size", "Color profile", "Created"]
    private var keyLabels: [NSTextField] = []
    private var valueLabels: [NSTextField] = []
    private var dividers: [NSView] = []
    private var items: [(index: Int, info: MediaInfo, metadata: ImageTechnicalMetadata?)] = []

    // MARK: Layout metrics (points at 1×, matching Figma)
    private let padX: CGFloat = 23
    private let rowInsetX: CGFloat = 35
    private let rowValueX: CGFloat = 173
    private let headerTop: CGFloat = 23
    private let headerDividerY: CGFloat = 81
    private let rowStartY: CGFloat = 111
    private let rowHeight: CGFloat = 46

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.font = PanelStyle.inspectFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        addSubview(titleLabel)
        addSubview(closeButton)

        subtitleLabel.font = PanelStyle.inspectFont(ofSize: 11)
        subtitleLabel.textColor = PanelStyle.textSecondary
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitleLabel)

        for key in keys {
            let keyLabel = NSTextField(labelWithString: key.localized)
            keyLabel.font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
            keyLabel.textColor = PanelStyle.textTertiary
            addSubview(keyLabel)
            keyLabels.append(keyLabel)

            let valueLabel = NSTextField(labelWithString: "—")
            valueLabel.font = PanelStyle.inspectFont(ofSize: 13)
            valueLabel.textColor = PanelStyle.textPrimary
            valueLabel.lineBreakMode = .byTruncatingMiddle
            valueLabel.isSelectable = true
            addSubview(valueLabel)
            valueLabels.append(valueLabel)

            let divider = NSView()
            divider.wantsLayer = true
            divider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.inspectLine)
            addSubview(divider)
            dividers.append(divider)
        }
        // One extra divider for the header separator (white at 12% opacity).
        let headerDivider = NSView()
        headerDivider.wantsLayer = true
        addSubview(headerDivider)
        dividers.insert(headerDivider, at: 0)

    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        func topFrame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x, y: bounds.height - y - h, width: w, height: h)
        }

        let closeSize: CGFloat = 24
        closeButton.frame = topFrame(bounds.width - padX - closeSize, headerTop - 2, closeSize, closeSize)
        titleLabel.frame = topFrame(padX, headerTop, bounds.width - padX * 2 - closeSize - 8, 21)
        subtitleLabel.frame = topFrame(padX, headerTop + 28, bounds.width - padX * 2 - closeSize - 8, 13)

        let headerDivider = dividers[0]
        headerDivider.layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.textPrimary.withAlphaComponent(0.12))
        headerDivider.frame = topFrame(padX, headerDividerY, bounds.width - padX * 2, 1)

        for index in keys.indices {
            let y = rowStartY + CGFloat(index) * rowHeight
            keyLabels[index].frame = topFrame(rowInsetX, y, rowValueX - rowInsetX - 8, 16)
            valueLabels[index].frame = topFrame(rowValueX, y, bounds.width - rowValueX - rowInsetX, 16)
            // Row dividers sit below each value (except we reuse the first divider
            // for the header; metadata dividers start at index 1).
            let dividerIndex = index + 1
            if dividerIndex < dividers.count {
                dividers[dividerIndex].frame = topFrame(rowInsetX, y + 30, bounds.width - rowInsetX * 2, 1)
            }
        }
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
        let dimensions = info.dimensions.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "—"
        let size = info.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
        let created: String = {
            guard info.isLocal,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: info.url.path),
                  let date = attributes[.creationDate] as? Date else { return "—" }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }()
        let values = [
            info.filename,
            dimensions,
            info.formatName.isDisplayableValue ? info.formatName : "—",
            size,
            item.metadata?.colorSpace?.isDisplayableValue == true ? item.metadata!.colorSpace! : "—",
            created
        ]
        for (label, value) in zip(valueLabels, values) { label.stringValue = value }
        subtitleLabel.stringValue = info.filename
    }
}

/// Image Information as its own frosted child window, attached to the right edge
/// of the Image Inspect window — matches the Figma panel exactly.
final class ImageInfoPanel: NSPanel {
    private static let panelWidth: CGFloat = 372
    /// The card ends with the last metadata row: its divider finishes at y 372
    /// (rowStartY 111 + 5 rows × 46 + 30 + 1) plus a 24pt bottom margin that
    /// mirrors the 23pt header margin. The old 684 height reserved space for
    /// the Quick Actions buttons, which no longer exist.
    private static let panelHeight: CGFloat = 396
    private weak var attachedParent: NSWindow?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
                   styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Outer wrapper casts the Figma shadow; inner content clips the frost.
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight))
        wrapper.wantsLayer = true
        wrapper.layer?.masksToBounds = false
        wrapper.layer?.shadowColor = NSColor.black.withAlphaComponent(0.32).cgColor
        wrapper.layer?.shadowOffset = CGSize(width: 0, height: -12)
        wrapper.layer?.shadowRadius = 28
        wrapper.layer?.shadowOpacity = 1

        let root = NSView(frame: wrapper.bounds)
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        root.autoresizingMask = [.width, .height]
        wrapper.addSubview(root)

        // Frosted base: NSVisualEffectView samples from behind the panel, and a
        // tint layer biases it toward the Figma rgba(22,23,25,0.92) fill.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        blur.frame = root.bounds
        blur.autoresizingMask = [.width, .height]
        root.addSubview(blur)

        let tint = CALayer()
        tint.backgroundColor = NSColor(srgbRed: 22 / 255, green: 23 / 255, blue: 25 / 255, alpha: 0.92).cgColor
        tint.cornerRadius = 16
        tint.frame = root.bounds
        tint.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        blur.layer?.addSublayer(tint)

        contentView = wrapper
    }

    func setContent(_ view: NSView) {
        guard let wrapper = contentView,
              let root = wrapper.subviews.first else { return }
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
        // Fixed card height; just slide it up/down to stay on screen as much as
        // possible.
        // Align the child panel to the parent's top edge, matching the Figma
        // side-panel presentation rather than docking it to the bottom.
        let y = max(visible.minY, min(parent.frame.maxY - height, visible.maxY - height))
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        contentView?.layoutSubtreeIfNeeded()
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
