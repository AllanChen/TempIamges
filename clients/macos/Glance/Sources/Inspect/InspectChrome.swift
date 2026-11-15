import AppKit

/// Floating capsule with three text segments (Focus / Side by Side / Slider),
/// anchored to the canvas' top-left corner (spec `.canvas-mode`).
final class CanvasModeSwitcher: NSView {
    var onSelect: ((Int) -> Void)?

    private let buttons: [NSButton]
    private var activeIndex = 0
    private static func titles() -> [String] {
        ["Focus".localized, "Compare".localized, "Slider".localized]
    }

    override init(frame frameRect: NSRect) {
        buttons = Self.titles().enumerated().map { index, title in
            PanelStyle.makeSegmentButton(title: title, target: nil, action: nil)
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        for (index, button) in buttons.enumerated() {
            if let button = button as? PanelButton {
                button.titleFont = PanelStyle.inspectFont(ofSize: 12, weight: .medium)
            }
            button.tag = index
            button.target = self
            button.action = #selector(segmentTapped(_:))
            addSubview(button)
        }
        setActive(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var fittingSize: NSSize {
        NSSize(width: 318, height: 38)
    }

    override func layout() {
        super.layout()
        let designWidths: [CGFloat] = [96, 112, 94]
        let scale = bounds.width / 318
        var x: CGFloat = 0
        for (button, designWidth) in zip(buttons, designWidths) {
            let width = designWidth * scale
            if let button = button as? PanelButton {
                button.titleFont = PanelStyle.inspectFont(ofSize: 12 * scale, weight: .medium)
                button.layer?.cornerRadius = 8 * scale
                button.layer?.borderWidth = max(1, scale)
            }
            button.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
            x += width + 8 * scale
        }
    }

    @objc private func segmentTapped(_ sender: NSButton) {
        onSelect?(sender.tag)
    }

    func setActive(_ index: Int) {
        activeIndex = index
        for (i, button) in buttons.enumerated() {
            PanelStyle.setSegmentActive(button, active: i == index)
        }
    }

    func setFocusEnabled(_ enabled: Bool) { buttons[0].isEnabled = enabled }
    func setCompareEnabled(_ enabled: Bool) {
        buttons[1].isEnabled = enabled
        buttons[2].isEnabled = enabled
    }

    func reloadTitles() {
        for (button, title) in zip(buttons, Self.titles()) {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: PanelStyle.inspectFont(ofSize: 12, weight: .medium),
                             .foregroundColor: PanelStyle.textSecondary]
            )
            button.setAccessibilityLabel(title)
        }
        // Reapply selected styling because attributedTitle resets the visible
        // text color until the next mode transition.
        setActive(activeIndex)
        needsLayout = true
    }
}

/// Non-blocking task toast pinned to the canvas' bottom-left corner
/// (spec `.task-toast`): spinner + task name + reassurance copy.
final class TaskToastView: NSView {
    private let spinner = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = PanelStyle.resolvedCG(PanelStyle.themed(NSColor(srgbRed: 27 / 255, green: 29 / 255, blue: 32 / 255, alpha: 1), PanelStyle.Washi.ink1))
        layer?.cornerRadius = PanelStyle.cornerMedium
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = PanelStyle.accent.cgColor

        spinner.wantsLayer = true
        spinner.layer?.backgroundColor = PanelStyle.resolvedCG(
            PanelStyle.themed(NSColor(srgbRed: 58 / 255, green: 44 / 255, blue: 38 / 255, alpha: 1), PanelStyle.Washi.ink3)
        )
        spinner.layer?.cornerRadius = 15
        addSubview(spinner)

        titleLabel.font = PanelStyle.inspectFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = PanelStyle.textPrimary
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.font = PanelStyle.inspectFont(ofSize: 11)
        subtitleLabel.textColor = PanelStyle.textSecondary
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let scale = min(bounds.width / 460, bounds.height / 76)
        layer?.cornerRadius = 12 * scale
        layer?.borderWidth = max(1, scale)
        spinner.layer?.cornerRadius = 15 * scale
        titleLabel.font = PanelStyle.inspectFont(ofSize: 14 * scale, weight: .semibold)
        subtitleLabel.font = PanelStyle.inspectFont(ofSize: 11 * scale)
        spinner.frame = NSRect(x: 20 * scale, y: 23 * scale, width: 30 * scale, height: 30 * scale)
        titleLabel.frame = NSRect(x: 66 * scale, y: 41 * scale,
                                  width: bounds.width - 86 * scale, height: 17 * scale)
        subtitleLabel.frame = NSRect(x: 66 * scale, y: 21 * scale,
                                     width: bounds.width - 86 * scale, height: 13 * scale)
    }

    func show(title: String, subtitle: String) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        if isHidden {
            isHidden = false
            alphaValue = 0
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard !isHidden else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.isHidden = true
        }
    }
}

final class InspectNonHitTestingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Figma V3's transparent drag region keeps native dragging without drawing a
/// second chrome band above the image.
final class FigmaInspectTitlebar: NSView {
    /// The bar is transparent over the image. Text beneath it must remain
    /// selectable while the rest of the bar still drags the window.
    var passesThroughTextAtPoint: ((NSPoint) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === self, passesThroughTextAtPoint?(point) == true { return nil }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

/// The solid top bar of the Inspect window. Only its controls take clicks; everything else falls through
/// to the drag region behind it, so dragging and double-click-to-zoom keep working.
final class InspectTopBar: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

final class InspectIdentityBar: NSVisualEffectView {
    private let tintLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = PanelStyle.vibrantAppearance
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
    var usesFigmaStyle = false { didSet { updateAppearance() } }
    var isBorderlessFigmaTile = false { didSet { updateAppearance() } }
    /// Figma Shizuka `IconButton`: a 28 pt tile with a 16 pt line glyph,
    /// ink/4 when selected and a quiet wash on hover.
    var usesShizukaStyle = false {
        didSet {
            guard usesShizukaStyle != oldValue else { return }
            symbolWeight = usesShizukaStyle ? .regular : .light
            symbolPointSize = usesShizukaStyle ? 13 : 18
            if designIconName == nil { setSymbol(currentSymbolName) } else { updateDesignIconSize() }
            layer?.cornerRadius = usesShizukaStyle ? PanelStyle.Radius.control : 5
            updateTrackingAreas()
            updateAppearance()
        }
    }
    private var hovering = false
    private var hoverArea: NSTrackingArea?
    private var symbolWeight: NSFont.Weight = .light

    /// The glyph point size. The toolbar drives this from the tile size so the
    /// icon always fills the same proportion of its 38pt tile (18/38) as the
    /// Figma reference, at any window/image size. Centered via `.imageOnly`.
    private var symbolPointSize: CGFloat = 18
    private var currentSymbolName: String = ""
    private var designIconName: String?

    private var glyphConfiguration: NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: symbolWeight)
    }

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
        currentSymbolName = symbol
        setSymbol(symbol)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Swap the icon while keeping the shared symbol configuration. Use this
    /// instead of assigning `image` directly so dynamically swapped icons
    /// (play/pause, mute) match the rest of the toolbar.
    func setSymbol(_ name: String) {
        currentSymbolName = name
        designIconName = nil
        let raw = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)
        image = raw?.withSymbolConfiguration(glyphConfiguration)
    }

    /// Use the vector exported by the Glance Figma design for the floating toolbar.
    func setDesignIcon(_ name: String) {
        designIconName = name
        updateDesignIconSize()
        updateAppearance()
    }

    private func updateDesignIconSize() {
        guard let designIconName,
              let icon = NSImage(named: NSImage.Name(designIconName))?.copy() as? NSImage else { return }
        icon.isTemplate = true
        // Shizuka tiles carry Figma's 16 pt line icons at their drawn size.
        let side = usesShizukaStyle ? 16 : symbolPointSize
        icon.size = NSSize(width: side, height: side)
        image = icon
    }

    /// Resize the glyph so it scales with its tile. No-op if unchanged, so it's
    /// cheap to call from every layout pass.
    func setSymbolPointSize(_ size: CGFloat) {
        let clamped = max(8, size)
        guard abs(clamped - symbolPointSize) > 0.5 else { return }
        symbolPointSize = clamped
        if designIconName == nil {
            setSymbol(currentSymbolName)
        } else {
            updateDesignIconSize()
        }
    }

    func updateTooltip(_ tooltip: String) {
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func mouseDown(with event: NSEvent) {
        if usesFigmaStyle { ActionMenuPanel.animateMoreButtonPress(self) }
        super.mouseDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
        guard usesShizukaStyle else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hovering = false
        updateAppearance()
    }

    private func updateAppearance() {
        if usesShizukaStyle {
            let fill: NSColor = isActive ? InspectInk.ink4 : (hovering && isEnabled ? PanelStyle.controlFill : .clear)
            layer?.backgroundColor = PanelStyle.resolvedCG(fill)
            layer?.borderWidth = 0
            contentTintColor = isEnabled ? (isActive || hovering ? InspectInk.text1 : InspectInk.text2) : InspectInk.text3
            alphaValue = isEnabled ? 1 : 0.45
            return
        }
        if usesFigmaStyle && PanelStyle.isLight {
            // Washi: no tile outline; the selected tool sits on a quiet paper fill.
            layer?.backgroundColor = PanelStyle.resolvedCG(isActive ? PanelStyle.Washi.ink4 : .clear)
            layer?.borderWidth = 0
            contentTintColor = isEnabled
                ? (isActive ? PanelStyle.Washi.text1 : PanelStyle.Washi.text2)
                : PanelStyle.textTertiary
            alphaValue = isEnabled ? 1 : 0.45
            return
        }
        if usesFigmaStyle {
            let idleFill = NSColor(srgbRed: 29 / 255, green: 30 / 255, blue: 34 / 255, alpha: 0.72)
            let activeFill = NSColor(srgbRed: 52 / 255, green: 37 / 255, blue: 31 / 255, alpha: 0.96)
            layer?.backgroundColor = PanelStyle.resolvedCG(
                isActive ? activeFill : idleFill
            )
            layer?.borderWidth = isBorderlessFigmaTile ? 0 : 1
            layer?.borderColor = PanelStyle.resolvedCG(
                isActive ? PanelStyle.accent.withAlphaComponent(0.78) : NSColor.white.withAlphaComponent(0.12)
            )
            let idleTint = designIconName == nil
                ? PanelStyle.textPrimary
                : NSColor(srgbRed: 243 / 255, green: 243 / 255, blue: 243 / 255, alpha: 1)
            contentTintColor = isEnabled
                ? (isActive ? PanelStyle.accent : idleTint)
                : PanelStyle.textTertiary
            alphaValue = isEnabled ? 1 : 0.45
            return
        }
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

// MARK: - Shizuka chrome (Figma `03 · Image Inspect / Focus`)

/// Ink and text tokens of the Shizuka Image Inspect frames, resolved through
/// PanelStyle so Sumi and Washi follow the theme.
enum InspectInk {
    static let ink0 = PanelStyle.inspectCanvas
    static let ink1 = PanelStyle.inspectChrome
    static let ink2 = PanelStyle.inspectStatus
    static let ink3 = PanelStyle.inspectToolbar
    static let ink4 = PanelStyle.surfaceElevated
    static let line = PanelStyle.themed(PanelStyle.Sumi.line, PanelStyle.Washi.line)
    static let lineStrong = PanelStyle.inspectLine
    static let text1 = PanelStyle.textPrimary
    static let text2 = PanelStyle.textSecondary
    static let text3 = PanelStyle.textTertiary
    static let text4 = PanelStyle.themed(PanelStyle.Sumi.text4, PanelStyle.Washi.text4)
}

/// Fixed geometry of the Shizuka viewer frame (top-origin Figma values).
enum InspectLayout {
    static let titlebarHeight: CGFloat = 44
    /// Filmstrip row (48) with 22 pt above and below it.
    static let bottomBarHeight: CGFloat = 92
    static let filmstripBottom: CGFloat = 22
    static let controlSize: CGFloat = 28
    static let thumbSize: CGFloat = 48
    static let thumbGap: CGFloat = 8
    /// Room above the thumbnails for the compare A/B captions and corner marks.
    static let filmstripHeadroom: CGFloat = 18
    static let sideInset: CGFloat = 28
}

/// Text drawn into a fixed Figma text frame (top-origin, `leading: normal`).
enum InspectText {
    static func attributes(_ font: NSFont, _ color: NSColor, align: NSTextAlignment = .left,
                           truncation: NSLineBreakMode = .byTruncatingTail) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = truncation
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }

    static func draw(_ string: String, in rect: CGRect, font: NSFont, color: NSColor,
                     align: NSTextAlignment = .left, truncation: NSLineBreakMode = .byTruncatingTail) {
        guard !string.isEmpty, rect.width > 0 else { return }
        NSAttributedString(string: string, attributes: attributes(font, color, align: align, truncation: truncation))
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    static func width(_ string: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
    }
}

/// A borderless text control (Figma text links such as `Fit`, `Slider`,
/// `Cancel`). Draws its title inside the exact frame it is given.
final class InspectTextButton: NSControl {
    var title: String { didSet { setAccessibilityLabel(title); needsDisplay = true } }
    var textFont: NSFont { didSet { needsDisplay = true } }
    var textColor: NSColor { didSet { needsDisplay = true } }
    var hoverColor = PanelStyle.textPrimary
    var textAlignment: NSTextAlignment = .left { didSet { needsDisplay = true } }
    var onPress: (() -> Void)?
    private var hovering = false
    private var area: NSTrackingArea?

    init(title: String, font: NSFont, color: NSColor) {
        self.title = title
        textFont = font
        textColor = color
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var preferredWidth: CGFloat { InspectText.width(title, font: textFont) }

    override func draw(_ dirtyRect: NSRect) {
        let color = !isEnabled ? InspectInk.text4 : (hovering ? hoverColor : textColor)
        InspectText.draw(title, in: bounds, font: textFont, color: color, align: textAlignment)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
        area = tracking
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?()
        return true
    }
}

/// Figma `task chip`: ink/3 capsule, a 5 pt ai dot and "1 task" (12 pt text/2).
final class InspectTaskChip: NSControl {
    var onPress: (() -> Void)?
    private(set) var text = ""
    private static let font = PanelStyle.inspectFont(ofSize: 12)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func setCount(_ count: Int) {
        text = count == 1 ? "1 task".localized : String(format: "%d tasks".localized, count)
        setAccessibilityLabel(text)
        toolTip = "Tasks".localized
        needsDisplay = true
    }

    /// Padding 10 × 4, dot 5, gap 6, 12 pt label.
    var preferredSize: NSSize {
        NSSize(width: 10 + 5 + 6 + InspectText.width(text, font: Self.font) + 10, height: 23)
    }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        InspectInk.ink3.setFill()
        capsule.fill()
        PanelStyle.info.setFill()
        NSBezierPath(ovalIn: NSRect(x: 10, y: (bounds.height - 5) / 2, width: 5, height: 5)).fill()
        InspectText.draw(text, in: NSRect(x: 21, y: 4, width: bounds.width - 31, height: 15),
                         font: Self.font, color: InspectInk.text2)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }
}

/// Figma compare `label`: ink/0 tag with the slot letter (mono 11, text/1)
/// and the file name (11 pt, text/2), pinned to a corner of each image.
final class InspectCompareTag: NSView {
    private var letter = ""
    private var name = ""
    private static let letterFont = PanelStyle.monoFont(ofSize: 11)
    private static let nameFont = PanelStyle.inspectFont(ofSize: 11)
    private static let maxNameWidth: CGFloat = 180

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(letter: String, name: String) {
        guard letter != self.letter || name != self.name else { return }
        self.letter = letter
        self.name = name
        setAccessibilityElement(true)
        setAccessibilityLabel("\(letter) \(name)")
        needsDisplay = true
    }

    /// Padding 8 × 4 and a 6 pt gap between the letter and the name.
    var preferredSize: NSSize {
        let nameWidth = min(Self.maxNameWidth, InspectText.width(name, font: Self.nameFont))
        return NSSize(width: 8 + InspectText.width(letter, font: Self.letterFont)
                        + (name.isEmpty ? 0 : 6 + nameWidth) + 8, height: 21)
    }

    override func draw(_ dirtyRect: NSRect) {
        InspectInk.ink0.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let letterWidth = InspectText.width(letter, font: Self.letterFont)
        InspectText.draw(letter, in: NSRect(x: 8, y: 4, width: letterWidth, height: 13),
                         font: Self.letterFont, color: InspectInk.text1)
        let nameX = 8 + letterWidth + 6
        InspectText.draw(name, in: NSRect(x: nameX, y: 4, width: max(0, bounds.width - nameX - 8), height: 13),
                         font: Self.nameFont, color: InspectInk.text2, truncation: .byTruncatingMiddle)
    }
}

/// The Shizuka bottom bar: file info on the left (name 13 pt, metadata in
/// mono), and on the right either the zoom state with the position, or the
/// compare-style switch. The filmstrip floats in its centre as a sibling.
final class InspectBottomBar: NSView {
    var onFit: (() -> Void)?
    var onComparisonStyle: ((ImageInspectSession.ComparisonStyle) -> Void)?
    /// The left info may not run under the filmstrip.
    var infoLimitX: CGFloat = .greatestFiniteMagnitude { didSet { needsDisplay = true } }

    private enum Content { case single(name: String, meta: String), pair(a: String, b: String) }
    private var content = Content.single(name: "", meta: "")
    private var position: String?
    private let zoomButton = InspectTextButton(title: "Fit".localized, font: PanelStyle.inspectFont(ofSize: 12),
                                               color: InspectInk.text2)
    private let sliderButton = InspectTextButton(title: "Slider".localized, font: PanelStyle.inspectFont(ofSize: 12),
                                                 color: InspectInk.text3)
    private let sideBySideButton = InspectTextButton(title: "Side by side".localized,
                                                     font: PanelStyle.inspectFont(ofSize: 12), color: InspectInk.text3)
    private var comparing = false
    private var style = ImageInspectSession.ComparisonStyle.sideBySide
    private static let nameFont = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
    private static let pairBFont = PanelStyle.inspectFont(ofSize: 13)
    private static let monoFont = PanelStyle.monoFont(ofSize: 11)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        zoomButton.toolTip = "Fit to window".localized
        zoomButton.onPress = { [weak self] in self?.onFit?() }
        sliderButton.onPress = { [weak self] in self?.onComparisonStyle?(.slider) }
        sideBySideButton.onPress = { [weak self] in self?.onComparisonStyle?(.sideBySide) }
        for view in [zoomButton, sliderButton, sideBySideButton] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    /// Only the text controls take clicks; empty bar space falls through to the window.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    func showSingle(name: String, meta: String, zoom: String, position: String?) {
        content = .single(name: name, meta: meta)
        setAccessibilityLabel([name, meta, position].compactMap { $0 }.joined(separator: ", "))
        self.position = position
        comparing = false
        zoomButton.title = zoom
        updateControls()
    }

    func showPair(a: String, b: String, style: ImageInspectSession.ComparisonStyle) {
        content = .pair(a: a, b: b)
        setAccessibilityLabel("A \(a), B \(b)")
        position = nil
        comparing = true
        self.style = style
        updateControls()
    }

    func reloadTitles() {
        sliderButton.title = "Slider".localized
        sideBySideButton.title = "Side by side".localized
        zoomButton.toolTip = "Fit to window".localized
        needsLayout = true
    }

    private func updateControls() {
        zoomButton.isHidden = comparing || zoomButton.title.isEmpty
        sliderButton.isHidden = !comparing
        sideBySideButton.isHidden = !comparing
        for (button, active) in [(sliderButton, style == .slider), (sideBySideButton, style == .sideBySide)] {
            button.textFont = PanelStyle.inspectFont(ofSize: 12, weight: active ? .medium : .regular)
            button.textColor = active ? InspectInk.text1 : InspectInk.text3
            button.setAccessibilitySelected(active)
        }
        needsLayout = true
        needsDisplay = true
    }

    /// Left edge of the right-hand controls, so the file info stops before them.
    private var rightContentMinX: CGFloat = .greatestFiniteMagnitude

    override func layout() {
        super.layout()
        // Right controls in Figma: text frames at y 45 (15 pt high), 28 pt from the edge.
        let right = bounds.width - InspectLayout.sideInset
        if comparing {
            let sideWidth = sideBySideButton.preferredWidth
            let sliderWidth = sliderButton.preferredWidth
            sideBySideButton.frame = NSRect(x: right - sideWidth, y: 45, width: sideWidth, height: 15)
            sliderButton.frame = NSRect(x: sideBySideButton.frame.minX - 18 - sliderWidth, y: 45,
                                        width: sliderWidth, height: 15)
            rightContentMinX = sliderButton.frame.minX
        } else {
            let positionWidth = position.map { InspectText.width($0, font: Self.monoFont) } ?? 0
            let zoomRight = position == nil ? right : right - positionWidth - 20
            let zoomWidth = zoomButton.preferredWidth
            zoomButton.frame = NSRect(x: zoomRight - zoomWidth, y: 45, width: zoomWidth, height: 15)
            rightContentMinX = !zoomButton.isHidden ? zoomButton.frame.minX
                : position == nil ? bounds.width : right - positionWidth
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let left = InspectLayout.sideInset
        let limit = max(left, min(infoLimitX, rightContentMinX - 16))
        let width = max(0, limit - left)
        switch content {
        case .single(let name, let meta):
            InspectText.draw(name, in: NSRect(x: left, y: 29, width: width, height: 16), font: Self.nameFont,
                             color: InspectInk.text1, truncation: .byTruncatingMiddle)
            InspectText.draw(meta, in: NSRect(x: left, y: 50, width: width, height: 14), font: Self.monoFont,
                             color: InspectInk.text3)
            if let position {
                let positionWidth = InspectText.width(position, font: Self.monoFont)
                InspectText.draw(position, in: NSRect(x: bounds.width - InspectLayout.sideInset - positionWidth,
                                                      y: 45.5, width: positionWidth, height: 14),
                                 font: Self.monoFont, color: InspectInk.text3)
            }
        case .pair(let a, let b):
            for (index, (letter, name)) in [("A", a), ("B", b)].enumerated() {
                let y: CGFloat = index == 0 ? 27 : 48
                let letterWidth = InspectText.width(letter, font: Self.monoFont)
                InspectText.draw(letter, in: NSRect(x: left, y: y + 1.5, width: letterWidth, height: 14),
                                 font: Self.monoFont, color: InspectInk.text3)
                let nameX = left + letterWidth + 8
                InspectText.draw(name, in: NSRect(x: nameX, y: y, width: max(0, limit - nameX), height: 16),
                                 font: index == 0 ? Self.nameFont : Self.pairBFont,
                                 color: index == 0 ? InspectInk.text1 : InspectInk.text2,
                                 truncation: .byTruncatingMiddle)
            }
        }
    }
}

/// Figma `26 · Image Inspect / Load error`: a dashed frame over the stage with
/// a vermilion mark, a Mincho title, the explanation and recovery buttons.
final class InspectLoadErrorView: NSView {
    var onReveal: (() -> Void)?
    var onRetry: (() -> Void)?
    private var title = ""
    private var message = ""
    private let border = CAShapeLayer()
    private let revealButton = InspectLoadErrorView.makeButton("Reveal in Finder".localized)
    private let retryButton = InspectLoadErrorView.makeButton("Try again".localized)
    private static let titleFont = PanelStyle.titleFont(ofSize: 24)
    private static let bodyFont = PanelStyle.inspectFont(ofSize: 13)
    private static let bodyWidth: CGFloat = 460

    private static func makeButton(_ title: String) -> PanelButton {
        let button = PanelStyle.makeQuietButton(title: title, target: nil, action: nil)
        button.normalBackground = .clear
        button.hoverBackground = PanelStyle.controlFill
        button.titleFont = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        button.layer?.cornerRadius = PanelStyle.Radius.control
        button.layer?.borderColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
        return button
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        border.fillColor = nil
        border.strokeColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
        border.lineWidth = 1
        border.lineDashPattern = [3, 3]
        layer?.addSublayer(border)
        revealButton.target = self
        revealButton.action = #selector(revealTapped)
        retryButton.target = self
        retryButton.action = #selector(retryTapped)
        addSubview(revealButton)
        addSubview(retryButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    /// Only the buttons take clicks; right-clicks and drops reach the viewport beneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    func configure(filename: String, canReveal: Bool, canBrowse: Bool) {
        title = String(format: "Couldn’t open %@".localized, filename)
        var text = "Glance couldn’t read this image. The file may be damaged or in a format it can’t decode.".localized
        if canBrowse { text += " " + "Use ← → to keep browsing.".localized }
        message = text
        revealButton.isHidden = !canReveal
        setAccessibilityLabel(title + ". " + message)
        needsLayout = true
        needsDisplay = true
    }

    func reloadTitles() {
        for (button, title) in [(revealButton, "Reveal in Finder".localized), (retryButton, "Try again".localized)] {
            button.title = title
            button.titleFont = PanelStyle.inspectFont(ofSize: 13, weight: .medium)
        }
        needsLayout = true
    }

    private var bodyHeight: CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.minimumLineHeight = 21
        style.maximumLineHeight = 21
        let text = NSAttributedString(string: message, attributes: [.font: Self.bodyFont, .paragraphStyle: style])
        return ceil(text.boundingRect(with: NSSize(width: min(Self.bodyWidth, bounds.width - 32), height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin]).height)
    }

    /// Dot 6, 16 pt gap, title 32, 8, body, 8 + 14, buttons 32.
    private var blockTop: CGFloat {
        let total = 6 + 16 + 32 + 8 + bodyHeight + 22 + 32
        return max(0, (bounds.height - total) / 2)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        border.frame = bounds
        border.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 4, cornerHeight: 4, transform: nil)
        CATransaction.commit()
        let buttonsY = blockTop + 6 + 16 + 32 + 8 + bodyHeight + 22
        let buttons = [revealButton, retryButton].filter { !$0.isHidden }
        let widths = buttons.map { InspectText.width($0.title, font: PanelStyle.inspectFont(ofSize: 13, weight: .medium)) + 32 }
        var x = (bounds.width - widths.reduce(0, +) - CGFloat(max(0, buttons.count - 1)) * 8) / 2
        for (button, width) in zip(buttons, widths) {
            button.frame = NSRect(x: x, y: buttonsY, width: width, height: 32)
            x += width + 8
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let top = blockTop
        PanelStyle.failure.setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - 3, y: top, width: 6, height: 6)).fill()
        InspectText.draw(title, in: NSRect(x: 16, y: top + 22, width: bounds.width - 32, height: 32),
                         font: Self.titleFont, color: InspectInk.text1, align: .center, truncation: .byTruncatingMiddle)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.minimumLineHeight = 21
        style.maximumLineHeight = 21
        let bodyWidth = min(Self.bodyWidth, bounds.width - 32)
        NSAttributedString(string: message, attributes: [.font: Self.bodyFont, .foregroundColor: InspectInk.text2,
                                                         .paragraphStyle: style])
            .draw(with: NSRect(x: (bounds.width - bodyWidth) / 2, y: top + 62, width: bodyWidth, height: bodyHeight),
                  options: [.usesLineFragmentOrigin])
    }

    @objc private func revealTapped() { onReveal?() }
    @objc private func retryTapped() { onRetry?() }
}

/// A label whose text frame is exactly its bounds (top-origin, Figma
/// `leading: normal`), instead of NSTextField's cell padding and baseline.
final class InspectTextLabel: NSView {
    var string: String { didSet { setAccessibilityLabel(string); needsDisplay = true } }
    var font: NSFont { didSet { needsDisplay = true } }
    var textColor: NSColor { didSet { needsDisplay = true } }
    var alignment: NSTextAlignment = .left { didSet { needsDisplay = true } }
    var truncation: NSLineBreakMode = .byTruncatingTail { didSet { needsDisplay = true } }

    init(_ string: String, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        self.string = string
        self.font = font
        textColor = color
        self.alignment = alignment
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(string)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var preferredWidth: CGFloat { InspectText.width(string, font: font) }

    override func draw(_ dirtyRect: NSRect) {
        InspectText.draw(string, in: bounds, font: font, color: textColor, align: alignment, truncation: truncation)
    }
}

/// Figma `Button` variants for dialogs: Primary (text/1 fill, ink/0 label) and
/// Quiet (line/strong rule), 32 pt high, 16 pt side padding, 13 pt medium.
enum InspectDialogButton {
    static let font = PanelStyle.inspectFont(ofSize: 13, weight: .medium)

    static func make(_ title: String, primary: Bool, target: AnyObject?, action: Selector?) -> PanelButton {
        let button = PanelButton(title: title, target: target, action: action)
        button.titleFont = font
        button.layer?.cornerRadius = PanelStyle.Radius.control
        if primary {
            button.normalBackground = InspectInk.text1
            button.hoverBackground = PanelStyle.accentHover
            button.titleColor = PanelStyle.accentInk
            button.layer?.borderWidth = 0
        } else {
            button.normalBackground = .clear
            button.hoverBackground = PanelStyle.controlFill
            button.titleColor = InspectInk.text1
            button.layer?.borderWidth = 1
            button.layer?.borderColor = PanelStyle.resolvedCG(InspectInk.lineStrong)
        }
        button.setAccessibilityLabel(title)
        return button
    }

    static func width(_ title: String) -> CGFloat { InspectText.width(title, font: font) + 32 }
}

/// Figma dialog key/value row: 13 pt text/3 key, 12 pt mono value, 8 pt
/// vertical padding and a line/hair rule along the foot (33 pt high).
final class InspectDialogRow: NSView {
    var key: String { didSet { needsDisplay = true } }
    var value = "" { didSet { setAccessibilityValue(value); needsDisplay = true } }
    var valueColor = InspectInk.text1 { didSet { needsDisplay = true } }

    init(key: String) {
        self.key = key
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(key)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let keyFont = PanelStyle.inspectFont(ofSize: 13)
        let keyWidth = min(bounds.width * 0.5, InspectText.width(key, font: keyFont))
        InspectText.draw(key, in: NSRect(x: 0, y: 8, width: keyWidth, height: 16), font: keyFont, color: InspectInk.text3)
        InspectText.draw(value, in: NSRect(x: keyWidth + 8, y: 8.5, width: max(0, bounds.width - keyWidth - 8), height: 15),
                         font: PanelStyle.monoFont(ofSize: 12), color: valueColor, align: .right)
        InspectInk.line.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

/// Flipped content plane for Figma-positioned dialogs.
final class InspectDialogContentView: NSView {
    override var isFlipped: Bool { true }
}
